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
