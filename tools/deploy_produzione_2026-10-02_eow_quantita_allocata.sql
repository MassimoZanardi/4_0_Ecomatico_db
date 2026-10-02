/*
Deploy produzione 2026-10-02 - EoW: "quantità attribuita" diventa "quantità allocata"

Rinomina la colonna restituita QuantitaAttribuita -> QuantitaAllocata (uspEoWLotti_get,
uspEoWLotti_get_List, uspEoWLotti_get_RegistrazioniList, uspEoWGiacenze_get_List,
uspEoWGiacenze_get_Carichi_List), le variabili interne e i testi visibili all'utente
(messaggio di uspEoWLotti_upd, descrizione dello stato in uspEoWLotti_get_List).

ATTENZIONE: va deployato insieme all'app (proprietà C# QuantitaAllocata). Con l'app vecchia
le quantità allocate EoW risulterebbero 0.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_esegui
	@IdRegistrazione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL OR @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non è un movimento reale: non riceve quote EoW
		IF EXISTS (SELECT 1
		FROM dbo.viewRifiutiRegistrazioniEffettive
		WHERE
			Id = @IdRegistrazione
			AND IsRettifica = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può ricevere quote EoW';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @idAllocazioneTipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@idAllocazioneTipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock = 0;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeAllocazione <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''allocazione selezionata non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'M'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo tipo di allocazione non supporta l''esecuzione automatica';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock di tutti i lotti coinvolti in un unico statement (ordine di acquisizione stabile,
			-- via index seek sulla PK, per ridurre il rischio di deadlock con esecuzioni concorrenti
			-- su insiemi di lotti sovrapposti), poi del movimento - stesso ordine di
			-- uspEoWLottiRifiutiRegistrazioni_ins.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = l.Id
			FROM dbo.tblEoWLotti l WITH (UPDLOCK, HOLDLOCK)
			WHERE l.Id IN (SELECT IdLotto FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
			ORDER BY l.Id;

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Righe di configurazione + quantità già allocata ad ognuno dei lotti coinvolti, lette
			-- sotto lock (fonte unica di verità, nessun ricalcolo su dati stimati prima del lock)
			DECLARE @righe TABLE (IdLotto CHAR(16) PRIMARY KEY, Valore DECIMAL(18, 2) NULL, QuantitaMax DECIMAL(18, 2) NULL, QuantitaAllocata DECIMAL(18, 2) NOT NULL);
			INSERT INTO @righe (IdLotto, Valore, QuantitaMax, QuantitaAllocata)
			SELECT
				la.IdLotto,
				la.Valore,
				l.QuantitaMax,
				QuantitaAllocata = ISNULL((SELECT SUM(r.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni r INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = la.IdLotto
					AND rr.Lock < 2
				), 0)
			FROM
				dbo.tblEoWLottiAllocazioni la
				INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id;

			IF NOT EXISTS (SELECT 1
			FROM @righe)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''allocazione non ha lotti configurati';
				GOTO BRANCH_END;
			END

			-- Lotti non utilizzabili: chiusi (data di chiusura impostata), disabilitati o eliminati,
			-- come per l'attribuzione manuale (uspEoWLottiRifiutiRegistrazioni_ins). Con il tipo C
			-- (priorità/capacità) vengono saltati come i lotti pieni e si passa al successivo; con
			-- U e P (lotto unico / percentuale) non c'è un lotto successivo: errore bloccante.
			DECLARE @lottoNonUtilizzabile VARCHAR(50) = (
				SELECT TOP 1 l.Nome
				FROM
					@righe r
					INNER JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
				WHERE
					l.Lock <> 0
					OR l.DataChiusura IS NOT NULL
					OR ISNULL(l.Disabilitato, 0) = 1
				ORDER BY l.Nome
			);
			IF @lottoNonUtilizzabile IS NOT NULL AND @idAllocazioneTipo IN ('U', 'P')
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Il lotto ' + @lottoNonUtilizzabile + ' dell''allocazione è chiuso o disabilitato';
				GOTO BRANCH_END;
			END
			IF @lottoNonUtilizzabile IS NOT NULL
			BEGIN
				DELETE r
				FROM
					@righe r
					INNER JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
				WHERE
					l.Lock <> 0
					OR l.DataChiusura IS NOT NULL
					OR ISNULL(l.Disabilitato, 0) = 1;

				IF NOT EXISTS (SELECT 1
				FROM @righe)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Tutti i lotti dell''allocazione sono chiusi o disabilitati';
					GOTO BRANCH_END;
				END
			END

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione), 0);
			DECLARE @quantitaDaAllocare DECIMAL(18, 2) = ISNULL(@quantitaMovimento, 0) - @quantitaAllocataRegistrazione;

			IF @quantitaDaAllocare <= 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non c''è quantità residua da allocare per questa registrazione';
				GOTO BRANCH_END;
			END

			-- Piano di ripartizione calcolato per tipo (U = Lotto unico, P = Percentuale, C = Priorità/Capacità)
			DECLARE @piano TABLE (IdLotto CHAR(16) PRIMARY KEY, Quantita DECIMAL(18, 2) NOT NULL);

			IF @idAllocazioneTipo = 'U'
			BEGIN
				IF (SELECT COUNT(*)
				FROM @righe) <> 1
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''allocazione di tipo Lotto unico deve avere esattamente un lotto configurato';
					GOTO BRANCH_END;
				END

				INSERT INTO @piano (IdLotto, Quantita)
				SELECT IdLotto, @quantitaDaAllocare
				FROM @righe;
			END
			ELSE IF @idAllocazioneTipo = 'P'
			BEGIN
				DECLARE @sommaPercentuali DECIMAL(18, 2) = (SELECT SUM(ISNULL(Valore, 0))
				FROM @righe);
				IF @sommaPercentuali > 100
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Le percentuali configurate non possono superare 100';
					GOTO BRANCH_END;
				END

				-- Arrotondamento a 2 decimali per riga. Il resto viene pareggiato sull'ultimo lotto (per
				-- Id) solo se le percentuali configurate coprono l'intero 100%: in quel caso il resto è
				-- puro errore di arrotondamento da correggere. Se invece sommano a meno di 100 (allocazione
				-- volutamente parziale, es. un solo lotto al 60%), il resto è quantità non allocata per
				-- scelta e deve restare tale, non va scaricato sull'ultimo lotto.
				INSERT INTO @piano (IdLotto, Quantita)
				SELECT
					IdLotto,
					Quantita = ROUND(@quantitaDaAllocare * Valore / 100.0, 2)
				FROM @righe;

				IF @sommaPercentuali = 100
				BEGIN
					DECLARE @idUltimoLotto CHAR(16) = (SELECT TOP 1 IdLotto
					FROM @righe ORDER BY IdLotto DESC);
					DECLARE @resto DECIMAL(18, 2) = @quantitaDaAllocare - (SELECT SUM(Quantita)
					FROM @piano);
					UPDATE @piano
					SET Quantita = Quantita + @resto
					WHERE IdLotto = @idUltimoLotto;
				END
			END
			ELSE IF @idAllocazioneTipo = 'C'
			BEGIN
				-- Ripartizione greedy per priorità (Valore crescente = priorità più alta): iterazione
				-- riga per riga, nessun pattern set-based equivalente per un bin-packing sequenziale.
				DECLARE @rimanente DECIMAL(18, 2) = @quantitaDaAllocare;
				DECLARE @curIdLotto CHAR(16), @curQuantitaMax DECIMAL(18, 2), @curQuantitaAllocata DECIMAL(18, 2);

				DECLARE curRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT IdLotto, QuantitaMax, QuantitaAllocata
					FROM @righe
					ORDER BY ISNULL(Valore, 999999999), IdLotto;

				OPEN curRighe;
				FETCH NEXT
				FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAllocata;
				WHILE @@FETCH_STATUS = 0 AND @rimanente > 0
				BEGIN
					DECLARE @capacitaResidua DECIMAL(18, 2) = CASE
						WHEN @curQuantitaMax IS NULL THEN @rimanente
						ELSE @curQuantitaMax - @curQuantitaAllocata
					END;
					IF @capacitaResidua > 0
					BEGIN
						DECLARE @presoQui DECIMAL(18, 2) = IIF(@capacitaResidua < @rimanente, @capacitaResidua, @rimanente);
						INSERT INTO @piano (IdLotto, Quantita) VALUES (@curIdLotto, @presoQui);
						SET @rimanente -= @presoQui;
					END
					FETCH NEXT
					FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAllocata;
				END
				CLOSE curRighe;
				DEALLOCATE curRighe;

				IF @rimanente > 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'La capacità configurata nei lotti è insufficiente per la quantità da allocare';
					GOTO BRANCH_END;
				END
			END

			-- Verifica finale capacità per riga (ridondante per U/P dove già implicito, ma protegge
			-- comunque da una configurazione QuantitaMax incoerente) e upsert nella tabella risultato
			IF EXISTS (
				SELECT 1
				FROM @piano p INNER JOIN @righe r ON p.IdLotto = r.IdLotto
				WHERE
					r.QuantitaMax IS NOT NULL
					AND r.QuantitaAllocata + p.Quantita > r.QuantitaMax
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità calcolata supera la capacità residua di uno o più lotti';
				GOTO BRANCH_END;
			END

			-- Pos = ordine di riempimento e IdAllocazioneTipo = metodo: quando la quantita' operativa della M scende,
			-- uspEoWLottiRifiutiRegistrazioni_upd_Allinea riduce partendo dall'ultima allocazione fatta rispettando
			-- il metodo (P in proporzione, C/U dall'ultimo lotto riempito). I lotti di questa esecuzione seguono
			-- quelli gia' allocati, nell'ordine di configurazione (Valore crescente = per il tipo C la priorita'
			-- con cui sono stati riempiti). Un lotto gia' allocato prende metodo e Pos di questa esecuzione
			-- (l'ultima operazione).
			DECLARE @posMax INT = ISNULL((SELECT MAX(Pos)
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE IdRegistrazione = @IdRegistrazione), 0);

			MERGE dbo.tblEoWLottiRifiutiRegistrazioni AS target
			USING (
				SELECT
					p.IdLotto,
					p.Quantita,
					Pos = @posMax + ROW_NUMBER() OVER (ORDER BY ISNULL(r.Valore, 999999999), p.IdLotto)
				FROM
					@piano p
					INNER JOIN @righe r ON p.IdLotto = r.IdLotto
			) AS source
				ON target.IdRegistrazione = @IdRegistrazione AND target.IdLotto = source.IdLotto
			WHEN MATCHED THEN
				UPDATE SET
					Quantita = target.Quantita + source.Quantita,
					Pos = source.Pos,
					IdAllocazioneTipo = @idAllocazioneTipo
			WHEN NOT MATCHED THEN
				INSERT (IdRegistrazione, IdLotto, Quantita, Pos, IdAllocazioneTipo)
				VALUES (@IdRegistrazione, source.IdLotto, source.Quantita, source.Pos, @idAllocazioneTipo);

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Carichi_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza @Id: tutti i carichi EoW delle sedi interne della sessione (filtrati per
		-- la sede del contesto della sessione, se impostata); con @Id: i carichi del lotto (@Vista = L)
		-- o del magazzino EoW (@Vista = M) indicato
		IF @Id IS NOT NULL AND ISNULL(@Vista, '') NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = tutte le sedi interne
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Titolarità sul Lotto/Magazzino indicato
		IF @Id IS NOT NULL AND @Vista = 'L' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND @Vista = 'M' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini g INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione AS Id,
			-- Registro della registrazione: la sede interna può averne più di uno
			RegistroNome = g.Nome,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			LottoNome = l.Nome,
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAllocata = lr.Quantita,
			-- Residuo attuale del lotto EoW della quota (gli scarichi di magazzino prelevano dal
			-- lotto, non dalla singola registrazione): quote di registrazioni attive meno gli
			-- scarichi dei movimenti di magazzino confermati
			ResiduoLotto = ISNULL(pl.Prodotta, 0) - ISNULL(sl.Scaricata, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
			OUTER APPLY (
				SELECT Prodotta = SUM(qp.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni qp
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON qp.IdRegistrazione = rp.Id
				WHERE
					qp.IdLotto = l.Id
					AND rp.Lock < 2
			) pl
			OUTER APPLY (
				SELECT Scaricata = SUM(rs.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rs
					INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
					INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
				WHERE
					rs.IdLotto = l.Id
					AND rg.Lock = 0
					AND ms.Lock = 0
			) sl
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			r.Lock < 2
			AND (
				(@Id IS NULL AND (@idSede IS NULL OR l.IdSede = @idSede))
				OR (@Vista = 'L' AND l.Id = @Id)
				OR (@Vista = 'M' AND l.IdMagazzino = @Id)
			)
			AND (@Search IS NULL OR r.Numero = TRY_CAST(@Search AS INT) OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Data DESC, r.Numero DESC
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Giacenza (coerente con Rifiuti/Giacenze): Quantita = quanto c'è oggi nel lotto, cioè le
		-- quote di registrazioni M attive (Lock < 2: una registrazione eliminata mantiene le sue
		-- quote per un eventuale ripristino, ma non conta più) meno gli scarichi dei movimenti di
		-- magazzino confermati; solo le righe con giacenza diversa da 0: una giacenza negativa è
		-- l'anomalia "Scaricato più del prodotto" (il magazzino EoW deriva dal registro operativo e
		-- prevale sul magazzino tradizionale, non viene mai corretto in automatico). GiacenzaGiorni = giorni dalla
		-- prima registrazione M del lotto. La capacità residua resta riferita alla produzione
		-- (QuantitaMax - quantità allocata): il lotto EoW è una partita di produzione, gli
		-- scarichi non liberano capienza.
		IF @Vista = 'L'
		BEGIN
			SELECT
				l.Id,
				-- 2 = anomalia (scaricato più del prodotto), 1 = lotto pieno (la produzione allocata ha
				-- raggiunto la quantità massima), 0 = OK
				StatoValore = CASE
					WHEN ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) < 0 THEN 2
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAllocata, 0) >= l.QuantitaMax THEN 1
					ELSE 0
				END,
				StatoDescrizione = CASE
					WHEN ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) < 0
						THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(ISNULL(q.QuantitaAllocata, 0), 'N2', 'it-IT') + ' kg, scaricati '
							+ FORMAT(ISNULL(sc.Scaricata, 0), 'N2', 'it-IT') + ' kg dal magazzino'
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAllocata, 0) >= l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
					ELSE 'OK'
				END,
				l.Nome,
				MaterialeNome = m.Nome,
				l.QuantitaMax,
				QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
				Quantita = ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWLotti l
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
				LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				OUTER APPLY (
					SELECT
						QuantitaAllocata = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLottiRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						r.IdLotto = l.Id
						AND rr.Lock < 2
				) q
						OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblMagazziniMovimentiRigheEoWLotti rs
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						rs.IdLotto = l.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
						) sc
			WHERE
				l.Lock = 0
				AND l.IdSede = @idSede
				AND
					(
					@Search IS NULL
					OR l.Nome LIKE '%' + @Search + '%'
					)
				AND ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) <> 0
			ORDER BY l.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END
		ELSE
		BEGIN
			SELECT
				g.Id,
				-- 2 = almeno un lotto del magazzino in anomalia (nella somma un lotto negativo resterebbe
				-- nascosto dagli altri)
				StatoValore = IIF(ISNULL(an.LottiAnomali, 0) > 0, 2, 0),
				StatoDescrizione = IIF(ISNULL(an.LottiAnomali, 0) > 0,
					'Scaricato più del prodotto in ' + CAST(an.LottiAnomali AS VARCHAR(10)) + IIF(an.LottiAnomali = 1, ' lotto', ' lotti'),
					'OK'),
				g.Nome,
				MaterialeNome = CAST(NULL AS VARCHAR(100)),
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
				Quantita = ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWMagazzini g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				OUTER APPLY (
					SELECT
						QuantitaAllocata = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni r ON r.IdLotto = l.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rr.Lock < 2
				) q
						OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoWLotti rs ON rs.IdLotto = l.Id
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
						) sc
						OUTER APPLY (
					SELECT LottiAnomali = COUNT(*)
					FROM
						dbo.tblEoWLotti l
						CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) sl
					WHERE
						l.IdMagazzino = g.Id
						AND l.Lock = 0
						AND sl.Giacenza < 0
						) an
			WHERE
				g.Lock = 0
				AND g.IdSede = @idSede
				AND
					(
					@Search IS NULL
					OR g.Nome LIKE '%' + @Search + '%'
					)
				AND
					(
					ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) <> 0
					OR ISNULL(an.LottiAnomali, 0) > 0
					)
			ORDER BY g.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
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
END;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_ins
	@IdRegistrazione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M, cioè
		-- tblRifiutiOperazioni.IsMateriale = 1 - vedi feedback_rentri_codice_lookup_pattern,
		-- mai confrontare IdOperazione con un letterale hardcoded)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non ha un materiale prodotto valorizzato';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non è un movimento reale: non riceve quote EoW
		IF EXISTS (SELECT 1
		FROM dbo.viewRifiutiRegistrazioniEffettive
		WHERE
			Id = @IdRegistrazione
			AND IsRettifica = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può ricevere quote EoW';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		DECLARE @dataChiusuraLotto DATE;
		DECLARE @disabilitatoLotto BIT;
		DECLARE @quantitaMaxLotto DECIMAL(18, 2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale,
			@dataChiusuraLotto = l.DataChiusura,
			@disabilitatoLotto = l.Disabilitato,
			@quantitaMaxLotto = l.QuantitaMax
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeLotto <> @idMaterialeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale della registrazione';
			GOTO BRANCH_END;
		END

		IF @dataChiusuraLotto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è chiuso, non può ricevere nuove quantità';
			GOTO BRANCH_END;
		END

		IF ISNULL(@disabilitatoLotto, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è disabilitato, non può ricevere nuove quantità';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock in ordine stabile (sempre Lotto, poi Movimento) per evitare deadlock con
			-- esecuzioni concorrenti che toccano insiemi di lotti/registrazioni sovrapposti.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = Id
			FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @IdLotto;

			DECLARE @quantitaAllocataLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAllocataLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la capacità residua del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione);
			IF ISNULL(@quantitaAllocataRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND IdLotto = @IdLotto
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Questo lotto è già associato alla registrazione: modificare la quantità esistente';
				GOTO BRANCH_END;
			END

			-- Pos = ordine di riempimento: se la quantita' operativa della M scende, le allocazioni si riducono
			-- partendo dall'ultimo lotto riempito (uspEoWLottiRifiutiRegistrazioni_upd_Allinea)
			INSERT dbo.tblEoWLottiRifiutiRegistrazioni (IdRegistrazione, IdLotto, Quantita, Pos)
			SELECT
				@IdRegistrazione,
				@IdLotto,
				@Quantita,
				ISNULL(MAX(Pos), 0) + 1
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE IdRegistrazione = @IdRegistrazione;

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_upd
	@IdRegistrazione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla registrazione (deve restare causale M, coerenza con l'insert)
		DECLARE @idMovimento CHAR(16);
		SELECT @idMovimento = m.Id
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul lotto
		DECLARE @quantitaMaxLotto DECIMAL(18, 2);
		SELECT @quantitaMaxLotto = l.QuantitaMax
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE l.Id = @IdLotto;

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLottiRifiutiRegistrazioni
		WHERE
			IdRegistrazione = @IdRegistrazione
			AND IdLotto = @IdLotto
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Associazione non trovata';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock in ordine stabile (sempre Lotto, poi Movimento), stesso ordine di _ins
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = Id
			FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @IdLotto;

			DECLARE @quantitaAllocataLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
					AND q.IdRegistrazione <> @IdRegistrazione
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAllocataLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la capacità residua del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE
					IdRegistrazione = @IdRegistrazione
					AND IdLotto <> @IdLotto
			);
			IF ISNULL(@quantitaAllocataRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			-- Quantita' decisa a mano: l'allocazione diventa manuale (IdAllocazioneTipo NULL), una riduzione
			-- automatica successiva non la tratta piu' come parte di un'allocazione in percentuale/priorita'
			UPDATE dbo.tblEoWLottiRifiutiRegistrazioni
			SET
				Quantita = @Quantita,
				IdAllocazioneTipo = NULL
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND IdLotto = @IdLotto;

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLotti
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			l.Id,
			l.IdSede,
			SedeNome = s.Nome,
			l.IdMagazzino,
			MagazzinoNome = g.Nome,
			l.IdMateriale,
			MaterialeNome = m.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			l.Lock
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT QuantitaAllocata = SUM(r.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
		WHERE
			l.Id = @Id
			AND l.Lock <= 2;

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
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@DataAperturaDa DATE = NULL,
	@DataAperturaA DATE = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMagazzino = NULLIF(LTRIM(RTRIM(@IdMagazzino)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			l.Id,
			-- Stato: prima l'anomalia "Scaricato più del prodotto" (il magazzino tradizionale ha scaricato
			-- più di quanto il registro operativo alloca al lotto: il magazzino EoW prevale e non viene
			-- mai corretto in automatico), poi la capacità (solo con quantità massima impostata; il lotto EoW
			-- è una partita di produzione, gli scarichi non liberano capienza): 2 = anomalia o capacità
			-- superata, 1 = lotto pieno o capacità residua sotto il 30% della quantità massima, 0 = OK
			StatoValore = CASE
				WHEN s.Giacenza < 0 THEN 2
				WHEN l.QuantitaMax IS NULL THEN 0
				WHEN c.QuantitaAllocata > l.QuantitaMax THEN 2
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN s.Giacenza < 0
					THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(s.Prodotta, 'N2', 'it-IT') + ' kg, scaricati '
						+ FORMAT(s.Scaricata, 'N2', 'it-IT') + ' kg dal magazzino'
				WHEN l.QuantitaMax IS NULL THEN 'OK'
				WHEN c.QuantitaAllocata > l.QuantitaMax
					THEN 'Capacità superata di ' + FORMAT(c.QuantitaAllocata - l.QuantitaMax, 'N2', 'it-IT') + ' kg: allocati '
						+ FORMAT(c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su ' + FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				WHEN c.QuantitaAllocata = l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3
					THEN 'Capacità residua sotto il 30%: ' + FORMAT(l.QuantitaMax - c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su '
						+ FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				ELSE 'OK'
			END,
			NumeroRegistrazioni = ISNULL(q.NumeroRegistrazioni, 0),
			l.Nome,
			MaterialeNome = m.Nome,
			MagazzinoNome = g.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT
					QuantitaAllocata = SUM(r.Quantita),
					NumeroRegistrazioni = COUNT(DISTINCT r.IdRegistrazione)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
					CROSS APPLY (SELECT QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0)) c
					CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) s
		WHERE
			l.Lock = 0
			AND l.IdSede = @idSede
			AND
				(
				@IdMagazzino IS NULL
				OR l.IdMagazzino = @IdMagazzino
				)
			AND
				(
				@IdMateriale IS NULL
				OR l.IdMateriale = @IdMateriale
				)
			AND
				(
				@Aperto IS NULL
				OR
					(
					@Aperto = 1
					AND l.DataChiusura IS NULL
					)
				OR
					(
					@Aperto = 0
					AND l.DataChiusura IS NOT NULL
					)
				)
			AND
				(
				@Disabilitato IS NULL
				OR ISNULL(l.Disabilitato, 0) = @Disabilitato
				)
			AND
				(
				@DataAperturaDa IS NULL
				OR l.DataApertura >= @DataAperturaDa
				)
			AND
				(
				@DataAperturaA IS NULL
				OR l.DataApertura <= @DataAperturaA
				)
			AND
				(
				@Search IS NULL
				OR l.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY l.Nome
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_RegistrazioniList
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
			@IdFunzione = 'EOW',
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
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAllocata = lr.Quantita
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			lr.IdLotto = @Id
			AND r.Lock < 2
		ORDER BY r.Data DESC, r.Numero DESC;

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
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@DataApertura DATE = NULL,
	@DataChiusura DATE = NULL,
	@QuantitaMax DECIMAL(18, 2) = NULL,
	@Disabilitato BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMagazzino = NULLIF(LTRIM(RTRIM(@IdMagazzino)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Disabilitato = ISNULL(@Disabilitato, 0);

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
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMateriale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataApertura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataApertura non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataChiusura IS NOT NULL AND @DataChiusura < @DataApertura
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di chiusura non può essere precedente alla data di apertura';
			GOTO BRANCH_END;
		END
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del lotto
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWLotti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale deve esistere in anagrafica (tblRifiutiMateriali, nessuna anagrafica EoW parallela)
		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Il magazzino, se indicato, deve appartenere alla stessa sede del lotto
		IF @IdMagazzino IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				Id = @IdMagazzino
				AND IdSede = @idSede
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il magazzino selezionato non appartiene alla sede del lotto';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il materiale se il lotto ha già registrazioni M associate
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdMateriale <> @IdMateriale
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdLotto = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il materiale di un lotto con registrazioni associate';
			GOTO BRANCH_END;
		END

		-- La quantità massima non può scendere sotto la produzione già allocata al lotto (quote
		-- di registrazioni M attive): il lotto EoW è una partita di produzione. Aumentarla è
		-- sempre possibile (riapre capienza, se il lotto non è chiuso).
		DECLARE @quantitaAllocata DECIMAL(18, 2) = ISNULL((
			SELECT SUM(q.Quantita)
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
			WHERE
				q.IdLotto = @Id
				AND rr.Lock < 2
		), 0);
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax < @quantitaAllocata
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima non può essere inferiore alla quantità già allocata al lotto (' + FORMAT(@quantitaAllocata, 'N2', 'it-IT') + ')';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro lotto attivo con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro lotto con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWLotti
			SET
				Lock = 0,
				IdMagazzino = @IdMagazzino,
				IdMateriale = @IdMateriale,
				Nome = @Nome,
				DataApertura = @DataApertura,
				DataChiusura = @DataChiusura,
				QuantitaMax = @QuantitaMax,
				Disabilitato = @Disabilitato
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Lotto non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_get_LottiSelectList
	@IdSede CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMateriale non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Lotti EoW da cui scaricare (criterio Manuale): stessa Sede+Materiale, attivi, non
		-- disabilitati, con disponibilità (anche se scaduti). Disponibilità = quantità
		-- prodotta (quote di registrazioni M attive allocate al lotto, modulo EoW) -
		-- scarichi confermati di questo modulo Magazzino
		SELECT
			l.Id,
			[Text] = l.Nome + ' (disp. ' + FORMAT(ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0), 'N2', 'it-IT') + ')',
			Selected = CAST(IIF(l.Id = @IdSelected, 1, 0) AS BIT)
		FROM
			dbo.tblEoWLotti l
			OUTER APPLY (
				SELECT Prodotta = SUM(q.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni q
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = l.Id
					AND rr.Lock < 2
			) p
			OUTER APPLY (
				SELECT Scaricata = SUM(rl.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rl
					INNER JOIN dbo.tblMagazziniMovimentiRigheEoW r ON rl.Id = r.Id
					INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
				WHERE
					rl.IdLotto = l.Id
					AND r.Lock = 0
					AND mv.Lock = 0
			) sc
		WHERE
			l.IdSede = @IdSede
			AND l.IdMateriale = @IdMateriale
			AND l.Lock = 0
			AND ISNULL(l.Disabilitato, 0) = 0
			AND ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0) > 0
			AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY l.Nome
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

