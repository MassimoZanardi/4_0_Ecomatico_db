/*
Deploy produzione 2026-10-23 - Registrazioni: ricerca per Carico/Scarico e Operazione; Tracciabilità fino ai DDT

Rieseguibile. Eseguire con sqlcmd -f 65001 -I -b (oppure da SSMS) sul DB 4_0_ecomatico, PRIMA di pubblicare l'app:
le SP accettano i parametri nuovi come facoltativi e restituiscono colonne in più, quindi funzionano anche con l'app
attuale; l'app nuova invece passa i parametri nuovi e senza queste SP la ricerca delle registrazioni darebbe errore.

uspRifiutiOperazioni_get_SelectList: parametro @Operazione (C, S, X) per proporre solo le operazioni del gruppo.
uspRifiutiRegistrazioni_get_List, uspRifiutiRegistrazioni_get_Esportazione: parametri @Operazione (Carico/Scarico
della registrazione) e @IdOperazione (operazione specifica del movimento).
uspRifiutiRegistrazioni_get_Tracciabilita_List: un nodo per lotto EoW (prima un lotto con più registrazioni della
filiera compariva più volte), passaggi registrazione -> lotto, livello degli scarichi di magazzino che prelevano dai
lotti (DDT o movimento), con il modulo Magazzino attivo e il permesso MAG.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiOperazioni_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IsRentri BIT = NULL,
	@IsFormulario BIT = NULL,
	@IsIntegrazioneFir BIT = NULL,
	@Operazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- @IsRentri          = NULL → nessun filtro; = 1 → solo Rentri
		-- @IsFormulario      = NULL → nessun filtro; = 0 → senza formulario; = 1 → con formulario
		-- @IsIntegrazioneFir = NULL → nessun filtro; = 1 → solo operazioni che integrano un FIR altrui
		--                     (Rifiuti/Registrazioni, importazione da formulario digitale RENTRI - piu' ampio
		--                     di IsFormulario: include anche Z/I che non emettono un proprio FIR)
		-- @Operazione        = NULL → nessun filtro; altrimenti solo le operazioni del raggruppamento
		--                     (C carico, S scarico, X carico e scarico - ricerca di Rifiuti/Registrazioni)

		IF @IsFormulario = 1 SET @IsRentri = NULL;
		IF @IsIntegrazioneFir = 1 SET @IsRentri = NULL;

		SELECT
			Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(1 AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			o.Id,
			[Text] = CAST(o.Pos AS VARCHAR(2)) + '. ' + o.Nome,
			Selected = CAST(0 AS BIT),
			o.Pos
		FROM
			dbo.tblRifiutiOperazioni o
			INNER JOIN dbo.tblRifiutiOperazioniRegistriTipi ot ON o.Id = ot.Id
			INNER JOIN dbo.tblRifiutiRegistri r ON ot.IdTipo = r.IdTipo
			INNER JOIN dbo.tblSessioni e ON r.Id = e.IdRegistro
		WHERE
			e.Id = @IdSessione
			AND
				(
				@IsRentri IS NULL
				OR o.IsRentri = @IsRentri
				)
			AND
				(
				@IsFormulario IS NULL
				OR ISNULL(o.IsFormulario, 0) = @IsFormulario
				)
			AND
				(
				@IsIntegrazioneFir IS NULL
				OR ISNULL(o.IsIntegrazioneFir, 0) = @IsIntegrazioneFir
				)
			AND
				(
				@Operazione IS NULL
				OR o.Operazione = @Operazione
				)
		ORDER BY Pos
		OPTION (RECOMPILE);
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
	@Etichetta VARCHAR(50) = NULL,
	@Operazione CHAR(1) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@NonTrasmesseRentri BIT = 0,
	@NonInConservazione BIT = 0,
	@SenzaEsito BIT = 0,
	@XfirSenzaPresaVisione BIT = 0,
	@XfirAttesaAccettazione BIT = 0,
	@XfirCopiaNonCaricata BIT = 0,
	@XfirCopiaNonTrasmessa BIT = 0
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
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');

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
            @Etichetta   VARCHAR(50),
            @Operazione   CHAR(1),
            @IdOperazione CHAR(1)';

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
                RentriFormularioStato    = m.RentriFormularioStato,
                RentriFormularioCartaceo = ISNULL(m.RentriFormularioCartaceo, 0)
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

		-- Carico/Scarico: raggruppamento della registrazione (C, S, X = carico e scarico); Operazione:
		-- l'operazione specifica del movimento. Senza Operazione si filtra solo per Carico/Scarico.
		IF @Operazione IS NOT NULL
			SET @stmt = @stmt + N' AND r.Operazione = @Operazione';

		IF @IdOperazione IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdOperazione = @IdOperazione';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		IF @NonTrasmesseRentri = 1
			SET @stmt = @stmt + N' AND r.RentriData IS NULL';

		-- "Non inviate in conservazione" = conservazione del registro (RentriDataInvioConservazione nel
		-- pannello "RENTRI - Stato"): NOT EXISTS anziché OUTER APPLY per non pagare il join cross-database
		-- su ogni riga quando il flag non è richiesto.
		IF @NonInConservazione = 1
			SET @stmt = @stmt + N' AND NOT EXISTS (
                SELECT 1 FROM [1_0_rentri]..tblRegistriConservazioni con
                WHERE con.IdRegistro = z.IdRentri COLLATE DATABASE_DEFAULT
                    AND con.Anno = YEAR(r.[Data])
                    AND r.Numero BETWEEN con.DalNumero AND con.AlNumero
                    AND con.Conservazione = 1
            )';

		IF @SenzaEsito = 1
			SET @stmt = @stmt + N' AND r.DataFineTrasporto IS NULL';

		-- I successivi 3 flag riguardano solo registrazioni con un xFIR collegato (RentriFormularioStato
		-- valorizzato): altrimenti il filtro intercetterebbe anche tutte le registrazioni senza alcun
		-- formulario digitale, per le quali le date sotto sono banalmente NULL.
		IF @XfirSenzaPresaVisione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataPresaVisione IS NULL';

		IF @XfirAttesaAccettazione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato = ''InserimentoAccettazione''';

		IF @XfirCopiaNonCaricata = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataCopia IS NULL';

		IF @XfirCopiaNonTrasmessa = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataTrasmissione IS NULL';

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
            tbl.RentriFormularioStato, tbl.RentriFormularioCartaceo,
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
			@Etichetta = @Etichetta,
			@Operazione = @Operazione,
			@IdOperazione = @IdOperazione;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registrazioni dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel,
-- Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca (SQL dinamico compreso) sono
-- ricopiati da uspRifiutiRegistrazioni_get_List e vanno tenuti allineati a quella. Tutte le righe, senza
-- paginazione: al massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Come nell'elenco, quantità e dati del rifiuto sono quelli della registrazione, non i valori effettivi dopo le
-- rettifiche: una rettifica è una riga a sé.
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL,
	@Operazione CHAR(1) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@NonTrasmesseRentri BIT = 0,
	@NonInConservazione BIT = 0,
	@SenzaEsito BIT = 0,
	@XfirSenzaPresaVisione BIT = 0,
	@XfirAttesaAccettazione BIT = 0,
	@XfirCopiaNonCaricata BIT = 0,
	@XfirCopiaNonTrasmessa BIT = 0,
	@MaxRighe INT = NULL
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
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
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

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @MaxRighe    INT,
            @IdSessione  CHAR(16),
            @DallaData   DATE,
            @AllaData    DATE,
            @Soggetto    VARCHAR(50),
            @Eer         VARCHAR(50),
            @Formulario  VARCHAR(50),
            @Etichetta   VARCHAR(50),
            @Operazione   CHAR(1),
            @IdOperazione CHAR(1)';

		-- Scope: registro corrente della sessione (tblSessioni.IdRegistro); senza registro nessuna riga
		SET @stmt = N'
        SELECT TOP (@MaxRighe + 1)
            [Numero]                    = r.Numero,
            [Data]                      = r.Data,
            [Stato]                     = CASE WHEN r.Lock = 1 THEN ''Da confermare'' ELSE ''Confermata'' END,
            [Operazione]                = o.Nome,
            [Codice EER]                = ISNULL(c.Nome, t.Codice),
            [Descrizione]               = ISNULL(c.Descrizione, t.Nome),
            [Pericoloso]                = CASE c.Pericoloso WHEN 1 THEN ''Sì'' WHEN 0 THEN ''No'' END,
            [Stato fisico]              = s.Nome,
            [Quantità]                  = m.Quantita * IIF(r.Operazione = ''S'', -1, 1),
            [Unità di misura]           = um.Codice,
            [Quantità verificata]       = r.QuantitaVerificata * IIF(r.Operazione = ''S'', -1, 1),
            [Attività]                  = a.Codice,
            [Formulario]                = m.FormularioNumero,
            [Inizio trasporto]          = m.DataInizioTrasporto,
            [Fine trasporto]            = r.DataFineTrasporto,
            [Esito]                     = es.Nome,
            [Produttore o detentore]    = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
            [Trasportatore]             = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
            [Destinatario]              = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
            [Intermediario]             = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
            [Etichette]                 = (SELECT STRING_AGG(x.Nome, '', '') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiRegistrazioniEtichette re INNER JOIN dbo.tblEtichette x ON re.IdEtichetta = x.Id WHERE re.Id = r.Id),
            [Rettifica]                 = CASE WHEN rett.Id IS NULL THEN NULL WHEN rett.Annullata = 1 THEN ''Annullamento'' ELSE ''Correzione'' END,
            [Registrazione rettificata] = ro.Numero,
            [Del]                       = ro.Data,
            [Identificativo RENTRI]     = r.RentriIdentificativo,
            [Trasmessa a RENTRI il]     = r.RentriData,
            [Stato del formulario digitale] = m.RentriFormularioStato,
            [Note]                      = r.Note
        FROM
            dbo.tblRifiutiRegistrazioni                  r
            INNER JOIN dbo.tblRifiutiMovimenti           m  ON r.IdMovimento               = m.Id
            INNER JOIN dbo.tblRifiutiRegistri            g  ON m.IdRegistro                = g.Id
            INNER JOIN dbo.tblSessioni                   e  ON g.Id                        = e.IdRegistro
            LEFT  JOIN dbo.tblRifiutiOperazioni          o  ON m.IdOperazione              = o.Id
            LEFT  JOIN dbo.tblRifiutiEer                 c  ON m.IdEer                     = c.Id
            LEFT  JOIN dbo.tblRifiutiStatiFisici         s  ON m.IdStatoFisico             = s.Id
            LEFT  JOIN dbo.tblRifiutiMateriali           t  ON r.IdMateriale               = t.Id
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
            LEFT  JOIN dbo.tblUnitaMisura                um ON m.IdUnitaMisura             = um.Id
            LEFT  JOIN dbo.tblRifiutiRegistrazioniEsiti  es ON r.IdEsito                   = es.Id
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

		IF @Operazione IS NOT NULL
			SET @stmt = @stmt + N' AND r.Operazione = @Operazione';

		IF @IdOperazione IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdOperazione = @IdOperazione';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		IF @NonTrasmesseRentri = 1
			SET @stmt = @stmt + N' AND r.RentriData IS NULL';

		-- "Non inviate in conservazione" = conservazione del registro: NOT EXISTS sul DB 1_0_rentri
		IF @NonInConservazione = 1
			SET @stmt = @stmt + N' AND NOT EXISTS (
                SELECT 1 FROM [1_0_rentri]..tblRegistriConservazioni con
                WHERE con.IdRegistro = z.IdRentri COLLATE DATABASE_DEFAULT
                    AND con.Anno = YEAR(r.[Data])
                    AND r.Numero BETWEEN con.DalNumero AND con.AlNumero
                    AND con.Conservazione = 1
            )';

		IF @SenzaEsito = 1
			SET @stmt = @stmt + N' AND r.DataFineTrasporto IS NULL';

		-- I flag sul formulario digitale riguardano solo le registrazioni con un xFIR collegato
		-- (RentriFormularioStato valorizzato)
		IF @XfirSenzaPresaVisione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataPresaVisione IS NULL';

		IF @XfirAttesaAccettazione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato = ''InserimentoAccettazione''';

		IF @XfirCopiaNonCaricata = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataCopia IS NULL';

		IF @XfirCopiaNonTrasmessa = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataTrasmissione IS NULL';

		SET @stmt = @stmt + N'
        ORDER BY r.Data DESC, r.Numero DESC
        OPTION (RECOMPILE);';

		EXEC sp_executesql
			@stmt,
			@params,
			@MaxRighe = @MaxRighe,
			@IdSessione = @IdSessione,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Soggetto = @Soggetto,
			@Eer = @Eer,
			@Formulario = @Formulario,
			@Etichetta = @Etichetta,
			@Operazione = @Operazione,
			@IdOperazione = @IdOperazione;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_Tracciabilita_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
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

		-- Controlla il permesso sulla funzione
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

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				r.Id = @Id
				AND r.Lock < 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Tracciabilità della registrazione: la filiera delle registrazioni collegate da relazioni di carico/scarico,
		-- dalla più vecchia (Livello negativo) alla più recente (Livello positivo), Livello 0 = la registrazione.
		-- Una riga di tblRifiutiRegistrazioniRelazioni ha sempre Id = scarico e IdParent = carico, ma il flusso può
		-- andare in entrambi i versi: consumo (carico -> scarico che preleva) e derivazione (scarico per trattamento
		-- interno -> carico generato, es. M/NP). Il verso del flusso è quindi cronologico (Data, poi Numero): in ogni
		-- coppia la registrazione più vecchia precede la più recente. A monte si seguono solo le più vecchie, a valle
		-- solo le più recenti: non si allarga ai rami paralleli (es. altri scarichi dello stesso carico).
		DECLARE @nodi TABLE (
			Id CHAR(16) PRIMARY KEY,
			Livello INT
		);
		DECLARE @passaggi TABLE (
			IdDa CHAR(16),
			IdA CHAR(16),
			Quantita DECIMAL(18, 2),
			PRIMARY KEY (IdDa, IdA)
		);
		DECLARE @livello INT;
		DECLARE @livelliMax INT = 20;

		-- Coppie collegate tra registrazioni attive, raccolte a ogni passo per le registrazioni del livello corrente,
		-- con il verso cronologico (IdScarico/IdCarico = la riga di relazione, IdVecchia/IdRecente = il flusso)
		DECLARE @coppie TABLE (
			IdScarico CHAR(16),
			IdCarico CHAR(16),
			IdVecchia CHAR(16),
			IdRecente CHAR(16),
			Quantita DECIMAL(18, 2),
			PRIMARY KEY (IdScarico, IdCarico)
		);

		INSERT INTO @nodi (Id, Livello)
		VALUES (@Id, 0);

		-- A monte: dalla registrazione verso le più vecchie
		SET @livello = 0;
		WHILE @livello > -@livelliMax
		BEGIN
			INSERT INTO @coppie (IdScarico, IdCarico, IdVecchia, IdRecente, Quantita)
			SELECT
				l.Id,
				l.IdParent,
				IdVecchia = IIF(a.[Data] < b.[Data] OR (a.[Data] = b.[Data] AND a.Numero < b.Numero), a.Id, b.Id),
				IdRecente = IIF(a.[Data] < b.[Data] OR (a.[Data] = b.[Data] AND a.Numero < b.Numero), b.Id, a.Id),
				l.Quantita
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni a ON l.Id = a.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni b ON l.IdParent = b.Id
			WHERE
				a.Lock < 2
				AND b.Lock < 2
				AND
					(
					l.Id IN (SELECT Id FROM @nodi WHERE Livello = @livello)
					OR l.IdParent IN (SELECT Id FROM @nodi WHERE Livello = @livello)
					)
				AND NOT EXISTS (SELECT 1 FROM @coppie c WHERE c.IdScarico = l.Id AND c.IdCarico = l.IdParent);

			INSERT INTO @passaggi (IdDa, IdA, Quantita)
			SELECT c.IdVecchia, c.IdRecente, SUM(c.Quantita)
			FROM
				@coppie c
				INNER JOIN @nodi n ON c.IdRecente = n.Id
			WHERE
				n.Livello = @livello
				AND NOT EXISTS (SELECT 1 FROM @passaggi p WHERE p.IdDa = c.IdVecchia AND p.IdA = c.IdRecente)
			GROUP BY c.IdVecchia, c.IdRecente;

			INSERT INTO @nodi (Id, Livello)
			SELECT DISTINCT c.IdVecchia, @livello - 1
			FROM
				@coppie c
				INNER JOIN @nodi n ON c.IdRecente = n.Id
			WHERE
				n.Livello = @livello
				AND NOT EXISTS (SELECT 1 FROM @nodi x WHERE x.Id = c.IdVecchia);

			IF @@ROWCOUNT = 0 BREAK;
			SET @livello = @livello - 1;
		END

		-- A valle: dalla registrazione verso le più recenti
		SET @livello = 0;
		WHILE @livello < @livelliMax
		BEGIN
			INSERT INTO @coppie (IdScarico, IdCarico, IdVecchia, IdRecente, Quantita)
			SELECT
				l.Id,
				l.IdParent,
				IdVecchia = IIF(a.[Data] < b.[Data] OR (a.[Data] = b.[Data] AND a.Numero < b.Numero), a.Id, b.Id),
				IdRecente = IIF(a.[Data] < b.[Data] OR (a.[Data] = b.[Data] AND a.Numero < b.Numero), b.Id, a.Id),
				l.Quantita
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni a ON l.Id = a.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni b ON l.IdParent = b.Id
			WHERE
				a.Lock < 2
				AND b.Lock < 2
				AND
					(
					l.Id IN (SELECT Id FROM @nodi WHERE Livello = @livello)
					OR l.IdParent IN (SELECT Id FROM @nodi WHERE Livello = @livello)
					)
				AND NOT EXISTS (SELECT 1 FROM @coppie c WHERE c.IdScarico = l.Id AND c.IdCarico = l.IdParent);

			INSERT INTO @passaggi (IdDa, IdA, Quantita)
			SELECT c.IdVecchia, c.IdRecente, SUM(c.Quantita)
			FROM
				@coppie c
				INNER JOIN @nodi n ON c.IdVecchia = n.Id
			WHERE
				n.Livello = @livello
				AND NOT EXISTS (SELECT 1 FROM @passaggi p WHERE p.IdDa = c.IdVecchia AND p.IdA = c.IdRecente)
			GROUP BY c.IdVecchia, c.IdRecente;

			INSERT INTO @nodi (Id, Livello)
			SELECT DISTINCT c.IdRecente, @livello + 1
			FROM
				@coppie c
				INNER JOIN @nodi n ON c.IdVecchia = n.Id
			WHERE
				n.Livello = @livello
				AND NOT EXISTS (SELECT 1 FROM @nodi x WHERE x.Id = c.IdRecente);

			IF @@ROWCOUNT = 0 BREAK;
			SET @livello = @livello + 1;
		END

		-- Lotti EoW (solo con modulo attivo e permesso): il livello dopo la filiera, un nodo per lotto anche quando vi
		-- confluiscono piu' registrazioni della filiera, piu' la quantita' ancora da allocare
		DECLARE @isEoW BIT = 0;
		DECLARE @permessoEoW TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permessoEoW OUTPUT;
		IF dbo.ufnModuli_get_IsAttivoBySessione('EOW', @IdSessione) = 1 AND ISNULL(@permessoEoW, 0) >= 1
			SET @isEoW = 1;

		-- Scarichi dal magazzino dei lotti (solo con EoW, modulo Magazzino attivo e permesso MAG): il livello dopo i
		-- lotti, un nodo per movimento di scarico (con il suo DDT, se c'e') anche quando preleva da piu' lotti
		DECLARE @isMagazzino BIT = 0;
		DECLARE @permessoMagazzino TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permessoMagazzino OUTPUT;
		IF @isEoW = 1 AND dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione) = 1 AND ISNULL(@permessoMagazzino, 0) >= 1
			SET @isMagazzino = 1;

		DECLARE @livelloLotti INT = (SELECT MAX(Livello) + 1
		FROM @nodi);

		-- Allocazioni delle registrazioni della filiera ai lotti (passaggi registrazione -> lotto)
		DECLARE @allocazioni TABLE (
			IdRegistrazione CHAR(16),
			IdLotto CHAR(16),
			Quantita DECIMAL(18, 2),
			PRIMARY KEY (IdRegistrazione, IdLotto)
		);
		INSERT INTO @allocazioni (IdRegistrazione, IdLotto, Quantita)
		SELECT q.IdRegistrazione, q.IdLotto, SUM(q.Quantita)
		FROM
			@nodi n
			INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni q ON n.Id = q.IdRegistrazione
		WHERE
			@isEoW = 1
			AND q.Quantita > 0
		GROUP BY q.IdRegistrazione, q.IdLotto;

		-- Il lotto non ha un'unita' di misura propria: e' quella delle registrazioni allocate
		DECLARE @lotti TABLE (
			Id CHAR(16) PRIMARY KEY,
			Quantita DECIMAL(18, 2),
			UnitaMisuraCodice VARCHAR(10),
			Ordine INT
		);
		INSERT INTO @lotti (Id, Quantita, UnitaMisuraCodice, Ordine)
		SELECT
			a.IdLotto,
			SUM(a.Quantita),
			MAX(u.Codice),
			ROW_NUMBER() OVER (ORDER BY MIN(r.[Data]), MIN(r.Numero), MAX(l.Nome))
		FROM
			@allocazioni a
			INNER JOIN dbo.tblEoWLotti l ON a.IdLotto = l.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
		GROUP BY a.IdLotto;

		-- Prelievi dei movimenti di magazzino confermati dai lotti (passaggi lotto -> scarico), come la Scaricata di
		-- ufnEoWLotti_get_Saldo: riga EoW e movimento Lock = 0
		DECLARE @prelievi TABLE (
			IdLotto CHAR(16),
			IdMovimento CHAR(16),
			Quantita DECIMAL(18, 2),
			PRIMARY KEY (IdLotto, IdMovimento)
		);
		INSERT INTO @prelievi (IdLotto, IdMovimento, Quantita)
		SELECT rl.IdLotto, rg.IdMovimento, SUM(rl.Quantita)
		FROM
			@lotti l
			INNER JOIN dbo.tblMagazziniMovimentiRigheEoWLotti rl ON l.Id = rl.IdLotto
			INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rl.Id = rg.Id
			INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
		WHERE
			@isMagazzino = 1
			AND rg.Lock = 0
			AND ms.Lock = 0
			AND rl.Quantita > 0
		GROUP BY rl.IdLotto, rg.IdMovimento;

		-- Tipo: R = registrazione, L = lotto EoW, A = quantità da allocare, D = scarico di magazzino (con il DDT, se
		-- c'è: IsDdt, Numero e Data del DDT; altrimenti Numero e Data del movimento), P = passaggio tra due righe
		SELECT
			Tipo = 'R',
			n.Livello,
			r.Id,
			IdDa = CAST(NULL AS CHAR(16)),
			r.Numero,
			r.[Data],
			OperazioneCodice = o.Codice,
			OperazioneNome = o.Nome,
			EerCodice = e.Nome,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			StatoFisicoNome = sf.Nome,
			v.Quantita,
			UnitaMisuraCodice = u.Codice,
			LottoNome = CAST(NULL AS VARCHAR(50)),
			IsDdt = CAST(0 AS BIT),
			DdtSezionale = CAST(NULL AS VARCHAR(5)),
			DestinatarioNome = CAST(NULL AS VARCHAR(500)),
			IsCorrente = CAST(IIF(r.Id = @Id, 1, 0) AS BIT),
			v.IsAnnullata,
			Ordine = ROW_NUMBER() OVER (PARTITION BY n.Livello ORDER BY r.[Data], r.Numero)
		FROM
			@nodi n
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON n.Id = r.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici sf ON v.IdStatoFisico = sf.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id

		UNION ALL

		SELECT
			Tipo = 'L',
			@livelloLotti,
			l.Id,
			IdDa = NULL,
			Numero = NULL,
			[Data] = NULL,
			OperazioneCodice = NULL,
			OperazioneNome = NULL,
			EerCodice = NULL,
			MaterialeNome = mat.Nome,
			StatoFisicoNome = NULL,
			ql.Quantita,
			ql.UnitaMisuraCodice,
			LottoNome = l.Nome,
			IsDdt = CAST(0 AS BIT),
			DdtSezionale = NULL,
			DestinatarioNome = NULL,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			ql.Ordine
		FROM
			@lotti ql
			INNER JOIN dbo.tblEoWLotti l ON ql.Id = l.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON l.IdMateriale = mat.Id

		UNION ALL

		-- Quantità della registrazione di materiale non ancora allocata ai lotti EoW
		SELECT
			Tipo = 'A',
			@livelloLotti,
			Id = r.Id,
			IdDa = r.Id,
			r.Numero,
			r.[Data],
			OperazioneCodice = NULL,
			OperazioneNome = NULL,
			EerCodice = NULL,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			StatoFisicoNome = NULL,
			Quantita = v.Quantita - ISNULL(qa.Allocata, 0),
			UnitaMisuraCodice = u.Codice,
			LottoNome = NULL,
			IsDdt = CAST(0 AS BIT),
			DdtSezionale = NULL,
			DestinatarioNome = NULL,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = 1000 + ROW_NUMBER() OVER (ORDER BY r.[Data], r.Numero)
		FROM
			@nodi n
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON n.Id = r.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
			OUTER APPLY (
				SELECT Allocata = SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q
				WHERE q.IdRegistrazione = r.Id) qa
		WHERE
			@isEoW = 1
			AND o.IsMateriale = 1
			AND v.Quantita - ISNULL(qa.Allocata, 0) > 0

		UNION ALL

		-- Scarichi di magazzino: Quantita = quanto il movimento ha prelevato dai lotti della filiera (dal lotto
		-- intero: la parte che viene dalla sola filiera non e' calcolabile, il lotto mescola il materiale)
		SELECT
			Tipo = 'D',
			@livelloLotti + 1,
			ms.Id,
			IdDa = NULL,
			Numero = ISNULL(d.Numero, ms.Numero),
			[Data] = ISNULL(d.[Data], ms.[Data]),
			OperazioneCodice = NULL,
			OperazioneNome = mo.Nome,
			EerCodice = NULL,
			MaterialeNome = NULL,
			StatoFisicoNome = NULL,
			p.Quantita,
			p.UnitaMisuraCodice,
			LottoNome = NULL,
			IsDdt = CAST(IIF(d.Id IS NOT NULL, 1, 0) AS BIT),
			DdtSezionale = d.Sezionale,
			DestinatarioNome = sd.NomeCompleto,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = ROW_NUMBER() OVER (ORDER BY ISNULL(d.[Data], ms.[Data]), ms.[Data], ms.Numero)
		FROM
			(
			SELECT pr.IdMovimento, Quantita = SUM(pr.Quantita), UnitaMisuraCodice = MAX(ql.UnitaMisuraCodice)
			FROM
				@prelievi pr
				INNER JOIN @lotti ql ON pr.IdLotto = ql.Id
			GROUP BY pr.IdMovimento
			) p
			INNER JOIN dbo.tblMagazziniMovimenti ms ON p.IdMovimento = ms.Id
			LEFT JOIN dbo.tblMagazziniOperazioni mo ON ms.IdOperazione = mo.Id
			LEFT JOIN dbo.tblMagazziniDdt d ON ms.Id = d.IdMovimento AND d.Lock = 0
			LEFT JOIN dbo.tblSedi sd ON d.IdDestinatario = sd.Id

		UNION ALL

		-- Passaggi: tra registrazioni (livelli consecutivi), registrazione -> lotto, lotto -> scarico di magazzino
		SELECT
			Tipo = 'P',
			Livello = a.Livello,
			Id = p.IdA,
			p.IdDa,
			Numero = NULL,
			[Data] = NULL,
			OperazioneCodice = NULL,
			OperazioneNome = NULL,
			EerCodice = NULL,
			MaterialeNome = NULL,
			StatoFisicoNome = NULL,
			p.Quantita,
			UnitaMisuraCodice = u.Codice,
			LottoNome = NULL,
			IsDdt = CAST(0 AS BIT),
			DdtSezionale = NULL,
			DestinatarioNome = NULL,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = 0
		FROM
			@passaggi p
			INNER JOIN @nodi a ON p.IdA = a.Id
			INNER JOIN @nodi d ON p.IdDa = d.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON p.IdA = v.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
		WHERE a.Livello = d.Livello + 1

		UNION ALL

		SELECT
			Tipo = 'P',
			@livelloLotti,
			Id = a.IdLotto,
			IdDa = a.IdRegistrazione,
			Numero = NULL,
			[Data] = NULL,
			OperazioneCodice = NULL,
			OperazioneNome = NULL,
			EerCodice = NULL,
			MaterialeNome = NULL,
			StatoFisicoNome = NULL,
			a.Quantita,
			ql.UnitaMisuraCodice,
			LottoNome = NULL,
			IsDdt = CAST(0 AS BIT),
			DdtSezionale = NULL,
			DestinatarioNome = NULL,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = 0
		FROM
			@allocazioni a
			INNER JOIN @lotti ql ON a.IdLotto = ql.Id

		UNION ALL

		SELECT
			Tipo = 'P',
			@livelloLotti + 1,
			Id = pr.IdMovimento,
			IdDa = pr.IdLotto,
			Numero = NULL,
			[Data] = NULL,
			OperazioneCodice = NULL,
			OperazioneNome = NULL,
			EerCodice = NULL,
			MaterialeNome = NULL,
			StatoFisicoNome = NULL,
			pr.Quantita,
			ql.UnitaMisuraCodice,
			LottoNome = NULL,
			IsDdt = CAST(0 AS BIT),
			DdtSezionale = NULL,
			DestinatarioNome = NULL,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = 0
		FROM
			@prelievi pr
			INNER JOIN @lotti ql ON pr.IdLotto = ql.Id
		ORDER BY Livello, Tipo DESC, Ordine;

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
