/*
Deploy produzione 2026-10-16 - Scadenziario: incasso (o pagamento) al netto delle note di credito

Indipendente dagli altri script. Rieseguibile. Eseguire con sqlcmd -f 65001 -I (oppure da SSMS).
Eseguire PRIMA di pubblicare l'app (commit 1221435 del repo app): con l'app vecchia le SP nuove funzionano
come prima.

1. uspPagamenti_ins: nel pagamento su più rate ammesse insieme rate di fatture e di note di credito dello stesso
   cliente o fornitore. Un solo movimento nel verso della parte più grande; la parte più piccola si chiude per
   intero, sulla più grande si distribuiscono in ordine di scadenza la parte più piccola più l'importo pagato.
   Ammessi l'acconto e l'importo zero (sola compensazione, solo con rate miste). Regola F8.6b di
   docs/regole/fatturazione.md (repo app).
2. uspFattureRate_get_Scadenzario_List: restituisce anche IdClienteFornitore, per il controllo nella pagina.
*/

-- ===== uspPagamenti_ins
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registra un pagamento sulle rate selezionate nello scadenziario (@IdRate: Id separati da ;) dei clienti
-- (@Tipo = C, incasso) o dei fornitori (@Tipo = F, pagamento). Un pagamento può coprire più rate, anche di
-- fatture diverse: l'importo si distribuisce sulle rate in ordine di scadenza, fino al residuo di ciascuna.
-- Ammesso il pagamento parziale, non un importo superiore al residuo complessivo. Le rate delle note di
-- credito pagate da sole hanno il verso opposto (uscita verso un cliente, entrata da un fornitore).
-- Rate di fatture e di note di credito insieme (solo dello stesso cliente o fornitore) = pagamento al netto:
-- la parte più piccola si chiude per intero, sulla più grande si distribuiscono la parte più piccola più
-- l'importo pagato, che non supera il netto e può essere zero (sola compensazione); il verso è quello della
-- parte più grande. Si registra anche su una fattura in sola lettura: il pagamento non
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
		IF @Importo IS NULL OR @Importo < 0
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
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Quota DECIMAL(18, 2) NOT NULL DEFAULT 0
		);
		INSERT @rate (Id, DataScadenza, Residuo, NotaCredito, IdClienteFornitore)
		SELECT
			r.Id,
			ISNULL(r.DataScadenza, '99991231'),
			ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato,
			IIF(f.IdTipo = 'TD04', 1, 0),
			f.IdClienteFornitore
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
		-- Fatture e note di credito insieme: pagamento al netto, solo verso lo stesso cliente o fornitore
		DECLARE @mista BIT = IIF((SELECT COUNT(DISTINCT NotaCredito) FROM @rate) > 1, 1, 0);
		IF @mista = 1 AND (SELECT COUNT(DISTINCT ISNULL(IdClienteFornitore, '')) FROM @rate) > 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le rate delle fatture e delle note di credito si pagano insieme solo se sono dello stesso ' + IIF(@Tipo = 'C', 'cliente', 'fornitore');
			GOTO BRANCH_END;
		END
		-- Importo zero solo per la compensazione tra fatture e note di credito
		IF @Importo = 0 AND @mista = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo del pagamento deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Parte più grande (fatture o note di credito): su di essa si distribuiscono la parte più piccola, che si
		-- chiude per intero, più l'importo pagato; senza note di credito (o senza fatture) la parte più piccola è zero
		DECLARE @fatture DECIMAL(18, 2) = (SELECT ISNULL(SUM(Residuo), 0) FROM @rate WHERE NotaCredito = 0);
		DECLARE @noteCredito DECIMAL(18, 2) = (SELECT ISNULL(SUM(Residuo), 0) FROM @rate WHERE NotaCredito = 1);
		DECLARE @grandeNotaCredito BIT = IIF(@noteCredito > @fatture, 1, 0);
		DECLARE @piccola DECIMAL(18, 2) = IIF(@grandeNotaCredito = 1, @fatture, @noteCredito);
		DECLARE @netto DECIMAL(18, 2) = ABS(@fatture - @noteCredito);
		IF @Importo > @netto
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo supera ' + IIF(@mista = 1, 'il netto', 'il residuo') + ' delle rate selezionate (' + FORMAT(@netto, 'N2', 'it-IT') + ')';
			GOTO BRANCH_END;
		END

		-- Verso del movimento, quello della parte più grande: entrata per l'incasso da un cliente e per la
		-- restituzione da un fornitore (nota di credito ricevuta), uscita negli altri casi
		DECLARE @verso CHAR(1) = IIF((@Tipo = 'C' AND @grandeNotaCredito = 0) OR (@Tipo = 'F' AND @grandeNotaCredito = 1), 'E', 'U');

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

			SET @fatture = (SELECT ISNULL(SUM(Residuo), 0) FROM @rate WHERE NotaCredito = 0);
			SET @noteCredito = (SELECT ISNULL(SUM(Residuo), 0) FROM @rate WHERE NotaCredito = 1);
			SET @piccola = IIF(@grandeNotaCredito = 1, @fatture, @noteCredito);

			IF EXISTS (SELECT 1 FROM @rate WHERE Residuo <= 0)
				OR @grandeNotaCredito <> IIF(@noteCredito > @fatture, 1, 0)
				OR @Importo > ABS(@fatture - @noteCredito)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Le rate selezionate sono state pagate o modificate nel frattempo: aggiornare l''elenco e riprovare';
				GOTO BRANCH_END;
			END

			-- La parte più piccola si chiude per intero; sulla più grande si distribuiscono, in ordine di scadenza,
			-- la parte più piccola più l'importo pagato: ogni rata prende fino al suo residuo
			DECLARE @distribuito DECIMAL(18, 2) = @piccola + @Importo;
			UPDATE t
			SET Quota = CASE
				WHEN t.NotaCredito <> @grandeNotaCredito THEN t.Residuo
				WHEN c.Prima + t.Residuo <= @distribuito THEN t.Residuo
				WHEN c.Prima < @distribuito THEN @distribuito - c.Prima
				ELSE 0
			END
			FROM
				@rate t
				CROSS APPLY
					(
						SELECT Prima = ISNULL(SUM(p.Residuo), 0)
						FROM @rate p
						WHERE
							p.NotaCredito = t.NotaCredito
							AND
								(
								p.DataScadenza < t.DataScadenza
								OR (p.DataScadenza = t.DataScadenza AND p.Id < t.Id)
								)
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

-- ===== uspFattureRate_get_Scadenzario_List
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
		-- Pagato = quote dei pagamenti attivi attribuite alla rata.
		-- Il residuo serve al filtro per stato, quindi va calcolato per tutte le rate dell'azienda: lo si fa
		-- con le sole colonne che servono a filtro e ordinamento (quelle degli indici delle fatture e delle
		-- rate); il resto della riga (tipo, modalità, banca) si legge solo per le rate della pagina
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
				s.NomeCompleto
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
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
		),
		pagina AS (
			SELECT
				t.Id,
				t.IdFattura,
				t.DataScadenza,
				t.Importo,
				t.Abbuono,
				t.Pagato,
				t.Residuo,
				t.Numero,
				t.NomeCompleto,
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
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataEmissione,
			f.IdTipo,
			TipoNome = p.Nome,
			f.IdModalita,
			f.IdBancaCassa,
			f.IdClienteFornitore,
			t.NomeCompleto,
			NotaCredito = CAST(IIF(f.IdTipo = 'TD04', 1, 0) AS BIT),
			SolaLettura = ISNULL(f.SolaLettura, 0),
			Importo = CAST(t.Importo AS DECIMAL(18, 2)),
			Abbuono = CAST(t.Abbuono AS DECIMAL(18, 2)),
			Pagato = CAST(t.Pagato AS DECIMAL(18, 2)),
			Residuo = CAST(t.Residuo AS DECIMAL(18, 2)),
			t.RowsCount
		FROM
			pagina t
			INNER JOIN dbo.tblFatture f ON t.IdFattura = f.Id
			LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
		ORDER BY
			t.DataScadenza,
			t.NomeCompleto,
			t.Numero,
			t.Id
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

