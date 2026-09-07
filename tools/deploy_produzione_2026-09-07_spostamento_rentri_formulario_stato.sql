/*
	Deploy produzione - 2026-09-07 - Spostamento RentriStato da tblRifiutiFormulari a tblRifiutiMovimenti

	Contenuto di questo script (solo 4_0_ecomatico - le due SP del branch @App='40' nell'hub
	condiviso 1_0_rentri sono un deploy separato, vedi tools/deploy_produzione_2026-09-07_spostamento_rentri_formulario_stato.sql
	nel repo 1_0_rentri):

	Motivazione: alcune Registrazioni hanno IdOperazione con IsFormulario=0 ma IsIntegrazioneFir=1
	(es. Operazione='C' per il Destinatario) - questi movimenti non hanno mai un proprio record in
	tblRifiutiFormulari, quindi lo stato RENTRI del formulario digitale non era mai leggibile per loro
	(il JOIN su IdMovimento non trovava nulla). Propedeutico a uno sviluppo futuro: un metodo per
	aggiornare lo stato interrogando direttamente RENTRI e la creazione di nuove Registrazioni con dati
	acquisiti da un formulario RENTRI esistente, per movimenti privi di formulario proprio.

	1) ALTER TABLE dbo.tblRifiutiMovimenti ADD (idempotente, guardato con IF NOT EXISTS):
	   - RentriFormularioStato VARCHAR(40) NULL
	   - RentriFormularioDataCopia SMALLDATETIME NULL
	   - RentriFormularioDataTrasmissione SMALLDATETIME NULL

	2) Migrazione dei valori esistenti da tblRifiutiFormulari.RentriStato/RentriDataCopia/RentriDataTrasmissione
	   a tblRifiutiMovimenti (via IdMovimento), poi DROP delle tre colonne originali da tblRifiutiFormulari.
	   Guardato con IF EXISTS sulla colonna originale + SQL dinamico, per restare sicuro anche se lo
	   script viene rieseguito per errore dopo che il passo e' gia' stato applicato.

	3) CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get: RentriFormularioStato ora letto da
	   m.RentriFormularioStato invece di f.RentriStato (nessun'altra riga cambiata). Aggiunto anche
	   l'header standard SET ANSI_NULLS/QUOTED_IDENTIFIER ON mancante (redeploy in dev l'aveva
	   rilevato con QUOTED_IDENTIFIER OFF).

	4) CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get_List: stessa sostituzione (alias
	   RentriFormularioStato, nessun'altra riga cambiata).

	5) CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_upd: @formularioRentriStato ora letto da
	   m.RentriFormularioStato invece di f.RentriStato (nessun'altra riga cambiata, la logica di
	   blocco FormularioNumero post-invio resta identica).

	6) CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_List: RentriFormularioStato ora letto
	   direttamente da m.RentriFormularioStato; rimosso il LEFT JOIN a dbo.tblRifiutiFormulari (alias
	   fdig) che serviva solo a questo scopo e che non trovava nulla per i movimenti IsIntegrazioneFir=1
	   senza formulario proprio - la causa originale del problema.

	7) CREATE OR ALTER VIEW dbo.viewRentriFormulariDigitali: colonna di output "Stato" (nome contrattuale
	   con l'hub 1_0_rentri, invariato) ora letta da m.RentriFormularioStato invece di f.RentriStato.

	Verificato su DB dev: schema aggiornato (3 colonne aggiunte su tblRifiutiMovimenti, 3 rimosse da
	tblRifiutiFormulari, 0 righe con dati da migrare in dev). Le 5 SP/vista ridistribuite senza errori
	di compilazione. Le due SP a SQL dinamico (uspRifiutiFormulari_get_List, uspRifiutiRegistrazioni_get_List)
	verificate anche eseguendo direttamente la query estratta su dati reali (nessun errore, il compilatore
	non valida il testo dinamico a CREATE time). Smoke test con sessione a basso privilegio su
	uspRifiutiFormulari_get/_get_List e uspRifiutiRegistrazioni_get_List: diniego pulito, nessun errore SQL.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-07_spostamento_rentri_formulario_stato.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) Colonne su dbo.tblRifiutiMovimenti (idempotente)
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioStato')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioStato VARCHAR(40) COLLATE Latin1_General_CI_AS NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioDataCopia')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioDataCopia SMALLDATETIME NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioDataTrasmissione')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioDataTrasmissione SMALLDATETIME NULL;
END
GO

--------------------------------------------------------------------------------
-- 2) Migrazione valori + drop colonne originali da dbo.tblRifiutiFormulari (idempotente)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiFormulari') AND name = 'RentriStato')
BEGIN
	EXEC(N'
		UPDATE m
		SET
			RentriFormularioStato = f.RentriStato,
			RentriFormularioDataCopia = f.RentriDataCopia,
			RentriFormularioDataTrasmissione = f.RentriDataTrasmissione
		FROM
			dbo.tblRifiutiMovimenti m
			INNER JOIN dbo.tblRifiutiFormulari f ON f.IdMovimento = m.Id;

		ALTER TABLE dbo.tblRifiutiFormulari DROP COLUMN RentriStato, RentriDataCopia, RentriDataTrasmissione;
	');
END
GO

--------------------------------------------------------------------------------
-- 3) dbo.uspRifiutiFormulari_get
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del
 formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = f.Id,
			IdMovimento = m.Id,
			m.IdRegistro,
			IdOperazione = ISNULL(m.IdOperazione, '0'),
			OperazioneNome = ISNULL(o.Nome, ''),
			IdEer = ISNULL(m.IdEer, '000000'),
			IdProvenienza = ISNULL(m.IdProvenienza, 'S'),
			IdStatoFisico = ISNULL(m.IdStatoFisico, '0'),
			IdAttivitaRs = ISNULL(m.IdAttivita, '00'),
			VerificatoInPartenza = ISNULL(f.VerificatoInPartenza, 0),

			IsRegistrazioneAssociata = CAST(IIF(r.Id IS NOT NULL AND r.Lock < 2, 1, 0) AS BIT),
			RegistrazioneData = ISNULL(r.[Data], GETDATE()),
			RegistrazioneNumero = ISNULL(r.Numero, 0),

			-- Dati formulario
			FormularioNumero = ISNULL(m.FormularioNumero, ''),
			FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
			RentriFormularioStato = m.RentriFormularioStato,
			IdAdr = ISNULL(f.IdAdr, '00'),
			NumeroOnu = ISNULL(f.NumeroOnu, ''),
			TrasportoAdr = ISNULL(f.TrasportoAdr, 0),
			AdrNote = ISNULL(f.AdrNote, ''),
			IdImballo = ISNULL(f.IdImballo, '00'),
			Quantita = ISNULL(m.Quantita, 0),
			IdUnitaMisura = ISNULL(m.IdUnitaMisura, 'KG'),
			ColliNumero = ISNULL(f.ColliNumero, ''),
			AllaRinfusa = ISNULL(f.AllaRinfusa, 0),

			IdAnalisiTipo = ISNULL(f.IdAnalisiTipo, '0'),
			AnalisiNumero = ISNULL(f.AnalisiNumero, ''),
			AnalisiData = f.AnalisiData,

			FormularioNote = ISNULL(f.Note, ''),
			UtenteNote = ISNULL(m.Note, ''),

			-- Autorizzazioni
			IdAutorizzazioneProduttoreDetentore = ISNULL(mp.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneDestinatario = ISNULL(md.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore1 = ISNULL(mt1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore2 = ISNULL(mt2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore3 = ISNULL(mt3.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario1 = ISNULL(mi1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario2 = ISNULL(mi2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario3 = ISNULL(mi3.IdAutorizzazione, REPLICATE('0', 16)),

			LuogoDiProduzione = ISNULL(f.LuogoDiProduzione, 0),
			Detentore = ISNULL(f.Detentore, 0),

			-- Trasporti
			DataInizioTrasporto = m.DataInizioTrasporto,
			IdTipoTrasporto1 = ISNULL(mt1.IdTipo, 'G'),
			IdTipoTrasporto2 = ISNULL(mt2.IdTipo, 'G'),
			IdTipoTrasporto3 = ISNULL(mt3.IdTipo, 'G'),

			-- Trasporto terreste (G)
			TargaMotrice = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.TargaMotrice, '') ELSE '' END,
			TargaRimorchio = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.TargaRimorchio, '') ELSE '' END,
			ConducenteNome = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.ConducenteNome, '') ELSE '' END,
			ConducenteCognome = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.ConducenteCognome, '') ELSE '' END,
			Percorso = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.Percorso, '') ELSE '' END,
			RimorchioPrecedente = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.RimorchioPrecedente, 0) ELSE 0 END,

			-- Trasporto marittimo (N)
			Nave = CASE WHEN mt1.IdTipo = 'N' THEN ISNULL(fn.Nave, '') ELSE '' END,
			Imdg = CASE WHEN mt1.IdTipo = 'N' THEN ISNULL(fn.Imdg, 0) ELSE 0 END,

			-- Trasporto ferroviario (T)
			Treno = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Treno, '') ELSE '' END,
			Tratta = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Tratta, '') ELSE '' END,
			Rid = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Rid, 0) ELSE 0 END,

			Lock = f.Lock
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			-- Produttori
			LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
			-- Destinatari
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			-- Trasportatori
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt3 ON m.Id = mt3.Id AND mt3.Pos = 2
			-- Intermediari
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi3 ON m.Id = mi3.Id AND mi3.Pos = 2
			-- Trasporti
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiTerresti fg ON f.Id = fg.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiMarittimi fn ON f.Id = fn.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiFerroviari ft ON f.Id = ft.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;

GO

--------------------------------------------------------------------------------
-- 4) dbo.uspRifiutiFormulari_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @Eer = dbo.ufnStringhe_get_SenzaSpazi(@Eer, 0, 1);
		SET @Formulario = dbo.ufnStringhe_get_SenzaSpazi(@Formulario, 0, 1);
		SET @Numeri = dbo.ufnStringhe_get_SenzaSpazi(@Numeri, 0, 1);
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage INT,
            @Offset      INT,
            @IdSessione  CHAR(16),
            @DallaData   DATE,
            @AllaData    DATE,
            @Soggetto    VARCHAR(50),
            @Eer         VARCHAR(50),
            @Formulario  VARCHAR(50),
            @Etichetta   VARCHAR(50)';

		-- FormularioNumero: spostato da tblRifiutiFormulari.Numero a tblRifiutiMovimenti.FormularioNumero
		SET @stmt = N'
        WITH tbl AS (
            SELECT
                Id                      = f.Id,
                StatoValore             = CASE WHEN f.Lock = 1 THEN 2 WHEN r.Id IS NULL THEN 1 ELSE 0 END,
                StatoDescrizione        = CASE WHEN f.Lock = 1 THEN ''Formulario non confermato'' WHEN r.Id IS NULL THEN ''Formulario non registrato'' ELSE ''OK'' END,
                FormularioNumero        = m.FormularioNumero,
                FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
                OperazioneNome          = op.Nome,
                EerNome                 = c.Nome,
                EerDescrizione          = c.Descrizione,
                StatoFisicoCodice       = s.Codice,
                StatoFisicoNome         = s.Nome,
                AttivitaRsCodice        = a.Codice,
                AttivitaRsNome          = a.Nome,
                RegistrazioneNumero     = r.Numero,
                RegistrazioneData       = r.[Data],
                ProduttoreDetentoreSede = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
                Trasportatore1Sede      = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
                DestinatarioSede        = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
                Intermediario1Sede      = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
                f.Etichette,
                IsRentriCollegato       = CAST(IIF(z.Id IS NOT NULL, 1, 0) AS BIT),
                r.RentriIdentificativo,
                r.RentriData,
                RentriFormularioStato   = m.RentriFormularioStato,
                RowsCount               = COUNT(*) OVER ()
            FROM
                dbo.tblRifiutiFormulari                      f
                INNER JOIN dbo.tblRifiutiMovimenti           m  ON f.IdMovimento               = m.Id
                INNER JOIN dbo.tblRifiutiRegistri            g  ON m.IdRegistro                = g.Id
                INNER JOIN dbo.tblSessioni                   e  ON g.Id                        = e.IdRegistro
                INNER JOIN dbo.tblRifiutiOperazioni          op ON m.IdOperazione              = op.Id
                LEFT  JOIN dbo.tblRifiutiRegistrazioni       r  ON f.IdMovimento               = r.IdMovimento AND r.Lock < 2
                LEFT  JOIN dbo.tblRifiutiEer                 c  ON m.IdEer                     = c.Id
                LEFT  JOIN dbo.tblRifiutiStatiFisici         s  ON m.IdStatoFisico             = s.Id
                LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento
                                                             a  ON m.IdAttivita                = a.Id
                LEFT  JOIN dbo.tblSedi                       sp ON m.IdSedeProduttoreDetentore = sp.Id
                LEFT  JOIN dbo.tblSedi                       st ON m.IdSedeTrasportatore1      = st.Id
                LEFT  JOIN dbo.tblSedi                       sd ON m.IdSedeDestinatario        = sd.Id
                LEFT  JOIN dbo.tblSedi                       si ON m.IdSedeIntermediario1      = si.Id
                LEFT  JOIN dbo.tblRentriRegistri             z  ON g.Id                        = z.Id
            WHERE
                e.Id    = @IdSessione
                AND f.Lock < 2
                AND (@DallaData IS NULL OR ISNULL(f.DataEmissione, GETDATE()) >= @DallaData)
                AND (@AllaData  IS NULL OR ISNULL(f.DataEmissione, GETDATE()) <= @AllaData)';

		IF @Soggetto IS NOT NULL
		BEGIN
			IF @Ruolo = 'P'
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'T'
				SET @stmt = @stmt + N' AND (st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'D'
				SET @stmt = @stmt + N' AND (sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'I'
				SET @stmt = @stmt + N' AND (si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
		END

		-- Filtro numeri: filtra per numero di registrazione associata.
		-- I formulari senza registrazione (r.Numero IS NULL) vengono esclusi intenzionalmente.
		-- Eccezione documentata al divieto di concatenazione: solo interi puri vengono inseriti.
		IF @Numeri IS NOT NULL
		BEGIN
			IF @Numeri LIKE '[1-9]%-%[0-9]' AND @Numeri LIKE '%[1-9]-[0-9]%'
			BEGIN
				DECLARE @numeroInizio VARCHAR(20) = SUBSTRING(@Numeri, 1, CHARINDEX('-', @Numeri) - 1);
				DECLARE @numeroFine VARCHAR(20) = SUBSTRING(@Numeri, CHARINDEX('-', @Numeri) + 1, 20);
				IF TRY_CAST(@numeroInizio AS INT) IS NOT NULL AND TRY_CAST(@numeroFine AS INT) IS NOT NULL
					SET @stmt = @stmt + N' AND r.Numero BETWEEN ' + @numeroInizio + N' AND ' + @numeroFine;
			END
			ELSE IF TRY_CAST(@Numeri AS INT) IS NOT NULL
				SET @stmt = @stmt + N' AND r.Numero = ' + @Numeri;
		END

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N' AND f.Id IN ('
					  + N'    SELECT t.Id FROM dbo.tblRifiutiFormulariEtichette t'
					  + N'    INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id'
					  + N'    WHERE et.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		-- FormularioNumero ora su tblRifiutiMovimenti (alias m)
		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.FormularioNumero, tbl.FormularioDataEmissione,
            tbl.OperazioneNome,
            tbl.EerNome, tbl.EerDescrizione,
            tbl.StatoFisicoCodice, tbl.StatoFisicoNome,
            tbl.AttivitaRsCodice, tbl.AttivitaRsNome,
            tbl.RegistrazioneNumero, tbl.RegistrazioneData,
            tbl.ProduttoreDetentoreSede, tbl.Trasportatore1Sede,
            tbl.DestinatarioSede, tbl.Intermediario1Sede,
            tbl.Etichette,
            tbl.IsRentriCollegato, tbl.RentriIdentificativo, tbl.RentriData, tbl.RentriFormularioStato,
            tbl.RowsCount
        FROM tbl
        ORDER BY tbl.FormularioDataEmissione DESC, tbl.FormularioNumero DESC
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY
        OPTION (RECOMPILE);';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Soggetto = @Soggetto,
			@Eer = @Eer,
			@Formulario = @Formulario,
			@Etichetta = @Etichetta;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;

GO

--------------------------------------------------------------------------------
-- 5) dbo.uspRifiutiFormulari_upd
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@VerificatoInPartenza BIT = 0,
	@IdAttivitaRs CHAR(2) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@FormularioDataEmissione DATE = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@IdTipoTrasporto1 CHAR(1) = NULL,
	@IdTipoTrasporto2 CHAR(1) = NULL,
	@IdTipoTrasporto3 CHAR(1) = NULL,
	@TargaMotrice VARCHAR(20) = NULL,
	@TargaRimorchio VARCHAR(20) = NULL,
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@RimorchioPrecedente BIT = 0,
	@Nave VARCHAR(50) = NULL,
	@Imdg BIT = 0,
	@Treno VARCHAR(50) = NULL,
	@Tratta VARCHAR(50) = NULL,
	@Rid BIT = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdAdr CHAR(2) = NULL,
	@NumeroOnu VARCHAR(20) = NULL,
	@TrasportoAdr BIT = 0,
	@AdrNote VARCHAR(200) = NULL,
	@IdImballo CHAR(2) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = NULL,
	@ColliNumero VARCHAR(50) = NULL,
	@AllaRinfusa BIT = 0,
	@IdAnalisiTipo CHAR(1) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData DATE = NULL,
	@LuogoDiProduzione BIT = 0,
	@Detentore BIT = 0,
	@Percorso VARCHAR(100) = NULL,
	@FormularioNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del
 formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizzazione parametri obbligatori
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Quantita non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione (via registro/sede) - stesso pattern di
		-- uspRifiutiFormulari_get. Senza questo controllo, chiunque avesse permesso
		-- RFR >= 2 poteva riscrivere il formulario (autorizzazioni, EER, quantità,
		-- trasportatori, ecc.) di un'altra azienda conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);
		DECLARE @minData DATE = '19000101';
		DECLARE @maxData DATE = '20501231';

		IF @FormularioDataEmissione >= @maxData SET @FormularioDataEmissione = NULL;
		IF @DataInizioTrasporto >= @maxData SET @DataInizioTrasporto = NULL;

		DECLARE @idMovimento CHAR(16);
		DECLARE @idRegistro CHAR(16);
		DECLARE @idRegistrazione CHAR(16);
		DECLARE @lock TINYINT;
		DECLARE @isRegistrazioneAssociata BIT;
		DECLARE @registrazioneData DATE;
		DECLARE @registrazioneNumero INT;
		DECLARE @idOperazione CHAR(1);
		DECLARE @totaleQuantitaAssegnata DECIMAL(18,2);
		DECLARE @idRelazione CHAR(16);
		DECLARE @quantitaRelazione DECIMAL(18,2);
		DECLARE @quantitaResidua DECIMAL(18,2);
		DECLARE @nessunaRegistrazioneAssociata BIT = 1;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @formularioRentriStato VARCHAR(40);

		-- Recupero dati formulario dalle tabelle base
		SELECT
			@idMovimento = f.IdMovimento,
			@idRegistro = m.IdRegistro,
			@idRegistrazione = r.Id,
			@lock = f.Lock,
			@idOperazione = m.IdOperazione,
			@isRegistrazioneAssociata = IIF(r.Id IS NOT NULL AND ISNULL(r.Lock, 8) < 2, 1, 0),
			@registrazioneData = r.[Data],
			@registrazioneNumero = r.Numero,
			@rentriIdentificativo = r.RentriIdentificativo,
			@rentriData = r.RentriData,
			@formularioRentriStato = m.RentriFormularioStato,
			@nessunaRegistrazioneAssociata = CASE
				WHEN EXISTS(
					SELECT 1
					FROM dbo.tblRifiutiRegistrazioniRelazioni rel
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON rel.Id = rr.Id
					WHERE
						rel.IdParent = r.Id
						AND rr.Lock < 2
				) THEN 0
				ELSE 1
			END
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		WHERE f.Id = @Id;

		-- Verifica che il formulario esista
		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		-- Se la registrazione associata è già stata trasmessa a RENTRI, il formulario non può più
		-- essere modificato (un formulario senza registrazione associata resta invece modificabile)
		IF @isRegistrazioneAssociata = 1 AND (@rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione associata è già stata inviata al RENTRI: il formulario non può più essere modificato';
			GOTO BRANCH_END;
		END

		-- Normalizzazione parametri CHAR opzionali
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdTipoTrasporto1 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto1)), '');
		SET @IdTipoTrasporto2 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto2)), '');
		SET @IdTipoTrasporto3 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto3)), '');
		SET @IdAdr = NULLIF(LTRIM(RTRIM(@IdAdr)), '');
		SET @IdImballo = NULLIF(LTRIM(RTRIM(@IdImballo)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');

		-- Autorizzazioni: azzera se è "nessuna" (SediciZeri)
		IF @IdAutorizzazioneProduttoreDetentore = @idSediciZeri SET @IdAutorizzazioneProduttoreDetentore = NULL;
		IF @IdAutorizzazioneDestinatario = @idSediciZeri SET @IdAutorizzazioneDestinatario = NULL;

		-- Autorizzazioni trasportatore: gestisce i valori delle 3 possibili autorizzazioni
		IF @IdAutorizzazioneTrasportatore1 = @idSediciZeri
			SET @IdAutorizzazioneTrasportatore1 = NULL;

		IF @IdAutorizzazioneTrasportatore2 = @idSediciZeri OR @IdAutorizzazioneTrasportatore1 IS NULL
			SET @IdAutorizzazioneTrasportatore2 = NULL;

		IF @IdAutorizzazioneTrasportatore3 = @idSediciZeri OR @IdAutorizzazioneTrasportatore2 IS NULL
			SET @IdAutorizzazioneTrasportatore3 = NULL;

		-- Autorizzazioni intermediario: gestisce i valori delle 3 possibili autorizzazioni
		IF @IdAutorizzazioneIntermediario1 = @idSediciZeri
			SET @IdAutorizzazioneIntermediario1 = NULL;

		IF @IdAutorizzazioneIntermediario2 = @idSediciZeri OR @IdAutorizzazioneIntermediario1 IS NULL
			SET @IdAutorizzazioneIntermediario2 = NULL;

		IF @IdAutorizzazioneIntermediario3 = @idSediciZeri OR @IdAutorizzazioneIntermediario2 IS NULL
			SET @IdAutorizzazioneIntermediario3 = NULL;

		IF @AllaRinfusa = 1 SET @IdImballo = NULL;
		IF @IdImballo = '00' SET @IdImballo = NULL;

		-- Normalizzazione parametri VARCHAR opzionali
		SET @ClassiPericolo = dbo.ufnStringhe_get_SenzaSpazi(@ClassiPericolo, 0, 1);
		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @ColliNumero = dbo.ufnStringhe_get_SenzaSpazi(@ColliNumero, 0, 1);
		SET @FormularioNote = dbo.ufnStringhe_get_SenzaSpazi(@FormularioNote, 0, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 0, 1);
		SET @IdEtichette = dbo.ufnStringhe_get_SenzaSpazi(@IdEtichette, 0, 1);

		-- Trasporto terrestre (G): tblRifiutiFormulariTrasportiTerresti
		IF @IdTipoTrasporto1 <> 'G'
		BEGIN
			SET @TargaMotrice = NULL;
			SET @TargaRimorchio = NULL;
			SET @ConducenteNome = NULL;
			SET @ConducenteCognome = NULL;
			SET @Percorso = NULL;
			SET @RimorchioPrecedente = 0;
		END
		ELSE
		BEGIN
			SET @TargaMotrice = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@TargaMotrice, 0, 1));
			SET @TargaRimorchio = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@TargaRimorchio, 0, 1));
			SET @ConducenteNome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteNome, 0, 1);
			SET @ConducenteCognome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteCognome, 0, 1);
			SET @Percorso = dbo.ufnStringhe_get_SenzaSpazi(@Percorso, 0, 1);
		END

		-- Trasporto marittimo (N): tblRifiutiFormulariTrasportiMarittimi
		IF @IdTipoTrasporto1 <> 'N'
		BEGIN
			SET @Nave = NULL;
			SET @Imdg = 0;
		END
		ELSE
			SET @Nave = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Nave, 0, 1));

		-- Trasporto ferroviario (T): tblRifiutiFormulariTrasportiFerroviari
		IF @IdTipoTrasporto1 <> 'T'
		BEGIN
			SET @Treno = NULL;
			SET @Tratta = NULL;
			SET @Rid = 0;
		END
		ELSE
		BEGIN
			SET @Treno = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Treno, 0, 1));
			SET @Tratta = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Tratta, 0, 1));
		END

		-- ADR
		IF @TrasportoAdr = 0
		BEGIN
			SET @IdAdr = NULL;
			SET @NumeroOnu = NULL;
			SET @AdrNote = NULL;
		END
		ELSE
		BEGIN
			IF @IdAdr = '00' SET @IdAdr = NULL;
			SET @NumeroOnu = dbo.ufnStringhe_get_SenzaSpazi(@NumeroOnu, 0, 1);
			SET @AdrNote = dbo.ufnStringhe_get_SenzaSpazi(@AdrNote, 0, 1);
		END

		-- Analisi
		IF @IdAnalisiTipo = '0'
		BEGIN
			SET @IdAnalisiTipo = NULL;
			SET @AnalisiNumero = NULL;
			SET @AnalisiData = NULL;
		END
		ELSE
		BEGIN
			SET @AnalisiNumero = dbo.ufnStringhe_get_SenzaSpazi(@AnalisiNumero, 0, 1);
		END

		-- Calcolo totale quantità assegnata (separato dal SELECT per leggere @nessunaRegistrazioneAssociata già valorizzata)
		IF @nessunaRegistrazioneAssociata = 0
			SELECT @totaleQuantitaAssegnata = ISNULL(SUM(lq.Quantita), 0)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni lq
				INNER JOIN dbo.tblRifiutiRegistrazioni rq ON lq.Id = rq.Id
			WHERE
				lq.IdParent = @idRegistrazione
				AND lq.Quantita > 0
				AND rq.Lock < 2;
		ELSE
			SET @totaleQuantitaAssegnata = 0;

		-- Controllo numero formulario duplicato
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			WHERE
				f.IdMovimento <> @idMovimento
				AND m.IdRegistro = @idRegistro
				AND f.Lock < 2
				AND m.FormularioNumero = @FormularioNumero
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro formulario con lo stesso numero è già presente';
			GOTO BRANCH_END;
		END

		-- Controllo EER/stato fisico/unità di misura nelle relazioni della registrazione associata
		IF @isRegistrazioneAssociata = 1 AND @nessunaRegistrazioneAssociata = 0 AND @idOperazione <> 'K'
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					(
					l.Id = @idRegistrazione
					OR l.IdParent = @idRegistrazione
					)
					AND mp.IdOperazione <> 'M'
					AND
						(
						m.IdEer <> @IdEer
						OR m.IdStatoFisico <> @IdStatoFisico
						OR m.IdUnitaMisura <> @IdUnitaMisura
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione di questo formulario è associata ad altre con differente EER e/o stato fisico e/o unità di misura';
				GOTO BRANCH_END;
			END
		END


		-- Controllo quantità già scaricata (l.Id = @idRegistrazione: verifica che @idRegistrazione, come figlio, non scenda sotto quanto già scaricato dal padre)
		IF @isRegistrazioneAssociata = 1
		BEGIN
			IF @Quantita < ISNULL((
				SELECT SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				WHERE
					l.Id = @idRegistrazione
					AND l.Quantita > 0
					AND rp.Lock < 2
			), 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità non può essere inferiore a quella già associata ad altre registrazioni';
				GOTO BRANCH_END;
			END
		END

		 -- Verifica quantità superiore disponibile nella registrazione associata
		IF @isRegistrazioneAssociata = 1 AND @nessunaRegistrazioneAssociata = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiOperazioniRelazioni
			WHERE Id = @idOperazione)
			BEGIN
				IF dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore(
					@idRegistrazione, @Quantita, @registrazioneData, @registrazioneNumero,
					@IdEer, @IdStatoFisico, @IdUnitaMisura, 0) > 0
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'La quantità registrata è superiore a quella disponibile nelle registrazioni associate';
					GOTO BRANCH_END;
				END
			END
		END

		-- Verifica se necessario aggiornare il log
		DECLARE @aggiornaLog BIT = 0;
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000')
						OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0')
						OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00')
						OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '')
						OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0')
						OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0)
						OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData)
						)
			)
				SET @aggiornaLog = 1;
			ELSE IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp1 ON m.Id = mp1.Id AND mp1.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(mp1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneProduttoreDetentore, @idSediciZeri)
						OR ISNULL(md.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneDestinatario, @idSediciZeri)
						OR ISNULL(mt1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneTrasportatore1, @idSediciZeri)
						OR ISNULL(mi1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneIntermediario1, @idSediciZeri)
						)
			)
				SET @aggiornaLog = 1;
		END

		-- Calcola la soglia per la pulizia del log (fuori dalla transazione, intenzionale)
		-- Se ci sono 10 o meno record @dataLogMin resta NULL: il DELETE successivo non elimina nulla (comportamento corretto)
		DECLARE @dataLogMin DATETIME2(0);
		DECLARE @idUtente CHAR(16);

		IF @aggiornaLog = 1
		BEGIN
			SELECT TOP 1
				@dataLogMin = [Data]
			FROM (
				SELECT
					[Data],
					Pos = ROW_NUMBER() OVER (ORDER BY [Data] DESC)
				FROM dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento) t
			WHERE t.Pos > 9
			ORDER BY Pos;

			-- Lettura IdUtente fuori dalla transazione (intenzionale)
			SELECT @idUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		BEGIN TRANSACTION;

			-- Produttori
			DELETE dbo.tblRifiutiMovimentiProduttori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneProduttoreDetentore IS NOT NULL
			BEGIN
				IF EXISTS (SELECT 1
				FROM dbo.tblSedi
				WHERE Id = @IdAutorizzazioneProduttoreDetentore)
				BEGIN
					DECLARE @idSede CHAR(16) = @IdAutorizzazioneProduttoreDetentore;
					SET @IdAutorizzazioneProduttoreDetentore = NULL;

					SELECT @IdAutorizzazioneProduttoreDetentore = Id
					FROM dbo.tblRifiutiAutorizzazioni
					WHERE
						IdSede = @idSede
						AND Nessuna = 1
						AND Lock = 0;

					IF @IdAutorizzazioneProduttoreDetentore IS NULL
					BEGIN
						EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @IdAutorizzazioneProduttoreDetentore OUTPUT;

						INSERT dbo.tblRifiutiAutorizzazioni
							(Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
						VALUES
							(@IdAutorizzazioneProduttoreDetentore, @idSede, 'P', @minData, @maxData, 1, 0, 0);
					END
				END

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneProduttoreDetentore, @Quantita, 0);
			END

			-- Destinatari
			DELETE dbo.tblRifiutiMovimentiDestinatari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneDestinatario IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneDestinatario, 0);
			END

			-- Trasportatori
			DELETE dbo.tblRifiutiMovimentiTrasportatori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneTrasportatore1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneTrasportatore1, @IdTipoTrasporto1, 0);

				IF @IdAutorizzazioneTrasportatore2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneTrasportatore2, @IdTipoTrasporto2, 1);

					IF @IdAutorizzazioneTrasportatore3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneTrasportatore3, @IdTipoTrasporto3, 2);
					END
				END
			END

			-- Trasporto (dettaglio per tipo, tabelle satellite del formulario)
			DELETE dbo.tblRifiutiFormulariTrasportiTerresti
			WHERE Id = @Id;
			DELETE dbo.tblRifiutiFormulariTrasportiMarittimi
			WHERE Id = @Id;
			DELETE dbo.tblRifiutiFormulariTrasportiFerroviari
			WHERE Id = @Id;

			IF @IdTipoTrasporto1 = 'G'
				INSERT dbo.tblRifiutiFormulariTrasportiTerresti
					(Id, TargaMotrice, TargaRimorchio, ConducenteNome, ConducenteCognome, Percorso, RimorchioPrecedente)
				VALUES
					(@Id, @TargaMotrice, @TargaRimorchio, @ConducenteNome, @ConducenteCognome, @Percorso, @RimorchioPrecedente);
			ELSE IF @IdTipoTrasporto1 = 'N'
				INSERT dbo.tblRifiutiFormulariTrasportiMarittimi (Id, Nave, Imdg)
				VALUES (@Id, @Nave, @Imdg);
			ELSE IF @IdTipoTrasporto1 = 'T'
				INSERT dbo.tblRifiutiFormulariTrasportiFerroviari (Id, Treno, Tratta, Rid)
				VALUES (@Id, @Treno, @Tratta, @Rid);

			-- Intermediari
			DELETE dbo.tblRifiutiMovimentiIntermediari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneIntermediario1, 0);

				IF @IdAutorizzazioneIntermediario2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneIntermediario2, 1);

					IF @IdAutorizzazioneIntermediario3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneIntermediario3, 2);
					END
				END
			END

			-- Classi di pericolo
			DELETE dbo.tblRifiutiMovimentiClassiPericolo
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT @idMovimento, c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Etichette formulario
			DELETE dbo.tblRifiutiFormulariEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
			SELECT TOP 3 @Id, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			-- Aggiorna le quantità delle registrazioni in relazione carico/scarico
			IF @Quantita = 0 OR @nessunaRegistrazioneAssociata = 1
			BEGIN
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @idRegistrazione;
			END

			IF @nessunaRegistrazioneAssociata = 0 AND @Quantita > 0 AND @Quantita <> @totaleQuantitaAssegnata
			BEGIN
				UPDATE dbo.tblRifiutiRegistrazioniRelazioni
				SET Quantita = 0
				WHERE IdParent = @idRegistrazione;

				SET @quantitaRelazione = @Quantita;

				-- Distribuzione quantità sulle relazioni ordinate per Pos
				DECLARE c CURSOR FAST_FORWARD FOR
					SELECT
						l.Id,
						QuantitaResidua = m2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.tblRifiutiMovimenti m2 ON r.IdMovimento = m2.Id
						LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
								INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
								INNER JOIN dbo.tblRifiutiMovimenti mpq ON pq.IdMovimento = mpq.Id
							WHERE
								pq.Lock < 2
								AND mpq.Quantita > 0
							GROUP BY lq.Id
						) a ON l.Id = a.Id
					WHERE l.IdParent = @idRegistrazione
					ORDER BY l.Pos;

				OPEN c;
				FETCH c INTO @idRelazione, @quantitaResidua;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @quantitaRelazione > 0
					BEGIN
						IF @quantitaRelazione >= @quantitaResidua
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaResidua
							WHERE
								IdParent = @idRegistrazione
								AND Id = @idRelazione;
							SET @quantitaRelazione = @quantitaRelazione - @quantitaResidua;
						END
						ELSE
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaRelazione
							WHERE
								IdParent = @idRegistrazione
								AND Id = @idRelazione;
							SET @quantitaRelazione = 0;
						END
					END
					FETCH c INTO @idRelazione, @quantitaResidua;
				END

				CLOSE c;
				DEALLOCATE c;
			END

			DELETE dbo.tblRifiutiRegistrazioniRelazioni
			WHERE
				IdParent = @idRegistrazione
				AND Quantita = 0;

			-- Aggiornamento log storico movimento (snapshot stato corrente prima degli UPDATE)
			-- @dataLogMin = NULL se <= 10 record: il DELETE non elimina nulla (comportamento corretto)
			IF @aggiornaLog = 1
			BEGIN
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND [Data] <= @dataLogMin;

				INSERT dbo.tblRifiutiMovimentiLog
					(Id, [Data], IdUtente,
					 IdEer, IdStatoFisico, IdMateriale, IdAttivita, IdUnitaMisura,
					 Quantita, QuantitaVerificata, IdAutorizzazioneProduttoreDetentore, IdAutorizzazioneDestinatario,
					 IdAutorizzazioneTrasportatore1, IdAutorizzazioneIntermediario1,
					 RegistrazioneNumero, RegistrazioneData, FormularioNumero, DataInizioTrasporto, DataFineTrasporto)
				SELECT
					m.Id, GETDATE(), @idUtente,
					m.IdEer, m.IdStatoFisico, r.IdMateriale, m.IdAttivita, m.IdUnitaMisura,
					m.Quantita, r.QuantitaVerificata, mp.IdAutorizzazione, md.IdAutorizzazione,
					mt.IdAutorizzazione, mi.IdAutorizzazione,
					r.Numero, r.[Data], m.FormularioNumero, m.DataInizioTrasporto, r.DataFineTrasporto
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				WHERE m.Id = @idMovimento;
			END

			-- Aggiornamento formulario
			UPDATE dbo.tblRifiutiFormulari
			SET
				DataEmissione = @FormularioDataEmissione,
				Note = @FormularioNote,
				IdAdr = @IdAdr,
				NumeroOnu = @NumeroOnu,
				TrasportoAdr = @TrasportoAdr,
				AdrNote = @AdrNote,
				IdImballo = @IdImballo,
				ColliNumero = @ColliNumero,
				AllaRinfusa = @AllaRinfusa,
				VerificatoInPartenza = @VerificatoInPartenza,
				Etichette = dbo.ufnRifiutiFormulari_get_Etichette(Id),
				IdAnalisiTipo = @IdAnalisiTipo,
				AnalisiNumero = @AnalisiNumero,
				AnalisiData = @AnalisiData,
				LuogoDiProduzione = @LuogoDiProduzione,
				Detentore = @Detentore,
				Lock = 0
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Formulario non trovato o già modificato da un altro utente';
				GOTO BRANCH_END;
			END

			-- Aggiornamento movimento
			UPDATE m
			SET
				IdEer = @IdEer,
				IdProvenienza = @IdProvenienza,
				IdStatoFisico = @IdStatoFisico,
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				Quantita = @Quantita,
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede,
				-- Una volta creato il formulario digitale su RENTRI (RentriStato valorizzato), il numero
				-- non puo' piu' essere modificato dall'utente - mantiene il valore gia' a DB
				-- indipendentemente da @FormularioNumero (non blocca l'intero update, solo questo campo:
				-- gli altri dati restano modificabili e sincronizzabili su RENTRI via "Modifica").
				FormularioNumero = CASE WHEN @formularioRentriStato IS NOT NULL THEN m.FormularioNumero ELSE @FormularioNumero END,
				DataInizioTrasporto = @DataInizioTrasporto,
				Note = @UtenteNote
			FROM
				dbo.tblRifiutiMovimenti m
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON mp.IdAutorizzazione = ap.Id
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON md.IdAutorizzazione = ad.Id
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON mt.IdAutorizzazione = ar.Id
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON mi.IdAutorizzazione = ai.Id
			WHERE m.Id = @idMovimento;

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione (intenzionale)
		IF @lock > 0 OR @aggiornaLog = 1
		BEGIN
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
		END

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT ReturnValue = @returnValue;
END;

GO

--------------------------------------------------------------------------------
-- 6) dbo.uspRifiutiRegistrazioni_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @Eer = dbo.ufnStringhe_get_SenzaSpazi(@Eer, 0, 1);
		SET @Formulario = dbo.ufnStringhe_get_SenzaSpazi(@Formulario, 0, 1);
		SET @Numeri = dbo.ufnStringhe_get_SenzaSpazi(@Numeri, 0, 1);
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage INT,
            @Offset      INT,
            @IdSessione  CHAR(16),
            @DallaData   DATE,
            @AllaData    DATE,
            @Soggetto    VARCHAR(50),
            @Eer         VARCHAR(50),
            @Formulario  VARCHAR(50),
            @Etichetta   VARCHAR(50)';

		-- FormularioNumero: spostato da tblRifiutiFormulari.Numero a tblRifiutiMovimenti.FormularioNumero
		SET @stmt = N'
        WITH tbl AS (
            SELECT
                Id                       = r.Id,
                StatoValore              = CASE WHEN r.Lock = 1 THEN 1 ELSE 0 END,
                StatoDescrizione         = CASE WHEN r.Lock = 1 THEN ''Registrazione da confermare'' ELSE ''OK'' END,
                RegistrazioneNumero      = r.Numero,
                RegistrazioneData        = r.Data,
                OperazioneNome           = o.Nome,
                Quantita                 = m.Quantita           * IIF(r.Operazione = ''S'', -1, 1),
                IsQuantitaVerificata     = CAST(IIF(r.QuantitaVerificata IS NULL, 0, 1) AS BIT),
                QuantitaVerificata       = r.QuantitaVerificata * IIF(r.Operazione = ''S'', -1, 1),
                EerNome                  = ISNULL(c.Nome, t.Codice),
                EerDescrizione           = ISNULL(c.Descrizione, t.Nome),
                StatoFisicoCodice        = s.Codice,
                StatoFisicoNome          = s.Nome,
                AttivitaRsCodice         = a.Codice,
                AttivitaRsNome           = a.Nome,
                FormularioNumero         = m.FormularioNumero,
                ProduttoreDetentoreSede  = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
                Trasportatore1Sede       = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
                DestinatarioSede         = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
                Intermediario1Sede       = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
                r.Etichette,
                IsRentriCollegato        = CAST(IIF(z.Id IS NOT NULL, 1, 0) AS BIT),
                r.RentriIdentificativo,
                r.RentriData,
                IsRettifica              = CAST(IIF(rett.Id IS NOT NULL, 1, 0) AS BIT),
                IsAnnullamento           = CAST(ISNULL(rett.Annullata, 0) AS BIT),
                RettificaRegistrazioneNumero = ro.Numero,
                RettificaRegistrazioneData   = ro.Data,
                RentriFormularioStato    = m.RentriFormularioStato
            FROM
                dbo.tblRifiutiRegistrazioni                  r
                INNER JOIN dbo.tblRifiutiMovimenti           m  ON r.IdMovimento               = m.Id
                INNER JOIN dbo.tblRifiutiRegistri            g  ON m.IdRegistro                = g.Id
                INNER JOIN dbo.tblSessioni                   e  ON g.Id                        = e.IdRegistro
                LEFT  JOIN dbo.tblRifiutiOperazioni          o  ON m.IdOperazione              = o.Id
                LEFT  JOIN dbo.tblRifiutiEer                 c  ON m.IdEer                     = c.Id
                LEFT  JOIN dbo.tblRifiutiStatiFisici         s  ON m.IdStatoFisico             = s.Id
				LEFT  JOIN dbo.tblRifiutiMateriali		     t  ON r.IdMateriale			   = t.Id
                LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento
                                                             a  ON m.IdAttivita                = a.Id
                LEFT  JOIN dbo.tblSedi                       sp ON m.IdSedeProduttoreDetentore = sp.Id
                LEFT  JOIN dbo.tblSedi                       st ON m.IdSedeTrasportatore1      = st.Id
                LEFT  JOIN dbo.tblSedi                       sd ON m.IdSedeDestinatario        = sd.Id
                LEFT  JOIN dbo.tblSedi                       si ON m.IdSedeIntermediario1      = si.Id
                LEFT  JOIN dbo.tblRentriRegistri             z  ON g.Id                        = z.Id
                LEFT  JOIN dbo.tblRentriRegistrazioniRettifiche
                                                             rett ON rett.IdRettifica          = r.Id
                LEFT  JOIN dbo.tblRifiutiRegistrazioni       ro ON rett.Id                     = ro.Id
            WHERE
                e.Id      = @IdSessione
                AND r.Lock < 2
                AND (@DallaData IS NULL OR r.Data >= @DallaData)
                AND (@AllaData  IS NULL OR r.Data <= @AllaData)';

		IF @Soggetto IS NOT NULL
		BEGIN
			IF @Ruolo = 'P'
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'T'
				SET @stmt = @stmt + N' AND (st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'D'
				SET @stmt = @stmt + N' AND (sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'I'
				SET @stmt = @stmt + N' AND (si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
		END

		-- Filtro numeri: interi validati con TRY_CAST prima della concatenazione.
		-- Eccezione documentata al divieto di concatenazione: solo interi puri vengono inseriti.
		IF @Numeri IS NOT NULL
		BEGIN
			IF @Numeri LIKE '[1-9]%-%[0-9]' AND @Numeri LIKE '%[1-9]-[0-9]%'
			BEGIN
				DECLARE @numeroInizio VARCHAR(20) = SUBSTRING(@Numeri, 1, CHARINDEX('-', @Numeri) - 1);
				DECLARE @numeroFine VARCHAR(20) = SUBSTRING(@Numeri, CHARINDEX('-', @Numeri) + 1, 20);
				IF TRY_CAST(@numeroInizio AS INT) IS NOT NULL AND TRY_CAST(@numeroFine AS INT) IS NOT NULL
					SET @stmt = @stmt + N' AND r.Numero BETWEEN ' + @numeroInizio + N' AND ' + @numeroFine;
			END
			ELSE IF TRY_CAST(@Numeri AS INT) IS NOT NULL
				SET @stmt = @stmt + N' AND r.Numero = ' + @Numeri;
		END

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N' AND r.Id IN ('
					  + N'    SELECT t.Id FROM dbo.tblRifiutiRegistrazioniEtichette t'
					  + N'    INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id'
					  + N'    WHERE et.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.RegistrazioneNumero, tbl.RegistrazioneData,
            tbl.OperazioneNome, tbl.Quantita, tbl.IsQuantitaVerificata, tbl.QuantitaVerificata,
            tbl.EerNome, tbl.EerDescrizione,
            tbl.StatoFisicoCodice, tbl.StatoFisicoNome,
            tbl.AttivitaRsCodice, tbl.AttivitaRsNome,
            tbl.FormularioNumero, tbl.ProduttoreDetentoreSede, tbl.Trasportatore1Sede, tbl.DestinatarioSede, tbl.Intermediario1Sede,
            tbl.Etichette,
            tbl.IsRentriCollegato, tbl.RentriIdentificativo, tbl.RentriData,
            tbl.IsRettifica, tbl.IsAnnullamento, tbl.RettificaRegistrazioneNumero, tbl.RettificaRegistrazioneData,
            tbl.RentriFormularioStato,
            RowsCount = COUNT(*) OVER ()
        FROM tbl
        ORDER BY tbl.RegistrazioneData DESC, tbl.RegistrazioneNumero DESC
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY
        OPTION (RECOMPILE);';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Soggetto = @Soggetto,
			@Eer = @Eer,
			@Formulario = @Formulario,
			@Etichetta = @Etichetta;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;

GO

--------------------------------------------------------------------------------
-- 7) dbo.viewRentriFormulariDigitali
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Vista consumata dall'hub condiviso 1_0_rentri (nuovo branch @App='40' di uspFormulario_get_ByIdFormulario),
-- referenziata letteralmente come [4_0_ecomatico]..viewRentriFormulariDigitali: nome e insieme di colonne NON
-- sono rinominabili/estendibili senza coordinarsi con l'hub. Colonne allineate a RentriApi.Domain.Models.FormularioDigitale
-- (Dapper QuerySingle, match per nome colonna). A differenza del branch gemello @App='31' (3_1_ecomatico..viewRentriFormulariDigitali,
-- schema legacy solo trasporto su gomma) questo schema supporta anche Ferroviario/Marittimo (tblRifiutiMovimentiTrasportatori.IdTipo
-- G/T/N), quindi valorizza anche TrasportoTipo/Trasporto2Tipo/IdentificativoTreno/Tratta/Nave/OpzioneTrenoNave, assenti nel branch 31.
-- Note sui campi lasciati a NULL/default (nessun concetto equivalente in questo schema, non usati dal blocco
-- dati_partenza costruito da ApiHelpers.BuildFormularioContent per le azioni Crea/Modifica):
-- - Produttore/DestinatarioSede: nessun uso lato hub, sempre NULL.
-- - Luogo di produzione diverso dall'unita' locale (tblRifiutiFormulari.LuogoDiProduzione=1): l'indirizzo
--   selezionato nel FIR (Sede dell'autorizzazione produttore) e' il luogo di produzione effettivo (Posizione*),
--   mentre Produttore* (Nome/CodiceFiscale/indirizzo, l'unita' locale/sede legale) va risolto separatamente:
--   nella famiglia della Sede (se stessa/sorelle dirette via IdParent, ancora = ISNULL(IdParent, Id) - stesso
--   raggruppamento dell'invariante di uspSedi_upd), la Sede con UnitaLocale=1, altrimenti la Sede Padre
--   (regola identica sia per sedi interne che esterne, nessun filtro InternaEsterna - confermato dall'utente
--   2026-09-05). NON usare IdAziendaInterna come chiave di famiglia: per le Sedi Esterne quella colonna vale
--   l'azienda interna proprietaria (tblSediEsterne.IdSedeInterna, vedi uspSedi_upd), non la radice della
--   propria parentela - userebbe come "sorelle" tutte le sedi esterne di quell'azienda interna, non quelle
--   della stessa famiglia (bug reale riscontrato in produzione 2026-09-06, corretto qui usando IdParent).
--   Il gate lato hub ApiHelpers.BuildFormularioContent (codice condiviso con le app legacy, non modificabile) allega il blocco
--   luogo_produzione solo se IDCausale='CSX' - per questo IDCausale sopra e' forzato a 'CSX' quando
--   LuogoDiProduzione=1 (nessun altro uso di IDCausale in questo schema/lato hub), invece di modificare il gate.
-- - Esito/DataEsito/QuantitaRegistrata/QuantitaDestino/QuantitaRespinta/EsitoCausaleRespingimento/RespingimentoMotivo/
--   DataOraFineTrasporto: dati di accettazione, non ancora implementati lato app (fase successiva, endpoint /accettazione) -
--   default sicuri per non rompere il mapping Dapper (tipi non nullable lato C#).
-- Autorizzazione Produttore/Destinatario: tblRifiutiAutorizzazioni.IdNumeroTipo distingue 'A' (Albo Gestori Ambientali,
-- popola solo *AutorizzazioneAlbo) da 'C'/altro (Comunicazione/Autorizzazione generica, popola *Autorizzazione +
-- *AutorizzazioneTipo da tblRifiutiAutorizzazioniTipi.Codice, gia' allineato ai valori enum RENTRI tipo_autorizzazione
-- - es. RecSmalArt208/AIA/RecProcSemplificata - verificato confrontando i due lookup). Trasportatori/Intermediari
-- usano sempre e solo il Numero come iscrizione Albo (RENTRI non prevede un tipo alternativo per questi ruoli).
-- DataOraInizioTrasporto: stringa ISO8601 con offset +01:00/+02:00 calcolato correttamente per il DST tramite
-- AT TIME ZONE (non hardcoded come nel branch legacy 31, che ha sempre "+02:00" indipendentemente dal periodo dell'anno).
CREATE OR ALTER VIEW [dbo].[viewRentriFormulariDigitali]
AS
SELECT
	IdFormulario = f.Id,
	-- IDCausale='CSX' forzato quando LuogoDiProduzione=1: e' l'UNICO segnale che ApiHelpers.BuildFormularioContent
	-- (1_0_RentriApi, codice condiviso con le app legacy, non modificabile) usa per decidere se allegare il
	-- blocco luogo_produzione (richiede anche ProduttorePosizione IS NOT NULL e ProduttoreSede <> ProduttorePosizione,
	-- entrambi gia' soddisfatti quando LuogoDiProduzione=1 in questa vista - ProduttoreSede e' sempre NULL).
	-- 'CSX' non ha altro significato/uso in questo schema, e IDCausale non e' letto altrove dall'hub.
	-- Soluzione confermata dall'utente (2026-09-05) per non dover toccare l'endpoint condiviso.
	IDCausale = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN 'CSX' ELSE o.Codice END,
	Numero = m.FormularioNumero,
	DataEmissione = ISNULL(f.DataEmissione, GETDATE()),
	ProduttoreNome = UPPER(CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN spul.NomeCompleto ELSE sp.NomeCompleto END),
	ProduttoreCodiceFiscale = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ISNULL(spul.CodiceFiscale, spul.PartitaIva) ELSE ISNULL(sp.CodiceFiscale, sp.PartitaIva) END,
	ProduttoreSede = CAST(NULL AS VARCHAR(200)),
	-- Luogo di produzione diverso dall'unita' locale (f.LuogoDiProduzione=1): l'indirizzo selezionato nel FIR
	-- (sp/ip, la Sede dell'autorizzazione produttore) e' in realta' il luogo di produzione (va in Posizione*),
	-- mentre l'unita' locale (Produttore*) va risolta separatamente nella famiglia di sp (se stessa/sorelle
	-- dirette via IdParent, stesso raggruppamento dell'invariante di uspSedi_upd - NON IdAziendaInterna, che
	-- per le Sedi Esterne e' l'azienda interna proprietaria e non la radice della propria parentela):
	-- la Sede con UnitaLocale=1, o in sua assenza la Sede Padre di sp (spul, risolta in OUTER APPLY sotto).
	-- Confermato dall'utente (2026-09-05): anche Nome/CodiceFiscale vanno presi dalla Sede risolta (spul), non da sp.
	ProduttorePosizione = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN UPPER(ip.Indirizzo + ISNULL(', ' + NULLIF(ip.NumeroCivico, ''), '')) ELSE NULL END,
	ProduttoreAutorizzazioneAlbo = CASE WHEN ISNULL(pa.Nessuna, 0) = 1 THEN NULL WHEN pa.IdNumeroTipo = 'A' THEN pa.Numero ELSE NULL END,
	ProduttoreAutorizzazione = CASE WHEN ISNULL(pa.Nessuna, 0) = 1 THEN NULL WHEN pa.IdNumeroTipo = 'A' THEN NULL ELSE pa.Numero END,
	ProduttoreAutorizzazioneTipo = CASE WHEN ISNULL(pa.Nessuna, 0) = 1 OR pa.IdNumeroTipo = 'A' THEN NULL ELSE pat.Codice END,
	ProduttoreNazione = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN nzpul.Sigla ELSE nzp.Sigla END,
	ProduttoreIdComune = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.IdComune ELSE ip.IdComune END,
	ProduttoreIndirizzo = UPPER(CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.Indirizzo + ISNULL(', ' + NULLIF(ipul.NumeroCivico, ''), '') ELSE ip.Indirizzo + ISNULL(', ' + NULLIF(ip.NumeroCivico, ''), '') END),
	ProduttoreCAP = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.CAP ELSE ip.CAP END,
	ProduttoreLocalita = UPPER(CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.Localita ELSE ip.Localita END),
	PosizioneNazione = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN nzp.Sigla ELSE NULL END,
	PosizioneIdComune = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ip.IdComune ELSE NULL END,
	PosizioneIndirizzo = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN UPPER(ip.Indirizzo + ISNULL(', ' + NULLIF(ip.NumeroCivico, ''), '')) ELSE NULL END,
	PosizioneCAP = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ip.CAP ELSE NULL END,
	PosizioneLocalita = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN UPPER(ip.Localita) ELSE NULL END,
	DestinatarioNome = UPPER(sd.NomeCompleto),
	DestinatarioCodiceFiscale = ISNULL(sd.CodiceFiscale, sd.PartitaIva),
	DestinatarioSede = CAST(NULL AS VARCHAR(200)),
	DestinatarioAutorizzazioneAlbo = CASE WHEN ISNULL(da.Nessuna, 0) = 1 THEN NULL WHEN da.IdNumeroTipo = 'A' THEN da.Numero ELSE NULL END,
	DestinatarioAutorizzazione = CASE WHEN ISNULL(da.Nessuna, 0) = 1 THEN NULL WHEN da.IdNumeroTipo = 'A' THEN NULL ELSE da.Numero END,
	DestinatarioAutorizzazioneTipo = CASE WHEN ISNULL(da.Nessuna, 0) = 1 OR da.IdNumeroTipo = 'A' THEN NULL ELSE dat.Codice END,
	DestinatarioNazione = nzd.Sigla,
	DestinatarioIdComune = id_.IdComune,
	DestinatarioIndirizzo = UPPER(id_.Indirizzo + ISNULL(', ' + NULLIF(id_.NumeroCivico, ''), '')),
	DestinatarioCAP = id_.CAP,
	DestinatarioLocalita = UPPER(id_.Localita),
	Destinazione = attv.Codice,
	TrasportatoreNome = UPPER(st1.NomeCompleto),
	TrasportatoreCodiceFiscale = ISNULL(st1.CodiceFiscale, st1.PartitaIva),
	TrasportatoreAutorizzazioneAlbo = CASE WHEN ISNULL(ta1.Nessuna, 0) = 1 THEN NULL ELSE ta1.Numero END,
	TrasportatoreNazione = nzt1.Sigla,
	TrasportoTipo = CASE mt1.IdTipo WHEN 'T' THEN 'Ferroviario' WHEN 'N' THEN 'Marittimo' ELSE 'Terrestre' END,
	Trasportatore2Nome = UPPER(st2.NomeCompleto),
	Trasportatore2CodiceFiscale = ISNULL(st2.CodiceFiscale, st2.PartitaIva),
	Trasportatore2AutorizzazioneAlbo = CASE WHEN ISNULL(ta2.Nessuna, 0) = 1 THEN NULL ELSE ta2.Numero END,
	Trasportatore2Nazione = nzt2.Sigla,
	Trasporto2Tipo = CASE mt2.IdTipo WHEN 'T' THEN 'Ferroviario' WHEN 'N' THEN 'Marittimo' ELSE 'Terrestre' END,
	IntermediarioNome = UPPER(si1.NomeCompleto),
	IntermediarioCodiceFiscale = ISNULL(si1.CodiceFiscale, si1.PartitaIva),
	IntermediarioAutorizzazioneAlbo = CASE WHEN ISNULL(ia1.Nessuna, 0) = 1 THEN NULL ELSE ia1.Numero END,
	IntermediarioNazione = nzi1.Sigla,
	Intermediario2Nome = UPPER(si2.NomeCompleto),
	Intermediario2CodiceFiscale = ISNULL(si2.CodiceFiscale, si2.PartitaIva),
	Intermediario2AutorizzazioneAlbo = CASE WHEN ISNULL(ia2.Nessuna, 0) = 1 THEN NULL ELSE ia2.Numero END,
	Intermediario2Nazione = nzi2.Sigla,
	Eer = m.IdEer,
	EerDescrizione = m.EerDescrizione,
	StatoFisico = sf.Codice,
	Provenienza = ISNULL(m.IdProvenienza, 'S'),
	ClassiPericolo = cp.ClassiPericolo,
	Quantita = m.Quantita,
	QuantitaDestino = CAST(0 AS DECIMAL(18, 2)),
	QuantitaRespinta = CAST(0 AS DECIMAL(18, 2)),
	UnitaMisura = LOWER(um.Codice),
	QuantitaVerificataPartenza = ISNULL(f.VerificatoInPartenza, 0),
	Colli = f.ColliNumero,
	AllaRinfusa = ISNULL(f.AllaRinfusa, 0),
	ADR = ISNULL(f.TrasportoAdr, 0),
	ClasseADR = adr.Codice,
	NumeroONU = f.NumeroOnu,
	TargaMotrice = CASE WHEN mt1.IdTipo = 'G' THEN fg.TargaMotrice ELSE NULL END,
	TargaRimorchio = CASE WHEN mt1.IdTipo = 'G' THEN fg.TargaRimorchio ELSE NULL END,
	Percorso = CASE WHEN mt1.IdTipo = 'G' THEN fg.Percorso ELSE NULL END,
	ConducenteNome = CASE WHEN mt1.IdTipo = 'G' THEN fg.ConducenteNome ELSE NULL END,
	ConducenteCognome = CASE WHEN mt1.IdTipo = 'G' THEN fg.ConducenteCognome ELSE NULL END,
	DataOraInizioTrasporto = CASE WHEN m.DataInizioTrasporto IS NULL THEN NULL ELSE
		CONVERT(VARCHAR(33), CAST(m.DataInizioTrasporto AS DATETIME2) AT TIME ZONE 'Central European Standard Time', 127)
	END,
	OraInizioTrasporto = CAST(NULL AS VARCHAR(10)),
	Analisi = f.IdAnalisiTipo,
	AnalisiNumero = f.AnalisiNumero,
	AnalisiData = FORMAT(f.AnalisiData, 'yyyy-MM-dd'),
	Note = LEFT(f.Note, 500),
	Detentore = CASE WHEN f.Detentore = 1 THEN 'X' ELSE NULL END,
	AdrNote = f.AdrNote,
	Esito = 'A',
	DataEsito = CAST(NULL AS VARCHAR(30)),
	QuantitaRegistrata = CAST(0 AS DECIMAL(18, 2)),
	DataOraFineTrasporto = CAST('20501231' AS DATE),
	EsitoCausaleRespingimento = CAST(NULL AS VARCHAR(10)),
	RespingimentoMotivo = CAST(NULL AS VARCHAR(200)),
	IdentificativoTreno = CASE WHEN mt1.IdTipo = 'T' THEN ft.Treno ELSE NULL END,
	IdentificativoTratta = CASE WHEN mt1.IdTipo = 'T' THEN ft.Tratta ELSE NULL END,
	IdentificativoNave = CASE WHEN mt1.IdTipo = 'N' THEN fn.Nave ELSE NULL END,
	OpzioneTrenoNave = CASE mt1.IdTipo WHEN 'T' THEN ISNULL(ft.Rid, 0) WHEN 'N' THEN ISNULL(fn.Imdg, 0) ELSE CAST(0 AS BIT) END,
	Stato = m.RentriFormularioStato
FROM
	dbo.tblRifiutiFormulari f
	INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
	LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
	LEFT JOIN dbo.tblRifiutiStatiFisici sf ON m.IdStatoFisico = sf.Id
	LEFT JOIN dbo.tblUnitaMisura um ON m.IdUnitaMisura = um.Id
	LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita = attv.Id
	LEFT JOIN dbo.tblAdr adr ON f.IdAdr = adr.Id
	-- Produttore
	LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni pa ON mp.IdAutorizzazione = pa.Id
	LEFT JOIN dbo.tblRifiutiAutorizzazioniTipi pat ON pa.IdTipo = pat.Id
	LEFT JOIN dbo.tblSedi sp ON pa.IdSede = sp.Id
	LEFT JOIN dbo.tblSediIndirizzi sip ON sp.Id = sip.Id
	LEFT JOIN dbo.tblIndirizzi ip ON sip.IdIndirizzo = ip.Id
	LEFT JOIN dbo.tblNazioni nzp ON ip.IdNazione = nzp.Id
	-- Unita' locale del produttore (usata al posto di sp quando f.LuogoDiProduzione=1): nella famiglia di sp
	-- (se stessa/sorelle dirette via IdParent - ancora = ISNULL(sp.IdParent, sp.Id), stesso raggruppamento
	-- dell'invariante di uspSedi_upd), la Sede con UnitaLocale=1, altrimenti la Sede Padre di sp. NON tramite
	-- IdAziendaInterna: per le Sedi Esterne quella colonna e' l'azienda interna proprietaria (tblSediEsterne.
	-- IdSedeInterna), condivisa da tutte le sedi esterne di quell'azienda interna - non la radice della
	-- famiglia di sp - e avrebbe pescato UnitaLocale=1 da una sede sorella estranea.
	OUTER APPLY (
		SELECT Id = COALESCE(
			(SELECT TOP 1 Id
			FROM dbo.tblSedi
			WHERE
				(Id = ISNULL(sp.IdParent, sp.Id) OR IdParent = ISNULL(sp.IdParent, sp.Id))
				AND UnitaLocale = 1
			),
			sp.IdParent
		)
	) rsul
			LEFT JOIN dbo.tblSedi spul ON rsul.Id = spul.Id
			LEFT JOIN dbo.tblSediIndirizzi sipul ON spul.Id = sipul.Id
			LEFT JOIN dbo.tblIndirizzi ipul ON sipul.IdIndirizzo = ipul.Id
			LEFT JOIN dbo.tblNazioni nzpul ON ipul.IdNazione = nzpul.Id
	-- Destinatario
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni da ON md.IdAutorizzazione = da.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniTipi dat ON da.IdTipo = dat.Id
			LEFT JOIN dbo.tblSedi sd ON da.IdSede = sd.Id
			LEFT JOIN dbo.tblSediIndirizzi sid ON sd.Id = sid.Id
			LEFT JOIN dbo.tblIndirizzi id_ ON sid.IdIndirizzo = id_.Id
			LEFT JOIN dbo.tblNazioni nzd ON id_.IdNazione = nzd.Id
	-- Trasportatore 1/2
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ta1 ON mt1.IdAutorizzazione = ta1.Id
			LEFT JOIN dbo.tblSedi st1 ON ta1.IdSede = st1.Id
			LEFT JOIN dbo.tblSediIndirizzi sit1 ON st1.Id = sit1.Id
			LEFT JOIN dbo.tblIndirizzi it1 ON sit1.IdIndirizzo = it1.Id
			LEFT JOIN dbo.tblNazioni nzt1 ON it1.IdNazione = nzt1.Id
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ta2 ON mt2.IdAutorizzazione = ta2.Id
			LEFT JOIN dbo.tblSedi st2 ON ta2.IdSede = st2.Id
			LEFT JOIN dbo.tblSediIndirizzi sit2 ON st2.Id = sit2.Id
			LEFT JOIN dbo.tblIndirizzi it2 ON sit2.IdIndirizzo = it2.Id
			LEFT JOIN dbo.tblNazioni nzt2 ON it2.IdNazione = nzt2.Id
	-- Intermediario 1/2
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ia1 ON mi1.IdAutorizzazione = ia1.Id
			LEFT JOIN dbo.tblSedi si1 ON ia1.IdSede = si1.Id
			LEFT JOIN dbo.tblSediIndirizzi sii1 ON si1.Id = sii1.Id
			LEFT JOIN dbo.tblIndirizzi ii1 ON sii1.IdIndirizzo = ii1.Id
			LEFT JOIN dbo.tblNazioni nzi1 ON ii1.IdNazione = nzi1.Id
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ia2 ON mi2.IdAutorizzazione = ia2.Id
			LEFT JOIN dbo.tblSedi si2 ON ia2.IdSede = si2.Id
			LEFT JOIN dbo.tblSediIndirizzi sii2 ON si2.Id = sii2.Id
			LEFT JOIN dbo.tblIndirizzi ii2 ON sii2.IdIndirizzo = ii2.Id
			LEFT JOIN dbo.tblNazioni nzi2 ON ii2.IdNazione = nzi2.Id
	-- Trasporti (dettaglio per modalita')
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiTerresti fg ON f.Id = fg.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiFerroviari ft ON f.Id = ft.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiMarittimi fn ON f.Id = fn.Id
			LEFT JOIN (
		SELECT
			mc.Id,
			ClassiPericolo = STRING_AGG(c.Codice, ';') WITHIN GROUP (ORDER BY c.Codice)
		FROM
			dbo.tblRifiutiMovimentiClassiPericolo mc
			LEFT JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
		GROUP BY
			mc.Id
	) cp ON m.Id = cp.Id
GO

