/*
Deploy produzione 2026-10-09 - Esportazione in Excel e CSV degli elenchi dei moduli Scadenze, Servizi e Rentri

Indipendente dagli altri script del 2026-10-09: usa solo tabelle e SP già in produzione (e il DB 1_0_rentri,
come le SP degli elenchi Rentri). Rieseguibile. Eseguire con sqlcmd -f 65001 -I.
Le etichette di Scadenze e Servizi usano uspEtichette_get_Esportazione, che è nello script
deploy_produzione_2026-10-09_rifiuti_esportazione.sql: va eseguito anche quello.

SP di esportazione, una per elenco: stesse righe e stesso ordine della SP dell'elenco, colonne con il nome
dell'intestazione, al massimo @MaxRighe + 1 righe.
1. uspScadenze_get_Esportazione: scadenze (chiama uspScadenze_get_List).
2. uspServizi_get_Esportazione: servizi (chiama uspServizi_get_List).
3. uspServiziAssegnati_get_Esportazione: servizi assegnati (chiama uspServiziAssegnati_get_List).
4. uspCalendari_get_Esportazione: calendari di un modulo.
5. uspTipi_get_Esportazione: tipi di un modulo.
6. uspRentriRegistri_get_Esportazione: registri RENTRI (chiama uspRentriRegistri_get_List).
7. uspRentriSedi_get_Esportazione: sedi RENTRI (chiama uspRentriSedi_get_List).
8. uspRentriCredenziali_get_Esportazione: credenziali RENTRI, solo dati descrittivi.
9. uspRentriCertificati_get_Esportazione: certificati RENTRI, solo dati descrittivi.

Nessuna modifica alle tabelle né alle SP degli elenchi. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/


PRINT 'uspScadenze_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scadenze: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspScadenze_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspScadenze_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: a parità di data vale l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IdSerie CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NULL,
			Ricorre BIT NULL,
			Eccezione BIT NULL,
			Tipo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, IdSerie, Descrizione, IdEvento, [Data], Ricorre, Eccezione, Tipo, Etichette, RowsCount)
		EXEC dbo.uspScadenze_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@Stato = @Stato,
			@Etichetta = @Etichetta,
			@Search = @Search;

		SELECT
			[Data] = [Data],
			[Tipo] = Tipo,
			[Descrizione] = Descrizione,
			[Stato] = StatoDescrizione,
			[Ricorrente] = IIF(Ricorre = 1, 'Sì', 'No'),
			[Etichette] =(SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(IIF(ISJSON(Etichette) = 1, Etichette, NULL)) WITH (Nome VARCHAR(50) '$.Nome') j)
		FROM #righe
		ORDER BY [Data], Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspServizi_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Servizi: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspServizi_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspServizi_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: a parità di data vale l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IdSerie CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Tipo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			Richiedente VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NULL,
			Ricorre BIT NULL,
			Eccezione BIT NULL,
			Etichette VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, IdSerie, Tipo, Descrizione, Richiedente, IdEvento, [Data], Ricorre, Eccezione, Etichette, RowsCount)
		EXEC dbo.uspServizi_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@Stato = @Stato,
			@Etichetta = @Etichetta,
			@Search = @Search;

		SELECT
			[Data] = [Data],
			[Tipo] = Tipo,
			[Descrizione] = Descrizione,
			[Richiedente] = Richiedente,
			[Stato] = StatoDescrizione,
			[Ricorrente] = IIF(Ricorre = 1, 'Sì', 'No'),
			[Etichette] =(SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(IIF(ISJSON(Etichette) = 1, Etichette, NULL)) WITH (Nome VARCHAR(50) '$.Nome') j)
		FROM #righe
		ORDER BY [Data], Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspServiziAssegnati_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Servizi assegnati: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspServiziAssegnati_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspServiziAssegnati_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: a parità di data vale l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Tipo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			Richiedente VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, IdEvento, [Data], StatoValore, StatoDescrizione, Tipo, Descrizione, Richiedente, Etichette, RowsCount)
		EXEC dbo.uspServiziAssegnati_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@Stato = @Stato,
			@Search = @Search;

		SELECT
			[Data] = [Data],
			[Servizio] = Tipo,
			[Richiedente] = Richiedente,
			[Descrizione] = Descrizione,
			[Stato] = StatoDescrizione,
			[Etichette] =(SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(IIF(ISJSON(Etichette) = 1, Etichette, NULL)) WITH (Nome VARCHAR(50) '$.Nome') j)
		FROM #righe
		ORDER BY [Data], Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspCalendari_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Calendari di un modulo: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspCalendari_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspCalendari_get_Esportazione
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
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
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
			@IdFunzione = 'CLD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: sede corrente della sessione (tblSessioni.IdSede); senza sede nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = a.Nome,
			[Descrizione] = a.Descrizione
		FROM
			dbo.tblCalendari a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdSede
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

PRINT 'uspTipi_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Tipi di un modulo: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspTipi_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspTipi_get_Esportazione
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
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = t.Nome,
			[Descrizione] = t.Descrizione
		FROM
			dbo.tblTipi t
			INNER JOIN dbo.tblSessioni e ON t.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND t.IdModulo = @IdModulo
			AND t.Lock = 0
			AND (@Search IS NULL OR t.Nome LIKE '%' + @Search + '%')
		ORDER BY t.Nome
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

PRINT 'uspRentriRegistri_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registri RENTRI: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspRentriRegistri_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRentriRegistri_get_Esportazione
	@IdSessione CHAR(16) = NULL,
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
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			SedeNome VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IndirizzoCompleto VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Identificativo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			BloccoFormulari VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			CredenzialePrimariaNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			AccreditamentoNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			IsCollegato BIT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, Nome, SedeNome, IndirizzoCompleto, Identificativo, BloccoFormulari, CredenzialePrimariaNome, AccreditamentoNome, IsCollegato, RowsCount)
		EXEC dbo.uspRentriRegistri_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Registro] = Nome,
			[Sede] = SedeNome,
			[Indirizzo] = IndirizzoCompleto,
			[Identificativo] = Identificativo,
			[Blocco formulari] = BloccoFormulari,
			[Credenziale primaria] = CredenzialePrimariaNome,
			[Accreditamento] = AccreditamentoNome,
			[Collegato a RENTRI] = IIF(IsCollegato = 1, 'Sì', 'No'),
			[Stato] = StatoDescrizione
		FROM #righe
		ORDER BY Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspRentriSedi_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sedi RENTRI: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspRentriSedi_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRentriSedi_get_Esportazione
	@IdSessione CHAR(16) = NULL,
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
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IndirizzoCompleto VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Identificativo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			CredenzialePrimariaNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			AccreditamentoNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			CredenzialiCount INT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, Nome, IndirizzoCompleto, Identificativo, CredenzialePrimariaNome, AccreditamentoNome, CredenzialiCount, RowsCount)
		EXEC dbo.uspRentriSedi_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Sede] = Nome,
			[Indirizzo] = IndirizzoCompleto,
			[Nr. iscrizione] = Identificativo,
			[Credenziale primaria] = CredenzialePrimariaNome,
			[Accreditamento] = AccreditamentoNome,
			[Credenziali associate] = CredenzialiCount,
			[Stato] = StatoDescrizione
		FROM #righe
		ORDER BY Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspRentriCredenziali_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali RENTRI (solo dati descrittivi, mai chiavi o segreti): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRentriCredenziali_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRentriCredenziali_get_Esportazione
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Nr. iscrizione] = h.Identificativo,
			[Certificato] = f.Nome,
			[Scadenza del certificato] = f.DataScadenza,
			[Accreditamento] = a.Nome,
			[Stato] = CASE
				WHEN f.DataScadenza < GETDATE() THEN 'Certificato scaduto'
				WHEN DATEDIFF(DAY, GETDATE(), f.DataScadenza) < 30 THEN 'Certificato in scadenza'
				ELSE 'OK'
			END
		FROM
			dbo.tblRentriCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN dbo.tblRentriCertificati f ON c.IdCertificato = f.Id
			LEFT JOIN dbo.tblRentriAccreditamenti a ON c.IdAccreditamento = a.Id
			LEFT JOIN [1_0_rentri]..tblCredenziali h ON c.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
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

PRINT 'uspRentriCertificati_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Certificati RENTRI (solo dati descrittivi, mai il contenuto del certificato): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRentriCertificati_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRentriCertificati_get_Esportazione
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Codice fiscale] = f.Identificativo,
			[Scadenza] = c.DataScadenza,
			[Stato] = CASE
				WHEN c.DataScadenza < GETDATE() THEN 'Certificato scaduto'
				WHEN DATEDIFF(DAY, GETDATE(), c.DataScadenza) < 30 THEN 'Certificato in scadenza'
				ELSE 'OK'
			END
		FROM
			dbo.tblRentriCertificati c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN [1_0_rentri]..tblCertificati f ON c.IdRentri COLLATE DATABASE_DEFAULT = f.Id COLLATE DATABASE_DEFAULT
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
