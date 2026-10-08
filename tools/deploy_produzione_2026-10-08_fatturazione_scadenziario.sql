/*
Deploy produzione 2026-10-08 - Fatturazione > Scadenziario clienti e fornitori (pagamenti delle rate)

Da eseguire DOPO deploy_produzione_2026-10-07_fatturazione_fatture.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

1. Pagine e voci di menu Scadenziario clienti e Scadenziario fornitori (funzione FTT, la stessa delle
   fatture), tra Fatture fornitori e Conti. Nessuna tabella nuova: tblPagamenti e
   tblFattureRatePagamenti sono create dallo script delle fatture.
2. uspFattureRate_get_Scadenzario_List: rate delle fatture attive con pagato e residuo.
3. uspPagamenti_ins, uspPagamenti_del, uspPagamenti_get_List: registrazione di un pagamento su una o
   piu' rate, annullamento, pagamenti di una rata.
4. uspFattureRate_upd: l'importo di una rata non scende sotto quanto gia' pagato.

Va deployato insieme all'app: le pagine Fatturazione > Scadenziario clienti e Scadenziario fornitori usano
le nuove SP.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'Pagine e menu dello scadenziario';
GO
-- Fatturazione > Scadenziario clienti e fornitori: pagine e voci di menu (funzione FTT, la stessa delle
-- fatture). Le tabelle dei pagamenti (tblPagamenti, tblFattureRatePagamenti) sono già create da
-- fatturazione_fatture.sql.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTS')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTS', 'FTT', 'Scadenziario clienti', 'scadenziario-clienti', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTP')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTP', 'FTT', 'Scadenziario fornitori', 'scadenziario-fornitori', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti, Scadenziario fornitori, Conti,
-- Banche e casse, Aliquote IVA
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ6')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ6', 'AJ0', NULL, 'FTS', 2);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ7')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ7', 'AJ0', NULL, 'FTP', 3);

UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AJ5' AND Pos <> 4;
UPDATE dbo.tblMenu SET Pos = 5 WHERE Id = 'AJ1' AND Pos <> 5;
UPDATE dbo.tblMenu SET Pos = 6 WHERE Id = 'AJ2' AND Pos <> 6;
GO

PRINT 'uspFattureRate_get_Scadenzario_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scadenziario: le rate delle fatture attive dei clienti (@Tipo = C) o dei fornitori (@Tipo = F) dell'azienda
-- del contesto, dalla scadenza più vecchia. Le pre-fatture (TD00) non entrano. @Stato: A aperte (da pagare
-- e scadute, predefinito), S scadute, D da pagare non scadute, P saldate, T tutte.
-- Residuo = importo - abbuono - pagato. La rata di una nota di credito (NotaCredito = 1) è un importo da
-- restituire.
-- SolaLettura = fattura in sola lettura: la rata non si modifica, i pagamenti si registrano comunque.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_Scadenzario_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@Stato CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');
		SET @Stato = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@Stato)), '')), 'A');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END
		IF @Stato NOT IN ('A', 'S', 'D', 'P', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Stato deve essere A, S, D, P o T';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga.
		-- @Numero cerca nel numero della fattura e, per i fornitori, nel numero del loro documento.
		-- Pagato = quote dei pagamenti attivi attribuite alla rata
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		WITH rate AS (
			SELECT
				r.Id,
				r.IdFattura,
				r.DataScadenza,
				Importo = ISNULL(r.Importo, 0),
				Abbuono = ISNULL(r.Abbuono, 0),
				x.Pagato,
				Residuo = IIF(ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato > 0, ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato, 0),
				f.Numero,
				f.Sezionale,
				f.NumeroFornitore,
				f.DataEmissione,
				f.IdTipo,
				TipoNome = p.Nome,
				f.IdModalita,
				f.IdBancaCassa,
				s.NomeCompleto,
				NotaCredito = CAST(IIF(f.IdTipo = 'TD04', 1, 0) AS BIT),
				SolaLettura = ISNULL(f.SolaLettura, 0)
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				CROSS APPLY
					(
						SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
						FROM
							dbo.tblFattureRatePagamenti rp
							INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
						WHERE
							rp.IdRata = r.Id
							AND g.Lock = 0
					) x
			WHERE
				e.Id = @IdSessione
				AND f.Tipo = @Tipo
				AND f.Lock = 0
				AND ISNULL(f.IdTipo, '') <> 'TD00'
				AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
				AND
					(
					@Numero IS NULL
					OR CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '') LIKE @Numero + '%'
					OR f.NumeroFornitore LIKE '%' + @Numero + '%'
					)
				AND (@DataDa IS NULL OR r.DataScadenza >= @DataDa)
				AND (@DataA IS NULL OR r.DataScadenza <= @DataA)
		)
		SELECT
			t.Id,
			t.IdFattura,
			StatoValore = CASE
				WHEN t.Residuo = 0 THEN 0
				WHEN t.DataScadenza < @oggi THEN 2
				ELSE 1
			END,
			StatoDescrizione = CASE
				WHEN t.Residuo = 0 THEN 'Saldata'
				WHEN t.DataScadenza < @oggi THEN 'Scaduta'
				ELSE 'Da pagare'
			END,
			t.DataScadenza,
			t.Numero,
			t.Sezionale,
			t.NumeroFornitore,
			t.DataEmissione,
			t.IdTipo,
			t.TipoNome,
			t.IdModalita,
			t.IdBancaCassa,
			t.NomeCompleto,
			t.NotaCredito,
			t.SolaLettura,
			Importo = CAST(t.Importo AS DECIMAL(18, 2)),
			Abbuono = CAST(t.Abbuono AS DECIMAL(18, 2)),
			Pagato = CAST(t.Pagato AS DECIMAL(18, 2)),
			Residuo = CAST(t.Residuo AS DECIMAL(18, 2)),
			RowsCount = COUNT(*) OVER ()
		FROM rate t
		WHERE
			@Stato = 'T'
			OR (@Stato = 'A' AND t.Residuo > 0)
			OR (@Stato = 'S' AND t.Residuo > 0 AND t.DataScadenza < @oggi)
			OR (@Stato = 'D' AND t.Residuo > 0 AND t.DataScadenza >= @oggi)
			OR (@Stato = 'P' AND t.Residuo = 0)
		ORDER BY
			t.DataScadenza,
			t.NomeCompleto,
			t.Numero,
			t.Id
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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

PRINT 'uspPagamenti_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registra un pagamento sulle rate selezionate nello scadenziario (@IdRate: Id separati da ;) dei clienti
-- (@Tipo = C, incasso) o dei fornitori (@Tipo = F, pagamento). Un pagamento può coprire più rate, anche di
-- fatture diverse: l'importo si distribuisce sulle rate in ordine di scadenza, fino al residuo di ciascuna.
-- Ammesso il pagamento parziale, non un importo superiore al residuo complessivo. Le rate delle note di
-- credito si pagano da sole (nessuna compensazione): il movimento ha il verso opposto (uscita verso un
-- cliente, entrata da un fornitore). Si registra anche su una fattura in sola lettura: il pagamento non
-- modifica il documento. @DataContabile è la data del movimento, @DataRegistrazione quella in cui lo si registra
-- (oggi se non indicata).
-- Restituisce l'Id del pagamento.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_ins
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@IdRate VARCHAR(MAX) = NULL,
	@DataRegistrazione DATE = NULL,
	@DataContabile DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdModalita CHAR(4) = NULL,
	@Causale VARCHAR(150) = NULL,
	@Importo DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @returnId CHAR(16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdRate = NULLIF(LTRIM(RTRIM(@IdRate)), '');
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @DataRegistrazione = ISNULL(@DataRegistrazione, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il pagamento è dell'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END
		IF @IdRate IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare almeno una rata';
			GOTO BRANCH_END;
		END
		IF @DataContabile IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data contabile del pagamento';
			GOTO BRANCH_END;
		END
		IF @IdBancaCassa IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la banca o la cassa';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE Id = @IdBancaCassa AND IdSede = @idAzienda AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdModalita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la modalità di pagamento';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		-- La causale è la descrizione del movimento in prima nota: sempre richiesta
		IF @Causale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la causale del pagamento';
			GOTO BRANCH_END;
		END
		IF LEN(@Causale) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale non può superare i 100 caratteri';
			GOTO BRANCH_END;
		END
		IF @Importo IS NULL OR @Importo <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo del pagamento deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Rate richieste: devono essere di fatture attive (non pre-fatture) dell'azienda e del tipo indicato
		DECLARE @richieste TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		INSERT @richieste (Id)
		SELECT DISTINCT LTRIM(RTRIM(v.value))
		FROM STRING_SPLIT(@IdRate, ';') v
		WHERE LTRIM(RTRIM(v.value)) <> '';

		DECLARE @rate TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			DataScadenza DATE NOT NULL,
			Residuo DECIMAL(18, 2) NOT NULL,
			NotaCredito BIT NOT NULL,
			Quota DECIMAL(18, 2) NOT NULL DEFAULT 0
		);
		INSERT @rate (Id, DataScadenza, Residuo, NotaCredito)
		SELECT
			r.Id,
			ISNULL(r.DataScadenza, '99991231'),
			ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato,
			IIF(f.IdTipo = 'TD04', 1, 0)
		FROM
			@richieste q
			INNER JOIN dbo.tblFattureRate r ON q.Id = r.Id
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			CROSS APPLY
				(
					SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
					FROM
						dbo.tblFattureRatePagamenti rp
						INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
					WHERE
						rp.IdRata = r.Id
						AND g.Lock = 0
				) x
		WHERE
			f.IdSede = @idAzienda
			AND f.Tipo = @Tipo
			AND f.Lock = 0
			AND ISNULL(f.IdTipo, '') <> 'TD00';

		IF (SELECT COUNT(*) FROM @rate) = 0 OR (SELECT COUNT(*) FROM @rate) <> (SELECT COUNT(*) FROM @richieste)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o una delle rate selezionate non esiste';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1 FROM @rate WHERE Residuo <= 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una delle rate selezionate è già saldata';
			GOTO BRANCH_END;
		END
		IF (SELECT COUNT(DISTINCT NotaCredito) FROM @rate) > 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le rate delle note di credito si pagano separatamente da quelle delle fatture';
			GOTO BRANCH_END;
		END

		DECLARE @residuo DECIMAL(18, 2) = (SELECT SUM(Residuo) FROM @rate);
		IF @Importo > @residuo
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo supera il residuo delle rate selezionate (' + FORMAT(@residuo, 'N2', 'it-IT') + ')';
			GOTO BRANCH_END;
		END

		-- Verso del movimento: entrata per l'incasso da un cliente e per la restituzione da un fornitore
		-- (nota di credito ricevuta), uscita negli altri casi
		DECLARE @notaCredito BIT = (SELECT MAX(CAST(NotaCredito AS INT)) FROM @rate);
		DECLARE @verso CHAR(1) = IIF((@Tipo = 'C' AND @notaCredito = 0) OR (@Tipo = 'F' AND @notaCredito = 1), 'E', 'U');

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			-- Residui riletti con il blocco sulle rate: un altro pagamento registrato nel frattempo non
			-- deve portare la rata oltre il suo importo
			UPDATE t
			SET Residuo = ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato
			FROM
				@rate t
				INNER JOIN dbo.tblFattureRate r WITH (UPDLOCK, HOLDLOCK) ON t.Id = r.Id
				CROSS APPLY
					(
						SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
						FROM
							dbo.tblFattureRatePagamenti rp
							INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
						WHERE
							rp.IdRata = r.Id
							AND g.Lock = 0
					) x;

			IF EXISTS (SELECT 1 FROM @rate WHERE Residuo <= 0) OR @Importo > (SELECT SUM(Residuo) FROM @rate)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Le rate selezionate sono state pagate o modificate nel frattempo: aggiornare l''elenco e riprovare';
				GOTO BRANCH_END;
			END

			-- Distribuzione in ordine di scadenza: ogni rata prende fino al suo residuo
			UPDATE t
			SET Quota = CASE
				WHEN c.Prima + t.Residuo <= @Importo THEN t.Residuo
				WHEN c.Prima < @Importo THEN @Importo - c.Prima
				ELSE 0
			END
			FROM
				@rate t
				CROSS APPLY
					(
						SELECT Prima = ISNULL(SUM(p.Residuo), 0)
						FROM @rate p
						WHERE
							p.DataScadenza < t.DataScadenza
							OR (p.DataScadenza = t.DataScadenza AND p.Id < t.Id)
					) c;

			INSERT dbo.tblPagamenti (Id, IdSede, IdBancaCassa, IdModalita, Tipo, Causale, DataRegistrazione, DataContabile, Importo, Lock)
			VALUES (@returnId, @idAzienda, @IdBancaCassa, @IdModalita, @verso, @Causale, @DataRegistrazione, @DataContabile, @Importo, 0);

			INSERT dbo.tblFattureRatePagamenti (IdRata, IdPagamento, Importo)
			SELECT Id, @returnId, Quota
			FROM @rate
			WHERE Quota > 0;
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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

PRINT 'uspPagamenti_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Annulla un pagamento registrato nello scadenziario: il pagamento resta in archivio come cancellato
-- (Lock = 4) e le sue quote sulle rate vengono tolte, così le rate tornano aperte per l'importo che
-- copriva. Si annulla anche su una fattura in sola lettura: il pagamento non modifica il documento.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_del
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il pagamento deve essere attivo e dell'azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblPagamenti p
				INNER JOIN dbo.tblSessioni e ON p.IdSede = e.IdAzienda
			WHERE
				p.Id = @Id
				AND e.Id = @IdSessione
				AND p.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il pagamento non esiste o è già stato annullato';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblPagamenti
			SET Lock = 4
			WHERE
				Id = @Id
				AND Lock = 0;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Pagamento non trovato o già annullato';
				GOTO BRANCH_END;
			END

			DELETE dbo.tblFattureRatePagamenti
			WHERE IdPagamento = @Id;
		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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

PRINT 'uspPagamenti_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pagamenti attivi di una rata, dal più vecchio: Quota è la parte del pagamento attribuita alla rata,
-- Importo l'intero pagamento, Rate il numero di rate che il pagamento copre.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_List
	@IdRata CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRata = NULLIF(LTRIM(RTRIM(@IdRata)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRata IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRata non può essere vuoto';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: rata di una fattura dell'azienda interna corrente della sessione
		SELECT
			p.Id,
			[Data] = p.DataContabile,
			p.DataRegistrazione,
			BancaCassaNome = b.Nome,
			ModalitaNome = m.Nome,
			p.Causale,
			Quota = CAST(rp.Importo AS DECIMAL(18, 2)),
			Importo = CAST(p.Importo AS DECIMAL(18, 2)),
			Rate = (SELECT COUNT(*) FROM dbo.tblFattureRatePagamenti q WHERE q.IdPagamento = p.Id)
		FROM
			dbo.tblFattureRatePagamenti rp
			INNER JOIN dbo.tblPagamenti p ON rp.IdPagamento = p.Id
			INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblBancheCasse b ON p.IdBancaCassa = b.Id
			LEFT JOIN dbo.tblPagamentiModalita m ON p.IdModalita = m.Id
		WHERE
			rp.IdRata = @IdRata
			AND e.Id = @IdSessione
			AND p.Lock = 0
		ORDER BY
			p.DataContabile,
			p.Id;

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

PRINT 'uspFattureRate_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva una rata (scadenza) della fattura: con @Id vuoto la aggiunge a @IdFattura, altrimenti la
-- modifica. Le rate si salvano subito, anche sulla fattura in bozza. Restituisce l'Id della rata.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_upd
	@Id CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@DataScadenza DATE = NULL,
	@Importo DECIMAL(18, 2) = NULL,
	@Abbuono DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Abbuono = ISNULL(@Abbuono, 0);

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Rata esistente: la fattura è quella della rata
		IF @Id IS NOT NULL
		BEGIN
			SET @IdFattura = NULL;
			SELECT @IdFattura = IdFattura
			FROM dbo.tblFattureRate
			WHERE Id = @Id;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @IdFattura
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		IF @DataScadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data di scadenza della rata';
			GOTO BRANCH_END;
		END
		IF @Importo IS NULL OR @Importo <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo della rata deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Abbuono < 0 OR @Abbuono > @Importo
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''abbuono deve essere compreso tra zero e l''importo della rata';
			GOTO BRANCH_END;
		END

		-- Rata con pagamenti: l'importo, tolto l'abbuono, non può scendere sotto quanto già pagato
		IF @Id IS NOT NULL
		BEGIN
			DECLARE @pagato DECIMAL(18, 2);
			SELECT @pagato = ISNULL(SUM(rp.Importo), 0)
			FROM
				dbo.tblFattureRatePagamenti rp
				INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
			WHERE
				rp.IdRata = @Id
				AND g.Lock = 0;

			IF @Importo - @Abbuono < @pagato
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo della rata, tolto l''abbuono, non può essere inferiore a quanto già pagato (' + FORMAT(@pagato, 'N2', 'it-IT') + ')';
				GOTO BRANCH_END;
			END
		END

		-- Nuova rata: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
				INSERT dbo.tblFattureRate (Id, IdFattura, Importo, Abbuono, DataScadenza)
				VALUES (@Id, @IdFattura, @Importo, @Abbuono, @DataScadenza);
			ELSE
				UPDATE dbo.tblFattureRate
				SET
					Importo = @Importo,
					Abbuono = @Abbuono,
					DataScadenza = @DataScadenza
				WHERE Id = @Id;
		COMMIT TRANSACTION;

		SELECT Id = @Id;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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

