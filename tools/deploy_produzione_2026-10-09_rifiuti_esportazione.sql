/*
Deploy produzione 2026-10-09 - Esportazione in Excel e CSV degli elenchi del modulo Rifiuti

Indipendente dagli altri script del 2026-10-09: usa solo tabelle e SP già in produzione. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

SP di esportazione, una per elenco: stesse righe e stesso ordine della SP dell'elenco, colonne con il nome
dell'intestazione, al massimo @MaxRighe + 1 righe.
1. uspRifiutiRegistrazioni_get_Esportazione: registrazioni.
2. uspRifiutiFormulari_get_Esportazione: formulari.
3. uspRifiutiGiacenze_get_Esportazione: giacenze per EER, per materiale e per etichette (chiama
   uspRifiutiGiacenze_get_List).
4. uspRifiutiGiacenze_get_Carichi_Esportazione: carichi in giacenza (chiama
   uspRifiutiGiacenze_get_Carichi_List).
5. uspRifiutiModelli_get_Esportazione: modelli.
6. uspRifiutiAutorizzazioni_get_Esportazione: autorizzazioni.
7. uspRifiutiRegistri_get_Esportazione: registri.
8. uspRifiutiLimiti_get_Esportazione: limiti.
9. uspRifiutiMud_get_Esportazione: dichiarazioni MUD.
10. uspEtichette_get_Esportazione: etichette di un modulo (qui usata per le etichette dei rifiuti).

Nessuna modifica alle tabelle né alle SP degli elenchi. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/


PRINT 'uspRifiutiRegistrazioni_get_Esportazione';
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
            @Etichetta   VARCHAR(50)';

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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspRifiutiFormulari_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Formulari dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel,
-- Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca (SQL dinamico compreso) sono
-- ricopiati da uspRifiutiFormulari_get_List e vanno tenuti allineati a quella. Tutte le righe, senza
-- paginazione: al massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL,
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
			@IdFunzione = 'RFR',
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
            @Etichetta   VARCHAR(50)';

		-- Scope: registro corrente della sessione (tblSessioni.IdRegistro); senza registro nessuna riga.
		-- Data di emissione: come nell'elenco, un formulario senza data vale come emesso oggi
		SET @stmt = N'
        SELECT TOP (@MaxRighe + 1)
            [Formulario]             = m.FormularioNumero,
            [Data di emissione]      = CAST(ISNULL(f.DataEmissione, GETDATE()) AS DATE),
            [Stato]                  = CASE WHEN f.Lock = 1 THEN ''Non confermato'' WHEN r.Id IS NULL THEN ''Non registrato'' ELSE ''Registrato'' END,
            [Operazione]             = op.Nome,
            [Codice EER]             = c.Nome,
            [Descrizione]            = c.Descrizione,
            [Pericoloso]             = CASE c.Pericoloso WHEN 1 THEN ''Sì'' WHEN 0 THEN ''No'' END,
            [Stato fisico]           = s.Nome,
            [Quantità]               = m.Quantita,
            [Unità di misura]        = um.Codice,
            [Attività]               = a.Codice,
            [Registrazione]          = r.Numero,
            [Data registrazione]     = r.[Data],
            [Inizio trasporto]       = m.DataInizioTrasporto,
            [Produttore o detentore] = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
            [Trasportatore]          = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
            [Destinatario]           = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
            [Intermediario]          = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
            [Colli]                  = f.ColliNumero,
            [Alla rinfusa]           = IIF(f.AllaRinfusa = 1, ''Sì'', ''No''),
            [Trasporto ADR]          = IIF(f.TrasportoAdr = 1, ''Sì'', ''No''),
            [Numero ONU]             = f.NumeroOnu,
            [Etichette]              = (SELECT STRING_AGG(x.Nome, '', '') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiFormulariEtichette fe INNER JOIN dbo.tblEtichette x ON fe.IdEtichetta = x.Id WHERE fe.Id = f.Id),
            [Identificativo RENTRI]  = r.RentriIdentificativo,
            [Registrazione trasmessa a RENTRI il] = r.RentriData,
            [Stato del formulario digitale] = m.RentriFormularioStato,
            [Formulario cartaceo]    = IIF(m.RentriFormularioCartaceo = 1, ''Sì'', ''No''),
            [Note]                   = f.Note
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
            LEFT  JOIN dbo.tblUnitaMisura                um ON m.IdUnitaMisura             = um.Id
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

		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		-- I flag sul formulario digitale riguardano solo i formulari con un xFIR RENTRI collegato
		-- (RentriFormularioStato valorizzato)
		IF @XfirAttesaAccettazione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato = ''InserimentoAccettazione''';

		IF @XfirCopiaNonCaricata = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataCopia IS NULL';

		IF @XfirCopiaNonTrasmessa = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataTrasmissione IS NULL';

		SET @stmt = @stmt + N'
        ORDER BY ISNULL(f.DataEmissione, GETDATE()) DESC, m.FormularioNumero DESC
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspRifiutiGiacenze_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze dei rifiuti (viste per EER, per materiale e per etichette): righe per l'esportazione dell'elenco in
-- Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che
-- finisce nel file: l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello
-- stesso ordine. Per cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo della giacenza NON è ricopiato. La SP chiama
-- uspRifiutiGiacenze_get_List (che controlla anche permesso e titolarità del registro) e ne rinomina le
-- colonne: se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiGiacenze_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		DECLARE @righe INT = @MaxRighe + 1;

		CREATE TABLE #righe (
			TipoCodice CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			Tipo VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Id VARCHAR(6) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			IdStatoFisico CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			StatoFisico VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(2000) COLLATE DATABASE_DEFAULT NULL,
			Quantita DECIMAL(38, 2) NULL,
			GiacenzaGiorni INT NULL,
			MovimentiNumero INT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO #righe (TipoCodice, Tipo, Id, Nome, Descrizione, IdStatoFisico, StatoFisico, Etichette, Quantita, GiacenzaGiorni, MovimentiNumero, StatoValore, StatoDescrizione)
		EXEC dbo.uspRifiutiGiacenze_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdRegistro = @IdRegistro,
			@Data = @Data,
			@Vista = @Vista,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		IF @Vista = 'M'
			SELECT
				[Materiale] = Nome,
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Movimenti] = MovimentiNumero
			FROM #righe
			ORDER BY GiacenzaGiorni DESC, Nome, StatoFisico, Tipo, Etichette;
		ELSE IF @Vista = 'T'
			SELECT
				[Tipo] = Tipo,
				[Etichette] = (SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(Etichette) WITH (Nome VARCHAR(50) '$.Nome') j),
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Movimenti] = MovimentiNumero
			FROM #righe
			ORDER BY GiacenzaGiorni DESC, Nome, StatoFisico, Tipo, Etichette;
		ELSE
			SELECT
				[Tipo] = Tipo,
				[Codice EER] = Nome,
				[Descrizione] = Descrizione,
				[Stato fisico] = StatoFisico,
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Movimenti] = MovimentiNumero
			FROM #righe
			ORDER BY GiacenzaGiorni DESC, Nome, StatoFisico, Tipo, Etichette;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspRifiutiGiacenze_get_Carichi_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze dei rifiuti, carichi in giacenza: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni >
-- Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file:
-- l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per
-- cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo della giacenza NON è ricopiato. La SP chiama
-- uspRifiutiGiacenze_get_Carichi_List (che controlla anche permesso e titolarità del registro) e ne rinomina
-- le colonne: se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiGiacenze_get_Carichi_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Tipo CHAR(1) = NULL,
	@Id CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Etichette VARCHAR(2000) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		CREATE TABLE #righe (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Numero INT NULL,
			[Data] DATE NULL,
			IdEer VARCHAR(6) COLLATE DATABASE_DEFAULT NULL,
			EerNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			IdStatoFisico CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			StatoFisico VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(2000) COLLATE DATABASE_DEFAULT NULL,
			IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			Quantita DECIMAL(38, 2) NULL,
			QuantitaAssegnata DECIMAL(38, 2) NULL,
			QuantitaResidua DECIMAL(38, 2) NULL,
			GiacenzaGiorni INT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, Numero, [Data], IdEer, EerNome, IdStatoFisico, StatoFisico, Etichette, IdUnitaMisura, Quantita, QuantitaAssegnata, QuantitaResidua, GiacenzaGiorni, StatoValore, StatoDescrizione, RowsCount)
		EXEC dbo.uspRifiutiGiacenze_get_Carichi_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdRegistro = @IdRegistro,
			@Data = @Data,
			@Vista = @Vista,
			@Tipo = @Tipo,
			@Id = @Id,
			@IdStatoFisico = @IdStatoFisico,
			@Etichette = @Etichette,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Numero] = c.Numero,
			[Data] = c.[Data],
			[Codice] = c.EerNome,
			[Stato fisico] = c.StatoFisico,
			[Etichette] = (SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(c.Etichette) WITH (Nome VARCHAR(50) '$.Nome') j),
			[Quantità] = c.Quantita,
			[Assegnata] = c.QuantitaAssegnata,
			[Residua] = c.QuantitaResidua,
			[Unità di misura] = um.Codice,
			[Giorni in giacenza] = c.GiacenzaGiorni
		FROM
			#righe c
			LEFT JOIN dbo.tblUnitaMisura um ON c.IdUnitaMisura = um.Id
		ORDER BY c.GiacenzaGiorni DESC, c.EerNome, c.Numero;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspRifiutiModelli_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modelli dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiModelli_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiModelli_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
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
			@IdFunzione = 'RMD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: registro corrente della sessione (tblSessioni.IdRegistro); senza registro nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = m.Nome,
			[Operazione] = o.Nome,
			[Codice EER] = e.Nome,
			[Descrizione EER] = e.Descrizione,
			[Pericoloso] = CASE e.Pericoloso WHEN 1 THEN 'Sì' WHEN 0 THEN 'No' END,
			[Stato fisico] = s.Nome,
			[Attività] = a.Codice,
			[Unità di misura] = um.Codice,
			[Materiale] = mt.Nome,
			[Etichette] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiModelliEtichette me INNER JOIN dbo.tblEtichette x ON me.IdEtichetta = x.Id WHERE me.Id = m.Id),
			[Note] = m.UtenteNote
		FROM
			dbo.tblRifiutiModelli m
			INNER JOIN dbo.tblSessioni ses ON m.IdRegistro = ses.IdRegistro
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			LEFT JOIN dbo.tblUnitaMisura um ON m.IdUnitaMisura = um.Id
			LEFT JOIN dbo.tblRifiutiMateriali mt ON m.IdMateriale = mt.Id
		WHERE
			ses.Id = @IdSessione
			AND m.Lock = 0
			AND (@Search IS NULL OR m.Nome LIKE '%' + @Search + '%')
		ORDER BY m.Nome
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspRifiutiAutorizzazioni_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Autorizzazioni dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiAutorizzazioni_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiAutorizzazioni_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Numero VARCHAR(50) = NULL,
	@Sede VARCHAR(50) = NULL,
	@IdRuolo CHAR(1) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Numero = dbo.ufnStringhe_get_SenzaSpazi(@Numero, 0, 1);
		SET @Sede = dbo.ufnStringhe_get_SenzaSpazi(@Sede, 0, 1);
		SET @IdRuolo = NULLIF(LTRIM(RTRIM(@IdRuolo)), '');
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
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		WITH tbl AS (
			-- Autorizzazioni interne: legate alla sessione tramite IdAziendaInterna
			SELECT
				a.Id,
				Stato = CASE
					WHEN a.DataFine < GETDATE() THEN 'Autorizzazione scaduta'
					WHEN a.Disabilitata = 1 THEN 'Autorizzazione disabilitata'
					WHEN s.Disabilitata = 1 THEN 'Sede disabilitata'
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 'Autorizzazione in scadenza'
					ELSE 'OK'
				END,
				Sede = s.NomeCompleto + ' - ' + s.IndirizzoCompleto
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND a.Nessuna = 0
				AND a.Lock = 0
				AND (@Numero IS NULL OR a.Numero LIKE '%' + @Numero + '%')
				AND (@Sede IS NULL OR s.NomeCompleto + ' - ' + s.IndirizzoCompleto LIKE '%' + @Sede + '%')
				AND (@IdRuolo IS NULL OR a.IdRuolo = @IdRuolo)
			UNION ALL

			-- Autorizzazioni esterne: legate alla sessione tramite aziende esterne condivise
			SELECT
				a.Id,
				Stato = CASE
					WHEN a.DataFine < GETDATE() THEN 'Autorizzazione scaduta'
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 'Autorizzazione in scadenza'
					ELSE 'OK'
				END,
				Sede = s.NomeCompleto + ' - ' + s.IndirizzoCompleto
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblRifiutiAutorizzazioni a ON s.Id = a.IdSede
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				CROSS APPLY (
					SELECT TOP 1 x.Id
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdAziendaInterna <> e.IdAzienda
				) c
			WHERE
				a.Disabilitata = 0
				AND a.Nessuna = 0
				AND s.Disabilitata = 0
				AND a.Lock = 0
				AND (@Numero IS NULL OR a.Numero LIKE '%' + @Numero + '%')
				AND (@Sede IS NULL OR s.NomeCompleto + ' - ' + s.IndirizzoCompleto LIKE '%' + @Sede + '%')
				AND (@IdRuolo IS NULL OR a.IdRuolo = @IdRuolo)
		)
		SELECT TOP (@MaxRighe + 1)
			[Sede] = tbl.Sede,
			[Codice fiscale] = s.CodiceFiscale,
			[Ruolo] = r.Nome,
			[Tipo] = t.Nome,
			[Tipo numero] = nt.Nome,
			[Numero] = a.Numero,
			[Identificativo] = a.Identificativo,
			[Dal] = a.DataInizio,
			[Al] = a.DataFine,
			[Stato] = tbl.Stato,
			[Note] = a.Note
		FROM
			tbl
			INNER JOIN dbo.tblRifiutiAutorizzazioni a ON tbl.Id = a.Id
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniTipi t ON a.IdTipo = t.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniNumeriTipi nt ON a.IdNumeroTipo = nt.Id
		ORDER BY tbl.Sede, a.DataFine DESC
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspRifiutiRegistri_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registri dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiRegistri_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistri_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: sede corrente della sessione (tblSessioni.IdSede); senza sede nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = r.Nome,
			[Tipo] = t.Nome,
			[Collegato a RENTRI] = IIF(z.Id IS NULL, 'No', 'Sì'),
			[Controllo scadenze autorizzazioni] = IIF(r.ControlloScadenzeAutorizzazioni = 1, 'Sì', 'No'),
			[Controllo targhe] = IIF(r.ControlloTarghe = 1, 'Sì', 'No'),
			[Controllo conducenti] = IIF(r.ControlloConducenti = 1, 'Sì', 'No'),
			[Controllo patenti] = IIF(r.ControlloPatenti = 1, 'Sì', 'No'),
			[Controllo attività R/S] = IIF(r.ControlloAttivitaRs = 1, 'Sì', 'No')
		FROM
			dbo.tblRifiutiRegistri r
			INNER JOIN dbo.tblRifiutiRegistriTipi t ON r.IdTipo = t.Id
			INNER JOIN dbo.tblSessioni e ON r.IdSede = e.IdSede
			LEFT JOIN dbo.tblRentriRegistri z ON r.Id = z.Id
		WHERE
			e.Id = @IdSessione
			AND r.Lock = 0
			AND (@Search IS NULL OR r.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Nome
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspRifiutiLimiti_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Limiti dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiLimiti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiLimiti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: sede corrente della sessione (tblSessioni.IdSede); senza sede nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Registro] = ISNULL(r.Nome, 'Tutti i registri'),
			[Riferimento] = IIF(c.Riferimento = 'G', 'Giacenza', 'Operazioni'),
			[Intervallo] = CASE c.Intervallo WHEN 'GG' THEN 'Giornaliero' WHEN 'WK' THEN 'Settimanale' WHEN 'MM' THEN 'Mensile' WHEN 'YY' THEN 'Annuale' ELSE c.Intervallo END,
			[Limite] = c.Valore,
			[Unità di misura] = c.IdUnitaMisura,
			[Codici EER] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiLimitiEer le INNER JOIN dbo.tblRifiutiEer x ON le.IdEer = x.Id WHERE le.IdLimite = c.Id),
			[Operazioni] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Pos) FROM dbo.tblRifiutiLimitiOperazioni lo INNER JOIN dbo.tblRifiutiOperazioni x ON lo.IdOperazione = x.Id WHERE lo.IdLimite = c.Id),
			[Etichette] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiLimitiEtichette lt INNER JOIN dbo.tblEtichette x ON lt.IdEtichetta = x.Id WHERE lt.IdLimite = c.Id)
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdSede
			LEFT JOIN dbo.tblRifiutiRegistri r ON c.IdRegistro = r.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND (@Search IS NULL OR c.Nome LIKE '%' + @Search + '%')
		ORDER BY c.Nome
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspRifiutiMud_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dichiarazioni MUD: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiMud_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiMud_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Anno] = c.Anno,
			[Unità locale] = su.Nome + ' ' + su.IndirizzoCompleto,
			[Data] = c.Data,
			[Dichiarazione generata il] = c.DataGenerazione,
			[Registri] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiMudRegistri mr INNER JOIN dbo.tblRifiutiRegistri x ON mr.IdRegistro = x.Id WHERE mr.Id = c.Id)
		FROM
			dbo.tblRifiutiMud c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			LEFT JOIN dbo.tblSedi su ON c.IdSedeUnitaLocale = su.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR su.Nome LIKE '%' + @Search + '%'
				OR CAST(c.Anno AS VARCHAR(10)) LIKE '%' + @Search + '%'
				)
		ORDER BY c.Anno DESC, su.Nome
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspEtichette_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Etichette di un modulo: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspEtichette_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEtichette_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(NULLIF(LTRIM(RTRIM(@Search)), ''), 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF dbo.ufnModuli_get_IsAttivoBySessione(@IdModulo, @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ETC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: sede corrente della sessione (tblSessioni.IdSede); senza sede nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = a.Nome,
			[Descrizione] = a.Descrizione,
			[Colore] = c.Nome
		FROM
			dbo.tblEtichette a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdSede
			LEFT JOIN dbo.tblColori c ON a.IdColore = c.Id
		WHERE
			e.Id = @IdSessione
			AND a.IdModulo = @IdModulo
			AND a.Lock = 0
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%')
		ORDER BY a.Nome
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO
