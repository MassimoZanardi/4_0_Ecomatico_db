-- Deploy produzione 2026-09-30, tranche 3 Magazzino/EoW: magazzino EoW allineato al registro operativo
-- (struttura + 2 funzioni + 14 stored procedure): repo DB da deployed-prod 98c1b51 a d8e4f01.
-- Gerarchia Registro > Magazzino EoW > Magazzino tradizionale:
-- - tblEoWLottiRifiutiRegistrazioni: nuove colonne Pos (ordine di riempimento) e IdAllocazioneTipo (metodo, NULL = manuale)
-- - le allocazioni EoW di una M seguono automaticamente la quantita' operativa (modifica, correzione, annullamento,
--   cancellazione di una rettifica, formulario): riduzione nel rispetto del metodo (percentuale in proporzione,
--   priorita'/lotto unico/manuale dall'ultimo lotto riempito), aumento = "da allocare", cambio materiale = rimosse
-- - anomalia "Scaricato piu' del prodotto" in Lotti, Giacenze EoW (giacenze negative visibili), righe EoW di magazzino
-- - anteprima per la modale "Magazzino EoW" dell'app (uspEoWLottiRifiutiRegistrazioni_get_Allineamento_List)
-- Richiede viewRifiutiRegistrazioniEffettive, ufnRifiutiRegistrazioni_get_RettificaOperativa, ufnModuli_get_IsAttivoBySessione
-- (gia' in produzione).
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -I -b -i <questo file>
-- Poi: tools\verifica_crlf_accenti.sql su tutto il DB (deve restituire 0 righe).
-- ============================================================ eow_allineamento_struttura
-- Magazzino EoW allineato al registro operativo (tranche 3): struttura.
-- Pos = ordine di riempimento delle allocazioni di una registrazione M (max+1 a ogni nuovo lotto):
-- quando la quantita' operativa della M scende, le allocazioni si riducono partendo dall'ultimo lotto
-- riempito (Pos piu' alta). Le righe gia' esistenti restano NULL (ordine di ripiego: DataApertura del lotto).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH('dbo.tblEoWLottiRifiutiRegistrazioni', 'Pos') IS NULL
	ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] ADD [Pos] [int] NULL;
GO

-- Metodo con cui e' nata l'allocazione (U = Lotto unico, P = Percentuale, C = Priorita'/capacita'; NULL = manuale):
-- la riduzione automatica rispetta il metodo (percentuale in proporzione, priorita' e manuale dall'ultimo lotto
-- riempito). Salvato il tipo e non l'allocazione configurata, che puo' essere cancellata fisicamente.
IF COL_LENGTH('dbo.tblEoWLottiRifiutiRegistrazioni', 'IdAllocazioneTipo') IS NULL
	ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] ADD [IdAllocazioneTipo] [char](1) COLLATE Latin1_General_CI_AS NULL;
GO

IF OBJECT_ID('dbo.FK_tblEoWLottiRifiutiRegistrazioni_tblEoWAllocazioniTipi', 'F') IS NULL
	ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblEoWAllocazioniTipi] FOREIGN KEY([IdAllocazioneTipo])
	REFERENCES [dbo].[tblEoWAllocazioniTipi] ([Id]);
GO

-- ============================================================ ufnEoWLotti_get_Saldo
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Saldo di un lotto EoW: Prodotta = allocazioni di registrazioni M attive (Lock < 2: una registrazione
-- cancellata mantiene le allocazioni per un eventuale ripristino ma non conta), Scaricata = righe EoW dei
-- movimenti di magazzino confermati (riga e movimento Lock = 0), Giacenza = Prodotta - Scaricata.
-- Il magazzino EoW deriva dal registro operativo e prevale sul magazzino tradizionale: una Giacenza negativa
-- non viene mai corretta in automatico, e' l'anomalia "Scaricato più del prodotto" da mostrare all'utente.
CREATE OR ALTER FUNCTION dbo.ufnEoWLotti_get_Saldo (
	@IdLotto CHAR(16)
)
RETURNS TABLE
AS
RETURN
SELECT
	p.Prodotta,
	s.Scaricata,
	Giacenza = p.Prodotta - s.Scaricata
FROM
	(
	SELECT Prodotta = ISNULL(SUM(q.Quantita), 0)
	FROM
		dbo.tblEoWLottiRifiutiRegistrazioni q
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON q.IdRegistrazione = r.Id
	WHERE
		q.IdLotto = @IdLotto
		AND r.Lock < 2
	) p
		CROSS JOIN (
	SELECT Scaricata = ISNULL(SUM(rl.Quantita), 0)
	FROM
		dbo.tblMagazziniMovimentiRigheEoWLotti rl
		INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rl.Id = rg.Id
		INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
	WHERE
		rl.IdLotto = @IdLotto
		AND rg.Lock = 0
		AND ms.Lock = 0
		) s;
GO

-- ============================================================ ufnEoWLottiRifiutiRegistrazioni_get_Allineamento
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Magazzino EoW allineato al registro operativo: per ogni allocazione della registrazione M
-- (@IdRegistrazione) calcola la quantita' allocata che resterebbe con la quantita' operativa @Quantita e il
-- materiale @IdMateriale. Unica regola, usata sia dall'allineamento
-- (uspEoWLottiRifiutiRegistrazioni_upd_Allinea) sia dall'anteprima della modale di conferma:
-- - lotto di materiale diverso da @IdMateriale (o @IdMateriale NULL: registrazione non piu' di materiale
--   prodotto) -> 0;
-- - se il totale allocato supera @Quantita la differenza si toglie rispettando il metodo con cui le
--   allocazioni sono nate (IdAllocazioneTipo), partendo dall'ultima allocazione fatta (Pos piu' alta):
--   percentuale (P) = tutte le allocazioni in percentuale come un blocco unico, ridotto in proporzione
--   (arrotondamento a 2 decimali, resto sull'ultimo lotto del blocco); priorita' (C), lotto unico (U) e
--   manuale (NULL) = lotto per lotto dall'ultimo riempito (per C la Pos segue la priorita', quindi si
--   svuota prima il lotto a priorita' piu' bassa). Righe senza Pos (pregresso) per ultime, poi lotto aperto
--   piu' di recente;
-- - se @Quantita e' maggiore o uguale al totale allocato le allocazioni restano invariate (la differenza e'
--   "da allocare").
-- QuantitaNuova = 0 significa che l'allocazione va rimossa.
CREATE OR ALTER FUNCTION dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento (
	@IdRegistrazione CHAR(16),
	@Quantita DECIMAL(18, 2),
	@IdMateriale CHAR(2)
)
RETURNS TABLE
AS
RETURN
WITH a AS (
	SELECT
		q.IdLotto,
		Quantita = ISNULL(q.Quantita, 0),
		IsCompatibile = CAST(IIF(@IdMateriale IS NOT NULL AND l.IdMateriale = @IdMateriale, 1, 0) AS BIT),
		IsPercentuale = CAST(IIF(q.IdAllocazioneTipo = 'P', 1, 0) AS BIT),
		-- Blocco di riduzione: le allocazioni in percentuale formano un unico blocco, le altre un blocco per lotto
		Blocco = IIF(q.IdAllocazioneTipo = 'P', CAST('P' AS CHAR(16)), q.IdLotto),
		Pos = ISNULL(q.Pos, 0),
		l.DataApertura
	FROM
		dbo.tblEoWLottiRifiutiRegistrazioni q
		INNER JOIN dbo.tblEoWLotti l ON q.IdLotto = l.Id
	WHERE q.IdRegistrazione = @IdRegistrazione),
e AS (
	-- Parte del totale compatibile che eccede la quantita' operativa
	SELECT Eccesso = ISNULL(SUM(Quantita), 0) - ISNULL(@Quantita, 0)
	FROM a
	WHERE IsCompatibile = 1),
b AS (
	SELECT
		Blocco,
		Totale = SUM(Quantita),
		Pos = MAX(Pos),
		DataApertura = MAX(DataApertura)
	FROM a
	WHERE IsCompatibile = 1
	GROUP BY Blocco
),
bc AS (
	-- Totale cumulato dall'ultimo blocco allocato (compreso quello della riga)
	SELECT
		b.Blocco,
		b.Totale,
		Cumulata = SUM(b.Totale) OVER (
			ORDER BY
				b.Pos DESC,
				b.DataApertura DESC,
				b.Blocco DESC
			ROWS UNBOUNDED PRECEDING)
	FROM b
),
br AS (
	-- Quantita' da togliere a ciascun blocco
	SELECT
		bc.Blocco,
		bc.Totale,
		Riduzione = CASE
			WHEN e.Eccesso <= 0 THEN CAST(0 AS DECIMAL(18, 2))
			WHEN e.Eccesso - (bc.Cumulata - bc.Totale) <= 0 THEN CAST(0 AS DECIMAL(18, 2))
			WHEN e.Eccesso - (bc.Cumulata - bc.Totale) >= bc.Totale THEN bc.Totale
			ELSE e.Eccesso - (bc.Cumulata - bc.Totale)
		END
	FROM
		bc
		CROSS JOIN e
),
r AS (
	SELECT
		a.IdLotto,
		a.Blocco,
		a.Quantita,
		a.IsCompatibile,
		Riduzione = ISNULL(br.Riduzione, 0),
		-- Blocco percentuale: quota proporzionale arrotondata a 2 decimali; negli altri blocchi (un solo lotto)
		-- tutta la riduzione del blocco
		RiduzioneRiga = CAST(IIF(a.IsPercentuale = 1 AND br.Totale > 0, ROUND(br.Riduzione * a.Quantita / br.Totale, 2), ISNULL(br.Riduzione, 0)) AS DECIMAL(18, 2)),
		IsUltimaDelBlocco = IIF(ROW_NUMBER() OVER (PARTITION BY a.Blocco ORDER BY a.Pos DESC, a.DataApertura DESC, a.IdLotto DESC) = 1, 1, 0)
	FROM
		a
		LEFT JOIN br ON a.Blocco = br.Blocco
),
rr AS (
	SELECT
		r.IdLotto,
		r.Quantita,
		r.IsCompatibile,
		r.Riduzione,
		-- Resto dell'arrotondamento del blocco sull'ultimo lotto del blocco (Pos piu' alta)
		RiduzioneFinale = r.RiduzioneRiga + IIF(r.IsUltimaDelBlocco = 1, r.Riduzione - SUM(r.RiduzioneRiga) OVER (PARTITION BY r.Blocco), 0)
	FROM r
	WHERE r.IsCompatibile = 1
	UNION ALL
	SELECT
		r.IdLotto,
		r.Quantita,
		r.IsCompatibile,
		r.Riduzione,
		RiduzioneFinale = r.Quantita
	FROM r
	WHERE r.IsCompatibile = 0)
SELECT
	rr.IdLotto,
	rr.Quantita,
	QuantitaNuova = CASE
		WHEN rr.IsCompatibile = 0 THEN CAST(0 AS DECIMAL(18, 2))
		WHEN rr.Riduzione = 0 THEN rr.Quantita
		WHEN rr.Quantita - rr.RiduzioneFinale < 0 THEN CAST(0 AS DECIMAL(18, 2))
		ELSE CAST(rr.Quantita - rr.RiduzioneFinale AS DECIMAL(18, 2))
	END
FROM rr;
GO

-- ============================================================ uspEoWLottiRifiutiRegistrazioni_upd_Allinea
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Magazzino EoW allineato al registro operativo (Registro > EoW > Magazzino): adegua le allocazioni EoW della
-- registrazione M @IdRegistrazione alla sua quantita' operativa (viewRifiutiRegistrazioniEffettive: ultima
-- rettifica confermata, 0 se annullata) e al suo materiale, con la regola di
-- ufnEoWLottiRifiutiRegistrazioni_get_Allineamento (riduzione dall'ultimo lotto riempito, lotti di materiale
-- diverso azzerati, nessun aumento automatico). Le allocazioni a 0 vengono rimosse.
-- SP interna, senza sessione: chiamata dentro la transazione delle SP che cambiano il valore operativo di una
-- registrazione (uspRifiutiRegistrazioni_upd, _upd_Rettifica, _upd_Annullamento, _del di una rettifica,
-- uspRifiutiFormulari_upd), che hanno gia' verificato permessi e titolarita'. Registrazioni non attive
-- (Lock >= 2: bozza o cancellata) non vengono toccate: una registrazione cancellata non conta nei lotti
-- (filtro Lock < 2 dei lettori) e mantiene le allocazioni per "Annulla cancellazione". Nessun controllo sul
-- materiale gia' scaricato dal magazzino: il registro prevale, l'eventuale anomalia resta visibile sul lotto.
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea
	@IdRegistrazione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Nessuna allocazione: niente da allineare (caso di gran lunga piu' frequente)
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLottiRifiutiRegistrazioni
		WHERE IdRegistrazione = @IdRegistrazione)
			GOTO BRANCH_END;

		DECLARE @isAttiva BIT = 0;
		DECLARE @idMateriale CHAR(2);
		DECLARE @quantita DECIMAL(18, 2);
		SELECT
			@isAttiva = 1,
			-- Materiale solo se la causale e' ancora di materiale prodotto (flag da LEFT JOIN: ISNULL)
			@idMateriale = IIF(ISNULL(o.IsMateriale, 0) = 1, r.IdMateriale, NULL),
			@quantita = ISNULL(v.Quantita, 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND v.IsRettifica = 0;

		IF @isAttiva = 0
			GOTO BRANCH_END;

		BEGIN TRANSACTION;

			DECLARE @allineamento TABLE (
				IdLotto CHAR(16) COLLATE DATABASE_DEFAULT PRIMARY KEY,
				Quantita DECIMAL(18, 2) NOT NULL,
				QuantitaNuova DECIMAL(18, 2) NOT NULL
			);

			-- Righe della registrazione bloccate fino alla fine della transazione del chiamante
			INSERT INTO @allineamento (IdLotto, Quantita, QuantitaNuova)
			SELECT
				n.IdLotto,
				n.Quantita,
				n.QuantitaNuova
			FROM
				dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento(@IdRegistrazione, @quantita, @idMateriale) n
				INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni q WITH (UPDLOCK, HOLDLOCK)
					ON q.IdRegistrazione = @IdRegistrazione
					AND q.IdLotto = n.IdLotto
			WHERE n.QuantitaNuova <> n.Quantita;

			DELETE q
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN @allineamento a ON q.IdLotto = a.IdLotto
			WHERE
				q.IdRegistrazione = @IdRegistrazione
				AND a.QuantitaNuova <= 0;

			UPDATE q
			SET q.Quantita = a.QuantitaNuova
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN @allineamento a ON q.IdLotto = a.IdLotto
			WHERE
				q.IdRegistrazione = @IdRegistrazione
				AND a.QuantitaNuova > 0;

		COMMIT TRANSACTION;

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

-- ============================================================ uspEoWLottiRifiutiRegistrazioni_ins
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

			DECLARE @quantitaAttribuitaLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAttribuitaLotto, 0) + @Quantita > @quantitaMaxLotto
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
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione);
			IF ISNULL(@quantitaAttribuitaRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
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

-- ============================================================ uspEoWLottiRifiutiRegistrazioni_upd
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

			DECLARE @quantitaAttribuitaLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
					AND q.IdRegistrazione <> @IdRegistrazione
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAttribuitaLotto, 0) + @Quantita > @quantitaMaxLotto
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
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE
					IdRegistrazione = @IdRegistrazione
					AND IdLotto <> @IdLotto
			);
			IF ISNULL(@quantitaAttribuitaRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
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

-- ============================================================ uspEoWAllocazioni_esegui
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

			-- Righe di configurazione + quantità già attribuita ad ognuno dei lotti coinvolti, lette
			-- sotto lock (fonte unica di verità, nessun ricalcolo su dati stimati prima del lock)
			DECLARE @righe TABLE (IdLotto CHAR(16) PRIMARY KEY, Valore DECIMAL(18, 2) NULL, QuantitaMax DECIMAL(18, 2) NULL, QuantitaAttribuita DECIMAL(18, 2) NOT NULL);
			INSERT INTO @righe (IdLotto, Valore, QuantitaMax, QuantitaAttribuita)
			SELECT
				la.IdLotto,
				la.Valore,
				l.QuantitaMax,
				QuantitaAttribuita = ISNULL((SELECT SUM(r.Quantita)
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
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione), 0);
			DECLARE @quantitaDaAllocare DECIMAL(18, 2) = ISNULL(@quantitaMovimento, 0) - @quantitaAttribuitaRegistrazione;

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
				DECLARE @curIdLotto CHAR(16), @curQuantitaMax DECIMAL(18, 2), @curQuantitaAttribuita DECIMAL(18, 2);

				DECLARE curRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT IdLotto, QuantitaMax, QuantitaAttribuita
					FROM @righe
					ORDER BY ISNULL(Valore, 999999999), IdLotto;

				OPEN curRighe;
				FETCH NEXT
				FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAttribuita;
				WHILE @@FETCH_STATUS = 0 AND @rimanente > 0
				BEGIN
					DECLARE @capacitaResidua DECIMAL(18, 2) = CASE
						WHEN @curQuantitaMax IS NULL THEN @rimanente
						ELSE @curQuantitaMax - @curQuantitaAttribuita
					END;
					IF @capacitaResidua > 0
					BEGIN
						DECLARE @presoQui DECIMAL(18, 2) = IIF(@capacitaResidua < @rimanente, @capacitaResidua, @rimanente);
						INSERT INTO @piano (IdLotto, Quantita) VALUES (@curIdLotto, @presoQui);
						SET @rimanente -= @presoQui;
					END
					FETCH NEXT
					FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAttribuita;
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
					AND r.QuantitaAttribuita + p.Quantita > r.QuantitaMax
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

-- ============================================================ uspRifiutiRegistrazioni_upd
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdDocumentoTrasportoTipo CHAR(1) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL,

	@IsVeicoloFuoriUso BIT = 0,
	@VeicoloFuoriUsoNumero VARCHAR(50) = NULL,
	@VeicoloFuoriUsoData DATE = NULL,

	@IdRaee CHAR(1) = NULL,

	-- Esito
	@IdEsito CHAR(1) = NULL,
	@QuantitaVerificata DECIMAL(18,2) = NULL,
	@DataFineTrasporto SMALLDATETIME = NULL,
	@IdCausaleRespingimento CHAR(1) = NULL,
	@CausaleRespingimentoAltro VARCHAR(100) = NULL,
	@IdUnitaMisuraQuantitaRespinta CHAR(2) = NULL,
	@QuantitaRespinta DECIMAL(18,2) = NULL,

	-- Materiale
	@IdMateriale CHAR(2) = NULL,
	@MaterialeDescrizione VARCHAR(200) = NULL,

	-- Provenienza
	@IdAttivitaProvenienza CHAR(1) = NULL,

	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0,
	@NessunaRegistrazioneAssociata BIT = 0
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del formulario a registrazioni già esistenti.
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);
		DECLARE @minData DATE = '19000101';
		DECLARE @maxData DATE = '20501231';

		-- Pre-calcolo range anno per confronti sargable
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@RegistrazioneData), 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(YEAR(@RegistrazioneData) + 1, 1, 1);

		DECLARE @idMovimento CHAR(16);
		DECLARE @idRegistro CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @lock TINYINT;
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @totaleQuantitaAssegnata DECIMAL(18,2);
		DECLARE @idRelazione CHAR(16);
		DECLARE @quantitaRelazione DECIMAL(18,2);
		DECLARE @quantitaResidua DECIMAL(18,2);
		DECLARE @isIntegrazioneFir BIT;
		DECLARE @isFormularioAssociato BIT;
		DECLARE @isEsito BIT;
		DECLARE @isMateriale BIT;
		DECLARE @isProduttore BIT;
		DECLARE @isTrasportatore BIT;
		DECLARE @isDestinatario BIT;
		DECLARE @isIntermediario BIT;
		DECLARE @isAttivitaRs BIT;
		DECLARE @isAttivitaProvenienza BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @conservazioneSostitutiva BIT;

		-- Recupero dati registrazione
		SELECT
			@idMovimento = r.IdMovimento,
			@idRegistro = m.IdRegistro,
			@idFormulario = f.Id,
			@lock = r.Lock,
			@operazione = r.Operazione,
			@idOperazione = m.IdOperazione,
			@rentriIdentificativo = r.RentriIdentificativo,
			@rentriData = r.RentriData,
			@conservazioneSostitutiva = r.ConservazioneSostitutiva,
			@isIntegrazioneFir = o.IsIntegrazioneFir,
			@isFormularioAssociato = CAST(IIF(f.IdMovimento IS NOT NULL AND f.Lock < 2, 1, 0) AS BIT),
			@isEsito = o.IsEsito,
			@isMateriale = o.IsMateriale,
			@isProduttore = o.IsProduttore,
			@isTrasportatore = o.IsTrasportatore,
			@isDestinatario = o.IsDestinatario,
			@isIntermediario = o.IsIntermediario,
			@isAttivitaRs = o.IsAttivitaRs,
			@isAttivitaProvenienza = o.IsAttivitaProvenienza,
			@totaleQuantitaAssegnata = CASE
				WHEN @NessunaRegistrazioneAssociata = 1 THEN 0
				ELSE
					ISNULL((
						SELECT SUM(lq.Quantita)
						FROM
							dbo.tblRifiutiRegistrazioniRelazioni lq
							INNER JOIN dbo.tblRifiutiRegistrazioni rq ON lq.Id = rq.Id
						WHERE
							lq.IdParent = r.Id
							AND lq.Quantita > 0
							AND rq.Lock < 2
					), 0)
				END
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
		WHERE r.Id = @Id;

		-- Verifica che la registrazione esista
		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @idRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione già trasmessa a RENTRI non può più essere modificata in alcun modo
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Una registrazione portata/bloccata per la conservazione sostitutiva non può più essere modificata
		IF ISNULL(@conservazioneSostitutiva, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Normalizza @isMateriale: NULL (nessuna corrispondenza in tblRifiutiOperazioni) equivale a "non materiale"
		SET @isMateriale = ISNULL(@isMateriale, 0);

		-- Normalizzazione parametri
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdAttivitaProvenienza = NULLIF(LTRIM(RTRIM(@IdAttivitaProvenienza)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdUnitaMisura = ISNULL(@IdUnitaMisura, 'KG');
		SET @IdDocumentoTrasportoTipo = NULLIF(LTRIM(RTRIM(@IdDocumentoTrasportoTipo)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');
		SET @IdEsito = NULLIF(LTRIM(RTRIM(@IdEsito)), '');
		SET @IdCausaleRespingimento = NULLIF(LTRIM(RTRIM(@IdCausaleRespingimento)), '');

		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @ClassiPericolo = dbo.ufnStringhe_get_SenzaSpazi(@ClassiPericolo, 0, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 0, 1);
		SET @RegistrazioneNote = dbo.ufnStringhe_get_SenzaSpazi(@RegistrazioneNote, 0, 1);
		SET @VeicoloFuoriUsoNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@VeicoloFuoriUsoNumero, 0, 1));
		SET @CausaleRespingimentoAltro = dbo.ufnStringhe_get_SenzaSpazi(@CausaleRespingimentoAltro, 0, 1);

		IF @NessunaRegistrazioneAssociata = 1 SET @RegistrazioneAuto = 0;

		IF @RegistrazioneAuto = 1 AND (EXISTS(
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND
					(
						(
						[Data] = @RegistrazioneData
						AND Numero = @RegistrazioneNumero
						)
					OR Lock = 2
					)
		))
			SET @RinumeraRegistro = 1;

		IF @QuantitaVerificata = @Quantita
			SET @QuantitaVerificata = NULL;

		-- EER / StatoFisico / ClassiPericolo esclusivi con Materiale; l'unità di misura per il
		-- Materiale è sempre KG, a prescindere da cosa arrivi dal client (campo disabilitato in UI).
		IF @isMateriale = 1
		BEGIN
			SET @IdEer = NULL;
			SET @IdProvenienza = NULL;
			SET @IdStatoFisico = NULL;
			SET @ClassiPericolo = NULL;
			SET @EerDescrizione = NULL;
			SET @IdUnitaMisura = 'KG';
			IF @IdMateriale = 'AL'
				SET @MaterialeDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@MaterialeDescrizione, 0, 1);
			ELSE
				SET @MaterialeDescrizione = NULL;
		END
		ELSE
		BEGIN
			SET @IdMateriale = NULL;
			SET @MaterialeDescrizione = NULL;

			IF @IdEer LIKE '%99'
				SET @EerDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@EerDescrizione, 0, 1);
			ELSE
				SET @EerDescrizione = NULL;
		END

		-- Data inizio trasporto solo se integrazione FIR
		IF @isIntegrazioneFir = 0
			SET @DataInizioTrasporto = NULL;

		-- Attività RS
		IF @isAttivitaRs = 0 OR @IdAttivitaRs = '00'
			SET @IdAttivitaRs = NULL;

		-- Attività Provenienza
		IF @isAttivitaProvenienza = 0 OR @IdAttivitaProvenienza = '0'
			SET @IdAttivitaProvenienza = NULL;

		-- Autorizzazioni: azzera se il ruolo non è previsto per l'operazione, o se è "nessuna" (SediciZeri)
		IF @isProduttore = 0 OR @IdAutorizzazioneProduttoreDetentore = @idSediciZeri
			SET @IdAutorizzazioneProduttoreDetentore = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore1 = @idSediciZeri
			SET @IdAutorizzazioneTrasportatore1 = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore2 = @idSediciZeri OR @IdAutorizzazioneTrasportatore1 IS NULL
			SET @IdAutorizzazioneTrasportatore2 = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore3 = @idSediciZeri OR @IdAutorizzazioneTrasportatore2 IS NULL
			SET @IdAutorizzazioneTrasportatore3 = NULL;

		IF @isDestinatario = 0 OR @IdAutorizzazioneDestinatario = @idSediciZeri
			SET @IdAutorizzazioneDestinatario = NULL;

		-- Autorizzazioni intermediario: gestisce i valori delle 3 possibili autorizzazioni
		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario1 = @idSediciZeri
			SET @IdAutorizzazioneIntermediario1 = NULL;

		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario2 = @idSediciZeri OR @IdAutorizzazioneIntermediario1 IS NULL
			SET @IdAutorizzazioneIntermediario2 = NULL;

		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario3 = @idSediciZeri OR @IdAutorizzazioneIntermediario2 IS NULL
			SET @IdAutorizzazioneIntermediario3 = NULL;

		-- Veicoli fuori uso
		IF
			(
				@idOperazione <> 'Z' -- Carico di rifiuto ricevuti da terzi
				OR
				ISNULL(@IdEer, '') NOT IN('160104', '160106') -- EER per veicoli fuori uso
			)
		BEGIN
			SET @IsVeicoloFuoriUso = 0;
			SET @VeicoloFuoriUsoNumero = NULL;
			SET @VeicoloFuoriUsoData = NULL;
		END

		-- Categoria RAEE
		IF
			(
				@IdRaee = '0'
				OR
				@idOperazione NOT IN('S', 'Z')
				OR
				ISNULL(@IdEer, '') NOT IN('200121', '200123', '200135', '200136', '160210', '160211', '160212', '160213', '160214', '160215', '160216')
			)
		BEGIN
			SET @IdRaee = NULL;
		END

		-- Esito
		IF @isEsito = 0 OR @IdEsito = '0'
		BEGIN
			SET @IdEsito = NULL;
			SET @QuantitaVerificata = NULL;
			SET @DataFineTrasporto = NULL;
			SET @IdCausaleRespingimento = NULL;
			SET @CausaleRespingimentoAltro = NULL;
			SET @QuantitaRespinta = NULL;
			SET @IdUnitaMisuraQuantitaRespinta = NULL;
		END
		ELSE
		BEGIN
			IF @IdEsito = 'A' SET @IdCausaleRespingimento = NULL;
			IF @IdEsito = 'A' SET @CausaleRespingimentoAltro = NULL;
			IF @IdEsito = 'A' SET @IdUnitaMisuraQuantitaRespinta = NULL;
			IF @IdEsito = 'A' SET @QuantitaRespinta = NULL;
			IF @IdEsito = 'R' SET @QuantitaRespinta = @Quantita;
			IF @IdEsito = 'R' SET @IdUnitaMisuraQuantitaRespinta = @IdUnitaMisura;
			IF @IdEsito = 'R' SET @QuantitaVerificata = NULL;
			IF @IdEsito = 'P' SET @IdUnitaMisuraQuantitaRespinta = ISNULL(@IdUnitaMisuraQuantitaRespinta, 'KG');
			IF ISNULL(@IdCausaleRespingimento, '') <> 'A' SET @CausaleRespingimentoAltro = NULL;
		END

		IF @isFormularioAssociato = 1 AND @FormularioNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questa registrazione è associata ad un formulario. Il numero deve essere valorizzato';
			GOTO BRANCH_END;
		END

		IF @isIntegrazioneFir = 1
		BEGIN
			-- Verifica l'unicità del numero di formulario solo contro registrazioni attive
			-- (r.Lock < 2), non contro il solo elenco dei formulari: un formulario può
			-- esistere senza alcuna registrazione associata (creato standalone da Formulari),
			-- nel qual caso non deve bloccare il riutilizzo del suo numero.
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Id <> @Id
					AND m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND m.FormularioNumero = @FormularioNumero
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''altra registrazione con lo stesso numero di formulario è già presente';
				GOTO BRANCH_END;
			END
		END

		IF @RegistrazioneNumero + @RegistrazioneAuto > 999999
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di registrazione non può essere superiore a 999.999';
			GOTO BRANCH_END;
		END

		-- Controllo EER/stato fisico/unità di misura nelle relazioni
		IF @lock < 2 AND @idOperazione <> 'K'
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					-- Valori effettivi della registrazione associata (ultima rettifica di correzione
					-- confermata, l'originale non viene mai modificato - viewRifiutiRegistrazioniEffettive)
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					(
					l.Id = @Id
					OR l.IdParent = @Id
					)
					AND mp.IdOperazione <> 'M'
					AND
						(
						v.IdEer <> @IdEer
						OR v.IdStatoFisico <> @IdStatoFisico
						OR v.IdUnitaMisura <> @IdUnitaMisura
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è associata ad altre con differente EER e/o stato fisico e/o unità di misura';
				GOTO BRANCH_END;
			END
		END

		-- Controllo numero registrazione duplicato (sargable)
		IF @RinumeraRegistro = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero = @RegistrazioneNumero
					AND r.Id <> @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''altra registrazione con lo stesso numero è già presente';
				GOTO BRANCH_END;
			END
		END

		-- Controllo numero > con data < (sargable)
		IF @RinumeraRegistro = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero > @RegistrazioneNumero
					AND r.[Data] < @RegistrazioneData
					AND r.Id <> @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Almeno una registrazione con numero maggiore e data inferiore a quella indicata è già presente';
				GOTO BRANCH_END;
			END
		END

		-- Controllo numero < con data > (sargable)
		IF @RinumeraRegistro = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero < @RegistrazioneNumero
					AND r.[Data] > @RegistrazioneData
					AND r.Id <> @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Almeno una registrazione con numero inferiore e data maggiore a quella indicata è già presente';
				GOTO BRANCH_END;
			END
		END

		-- Controllo data relazioni padre
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				WHERE
					l.Id = @Id
					AND
						(
						rp.[Data] < @RegistrazioneData
						OR
							(
							rp.[Data] = @RegistrazioneData
							AND rp.Numero < @RegistrazioneNumero
							)
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è associata ad altre con numero e/o data di registrazione inferiore';
				GOTO BRANCH_END;
			END
		END

		-- Controllo quantità già scaricata (l.Id = @Id: verifica che @Id, come figlio, non scenda sotto quanto già scaricato dal padre)
		IF @lock < 2
		BEGIN
			IF @Quantita < ISNULL((
				SELECT SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
				WHERE
					l.Id = @Id
					AND l.Quantita > 0
					AND rp.Lock < 2
					-- Uno scarico annullato non consuma piu' la registrazione (relazione mantenuta per la stampa)
					AND vp.IsAnnullata = 0
			), 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità non può essere inferiore a quella già associata ad altre registrazioni';
				GOTO BRANCH_END;
			END
		END

		-- Verifica quantità superiore disponibile
		IF @NessunaRegistrazioneAssociata = 0 AND EXISTS (SELECT 1
		FROM dbo.tblRifiutiOperazioniRelazioni
		WHERE Id = @idOperazione) AND @RegistrazioneAuto = 0
		BEGIN
			IF dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore(
				@Id, @Quantita, @RegistrazioneData, @RegistrazioneNumero,
				@IdEer, @IdStatoFisico, @IdUnitaMisura, 0) > 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità registrata è superiore a quella disponibile nelle registrazioni associate';
				GOTO BRANCH_END;
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
					LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
					LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000')
						OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0')
						OR ISNULL(r.IdMateriale, '00') <> ISNULL(@IdMateriale, '00')
						OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00')
						OR ISNULL(r.Numero, -1) <> ISNULL(@RegistrazioneNumero, -1)
						OR ISNULL(r.[Data], @minData) <> ISNULL(@RegistrazioneData, @minData)
						OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0')
						OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0)
						OR ISNULL(r.QuantitaVerificata, 0) <> ISNULL(@QuantitaVerificata, 0)
						OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '')
						OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData)
						OR ISNULL(r.DataFineTrasporto, @minData) <> ISNULL(@DataFineTrasporto, @minData)
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

		-- Lettura IdUtente fuori dalla transazione (intenzionale)
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

			SELECT @idUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		-- Rinumerazione registro (sargable)
		IF @RinumeraRegistro = 1
		BEGIN
			DECLARE @isLibero1 BIT = 0;
			DECLARE @isLibero2 BIT = 0;

			IF @lock = 2
				SET @RegistrazioneNumero = 1 +
					(SELECT ISNULL(MAX(r.Numero), 0)
					 FROM
						 dbo.tblRifiutiRegistrazioni r
						 INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					 WHERE
						 r.Lock < 2
						 AND m.IdRegistro = @idRegistro
						 AND r.[Data] <= @RegistrazioneData
						 AND r.[Data] >= @annoInizio
						 AND r.[Data] < @annoFine
					);

			SET @isLibero1 = IIF(EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND r.Numero = @RegistrazioneNumero
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
			), 0, 1);

			SET @isLibero2 = IIF(EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND r.Numero = @RegistrazioneNumero + 1
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
			), 0, 1);
		END

		BEGIN TRANSACTION;

			IF @RinumeraRegistro = 1
			BEGIN
				UPDATE r
				SET Numero = Numero + 1 + IIF(@lock = 2 AND @RegistrazioneAuto = 1 AND @isLibero1 = 0, 1, 0)
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND
						(
						r.[Data] > @RegistrazioneData
						OR
							(
							r.[Data] = @RegistrazioneData
							AND r.Numero > @RegistrazioneNumero
							)
						)
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND
						(
							(
							@lock < 2
							AND @isLibero2 = 0
							)
						OR
							(
							@lock = 2
							AND @RegistrazioneAuto = 1
							AND
								(
								@isLibero1 = 0
								OR @isLibero2 = 0
								)
							)
						OR
							(
							@lock = 2
							AND @RegistrazioneAuto = 0
							AND @isLibero1 = 0
							)
						);
			END

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
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneTrasportatore1, 0);

				IF @IdAutorizzazioneTrasportatore2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneTrasportatore2, 1);

					IF @IdAutorizzazioneTrasportatore3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneTrasportatore3, 2);
					END
				END
			END

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

			-- Relazioni quantità
			IF @Quantita = 0 OR @NessunaRegistrazioneAssociata = 1
			BEGIN
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @Id;
			END

			IF @NessunaRegistrazioneAssociata = 0 AND @Quantita > 0 AND @Quantita <> @totaleQuantitaAssegnata
			BEGIN
				UPDATE dbo.tblRifiutiRegistrazioniRelazioni
				SET Quantita = 0
				WHERE IdParent = @Id;

				SET @quantitaRelazione = @Quantita;

				-- Distribuzione quantità sulle relazioni ordinate per Pos
				DECLARE c CURSOR FAST_FORWARD FOR
					SELECT
						l.Id,
						-- Valori effettivi (viewRifiutiRegistrazioniEffettive): quantita' dell'ultima correzione
						-- confermata, 0 se annullata; uno scarico annullato non consuma piu' i suoi carichi
						QuantitaResidua = v2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v2 ON r.Id = v2.Id
						LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
								INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
								INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vpq ON pq.Id = vpq.Id
							WHERE
								pq.Lock < 2
								AND vpq.Quantita > 0
							GROUP BY lq.Id
						) a ON l.Id = a.Id
					WHERE l.IdParent = @Id
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
								IdParent = @Id
								AND Id = @idRelazione;
							SET @quantitaRelazione = @quantitaRelazione - @quantitaResidua;
						END
						ELSE
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaRelazione
							WHERE
								IdParent = @Id
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
				IdParent = @Id
				AND Quantita = 0;

			-- Generazione registrazione automatica di compensazione
			IF @quantitaRelazione > 0 AND @RegistrazioneAuto = 1
			BEGIN
				DECLARE @idMovimentoAuto CHAR(16);
				DECLARE @idRegistrazioneAuto CHAR(16);

				EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimentoAuto OUTPUT;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRegistrazioneAuto OUTPUT;

				INSERT dbo.tblRifiutiMovimenti (Id, IdRegistro, IdOperazione, IdEer, IdProvenienza, IdStatoFisico, IdUnitaMisura, Quantita)
				VALUES (@idMovimentoAuto, @idRegistro, 'C', @IdEer, @IdProvenienza, @IdStatoFisico, @IdUnitaMisura, @quantitaRelazione);

				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, [Data], Numero, Lock)
				VALUES
					(@idRegistrazioneAuto, @idMovimentoAuto, 'C',
					 @RegistrazioneData, @RegistrazioneNumero, 0);

				INSERT dbo.tblRifiutiRegistrazioniRelazioni
					(Id, IdParent, Operazione, Quantita, Pos)
				SELECT
					@idRegistrazioneAuto, @Id, 'S', @quantitaRelazione,
					ISNULL(MAX(Pos), -1) + 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @Id;

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimentoAuto, @IdAutorizzazioneProduttoreDetentore, @quantitaRelazione, 0);

				INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
				SELECT @idMovimentoAuto, c.Id
				FROM
					dbo.tblRifiutiClassiPericolo c
					INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

				INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
				SELECT TOP 3 @idRegistrazioneAuto, e.Id
				FROM
					dbo.tblEtichette e
					INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

				SET @RegistrazioneNumero = @RegistrazioneNumero + 1;
			END

			-- Classi di pericolo
			DELETE dbo.tblRifiutiMovimentiClassiPericolo
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT @idMovimento, c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Etichette
			DELETE dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
			SELECT TOP 3 @Id, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

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
					LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				WHERE m.Id = @idMovimento;
			END

			-- Azzera FormularioNumero se il documento non è un formulario
			IF ISNULL(@IdDocumentoTrasportoTipo, 'F') <> 'F'
				SET @FormularioNumero = NULL;

			-- Se il documento non è un formulario (tipo <> 'F') elimina il formulario associato
			IF ISNULL(@IdDocumentoTrasportoTipo, 'F') <> 'F' AND @idFormulario IS NOT NULL
			BEGIN
				DELETE dbo.tblRifiutiFormulari
				WHERE Id = @idFormulario;
				DELETE dbo.tblIdLog
				WHERE Id = @idMovimento;
				DELETE dbo.tblId
				WHERE Id = @idMovimento;
			END

			-- Aggiornamento registrazione
			UPDATE dbo.tblRifiutiRegistrazioni
			SET
				[Data] = @RegistrazioneData,
				Numero = @RegistrazioneNumero,
				IdTrasportoTransfrontalieroTipo = IIF(@IdDocumentoTrasportoTipo <> 'F', @IdDocumentoTrasportoTipo, NULL),
				Note = @RegistrazioneNote,
				Etichette = dbo.ufnRifiutiRegistrazioni_get_Etichette(Id),
				VeicoloFuoriUso = @IsVeicoloFuoriUso,
				VeicoloFuoriUsoData = @VeicoloFuoriUsoData,
				VeicoloFuoriUsoNumero = @VeicoloFuoriUsoNumero,
				IdRaee = @IdRaee,
				IdEsito = @IdEsito,
				IdCausaleRespingimento = @IdCausaleRespingimento,
				CausaleRespingimentoAltro = @CausaleRespingimentoAltro,
				QuantitaVerificata = @QuantitaVerificata,
				IdUnitaMisuraQuantitaRespinta = @IdUnitaMisuraQuantitaRespinta,
				QuantitaRespinta = @QuantitaRespinta,
				DataFineTrasporto = @DataFineTrasporto,
				IdMateriale = @IdMateriale,
				MaterialeDescrizione = @MaterialeDescrizione,
				IdAttivitaProvenienza = @IdAttivitaProvenienza,
				Lock = 0
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione non trovata o già modificata da un altro utente';
				GOTO BRANCH_END;
			END

			-- Aggiornamento movimento
			UPDATE m
			SET
				IdEer = @IdEer,
				IdProvenienza = @IdProvenienza,
				EerDescrizione = @EerDescrizione,
				IdStatoFisico = @IdStatoFisico,
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				Quantita = @Quantita,
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede,
				FormularioNumero = @FormularioNumero,
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

			-- Magazzino EoW allineato al registro operativo: una M con quantita' ridotta o materiale cambiato
			-- riduce/rimuove le proprie allocazioni sui lotti (nessun effetto senza allocazioni o su una
			-- rettifica, che non ne ha mai)
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @Id;

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

-- ============================================================ uspRifiutiRegistrazioni_upd_Rettifica
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica (@Id, collegata a un originale via
-- tblRentriRegistrazioniRettifiche.IdRettifica). Riusa integralmente uspRifiutiRegistrazioni_upd per
-- salvare la rettifica stessa (stessa validazione Data/Numero/rinumerazione/autorizzazioni/esito/ecc. di
-- una registrazione normale - la rettifica non è ancora inviata al RENTRI, quindi il blocco "già inviata"
-- di quella SP non la riguarda). Stato amministrativo e stato operativo sono separati: la rettifica viene
-- sempre salvata con i valori indicati (sono quelli trasmessi al RENTRI) e le relazioni carico/scarico non la
-- bloccano mai; l'originale non viene mai modificato. Alla conferma i valori OPERATIVI (giacenze, residui,
-- relazioni - viewRifiutiRegistrazioniEffettive) vengono scritti nella riga di tblRentriRegistrazioniRettifiche:
-- i nuovi valori se non rendono incoerenti le relazioni dell'originale, altrimenti tutti quelli operativi
-- precedenti ("tutto o niente", ufnRifiutiRegistrazioni_get_RettificaOperativa). Ogni salvataggio prima
-- dell'invio ricalcola la decisione; dopo l'invio la rettifica non e' piu' modificabile e la decisione resta.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Rettifica]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdDocumentoTrasportoTipo CHAR(1) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL,

	@IsVeicoloFuoriUso BIT = 0,
	@VeicoloFuoriUsoNumero VARCHAR(50) = NULL,
	@VeicoloFuoriUsoData DATE = NULL,

	@IdRaee CHAR(1) = NULL,

	-- Esito
	@IdEsito CHAR(1) = NULL,
	@QuantitaVerificata DECIMAL(18,2) = NULL,
	@DataFineTrasporto SMALLDATETIME = NULL,
	@IdCausaleRespingimento CHAR(1) = NULL,
	@CausaleRespingimentoAltro VARCHAR(100) = NULL,
	@IdUnitaMisuraQuantitaRespinta CHAR(2) = NULL,
	@QuantitaRespinta DECIMAL(18,2) = NULL,

	-- Materiale
	@IdMateriale CHAR(2) = NULL,
	@MaterialeDescrizione VARCHAR(200) = NULL,

	-- Provenienza
	@IdAttivitaProvenienza CHAR(1) = NULL,

	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo o dell'originale collegato
		-- (stesso pattern di uspRifiutiRegistrazioni_ins/_del - evita di esporre valori/relazioni
		-- dell'originale a una sessione senza diritti su questa specifica registrazione)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idOriginale CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id);

		IF @idOriginale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è una rettifica';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Relazioni carico/scarico dell'originale bloccate fino alla fine della transazione
			-- (UPDLOCK/HOLDLOCK): una nuova associazione sull'originale attende la conferma di questa
			-- rettifica, cosi' la decisione sui valori operativi presa sotto resta valida.
			DECLARE @relazioniOriginale INT = (SELECT COUNT(*)
			FROM dbo.tblRifiutiRegistrazioniRelazioni WITH (UPDLOCK, HOLDLOCK)
			WHERE
				Id = @idOriginale
				OR IdParent = @idOriginale
			);

			EXEC dbo.uspRifiutiRegistrazioni_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@IdEer = @IdEer,
				@IdProvenienza = @IdProvenienza,
				@EerDescrizione = @EerDescrizione,
				@IdStatoFisico = @IdStatoFisico,
				@ClassiPericolo = @ClassiPericolo,
				@IdAttivitaRs = @IdAttivitaRs,
				@RegistrazioneData = @RegistrazioneData,
				@RegistrazioneNumero = @RegistrazioneNumero,
				@IdUnitaMisura = @IdUnitaMisura,
				@Quantita = @Quantita,
				@DataInizioTrasporto = @DataInizioTrasporto,
				@IdDocumentoTrasportoTipo = @IdDocumentoTrasportoTipo,
				@FormularioNumero = @FormularioNumero,
				@IdAutorizzazioneProduttoreDetentore = @IdAutorizzazioneProduttoreDetentore,
				@IdAutorizzazioneDestinatario = @IdAutorizzazioneDestinatario,
				@IdAutorizzazioneTrasportatore1 = @IdAutorizzazioneTrasportatore1,
				@IdAutorizzazioneTrasportatore2 = @IdAutorizzazioneTrasportatore2,
				@IdAutorizzazioneTrasportatore3 = @IdAutorizzazioneTrasportatore3,
				@IdAutorizzazioneIntermediario1 = @IdAutorizzazioneIntermediario1,
				@IdAutorizzazioneIntermediario2 = @IdAutorizzazioneIntermediario2,
				@IdAutorizzazioneIntermediario3 = @IdAutorizzazioneIntermediario3,
				@RegistrazioneNote = @RegistrazioneNote,
				@UtenteNote = @UtenteNote,
				@IdEtichette = @IdEtichette,
				@IsVeicoloFuoriUso = @IsVeicoloFuoriUso,
				@VeicoloFuoriUsoNumero = @VeicoloFuoriUsoNumero,
				@VeicoloFuoriUsoData = @VeicoloFuoriUsoData,
				@IdRaee = @IdRaee,
				@IdEsito = @IdEsito,
				@QuantitaVerificata = @QuantitaVerificata,
				@DataFineTrasporto = @DataFineTrasporto,
				@IdCausaleRespingimento = @IdCausaleRespingimento,
				@CausaleRespingimentoAltro = @CausaleRespingimentoAltro,
				@IdUnitaMisuraQuantitaRespinta = @IdUnitaMisuraQuantitaRespinta,
				@QuantitaRespinta = @QuantitaRespinta,
				@IdMateriale = @IdMateriale,
				@MaterialeDescrizione = @MaterialeDescrizione,
				@IdAttivitaProvenienza = @IdAttivitaProvenienza,
				@RegistrazioneAuto = @RegistrazioneAuto,
				@RinumeraRegistro = @RinumeraRegistro,
				-- Sempre 1: una rettifica non partecipa mai al grafo carichi/scarichi (punto 3 della
				-- specifica) - non è un parametro esposto al chiamante, bypassa anche il controllo
				-- "quantità disponibile nelle registrazioni associate" che non ha senso qui
				@NessunaRegistrazioneAssociata = 1;

			-- Valori operativi (vedi header), calcolati sui valori appena salvati nel movimento della
			-- rettifica (gia' normalizzati da uspRifiutiRegistrazioni_upd, es. KG per il Materiale)
			UPDATE t
			SET
				t.IdEer = IIF(o.IsOperativa = 1, m.IdEer, o.IdEer),
				t.EerDescrizione = IIF(o.IsOperativa = 1, m.EerDescrizione, o.EerDescrizione),
				t.IdStatoFisico = IIF(o.IsOperativa = 1, m.IdStatoFisico, o.IdStatoFisico),
				t.IdUnitaMisura = IIF(o.IsOperativa = 1, m.IdUnitaMisura, o.IdUnitaMisura),
				t.Quantita = IIF(o.IsOperativa = 1, m.Quantita, o.Quantita)
			FROM
				dbo.tblRentriRegistrazioniRettifiche t
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON t.IdRettifica = r.Id
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, m.IdEer, m.IdStatoFisico, m.IdUnitaMisura, m.Quantita) o
			WHERE t.IdRettifica = @Id;

			-- Magazzino EoW allineato al registro operativo: se la correzione riduce la quantita' operativa di
			-- una M, le sue allocazioni sui lotti si riducono (correzione non operativa: nessun effetto)
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginale;

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

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

-- ============================================================ uspRifiutiRegistrazioni_upd_Annullamento
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica di ANNULLAMENTO (@Id, collegata a un
-- originale via tblRentriRegistrazioniRettifiche.IdRettifica/Annullata=1 - vedi
-- uspRifiutiRegistrazioni_upd_Rettifica per la sotto-tipologia di correzione, stessa tabella di
-- tracking). A differenza della correzione, un annullamento non ha ALCUN campo modificabile
-- dall'utente eccetto le note (RegistrazioneNote, obbligatorie: riportano il motivo dell'annullamento
-- e diventano "annotazioni" nel payload RENTRI - vedi viewRentriRegistrazioni.RettificaIsAnnullata,
-- l'hub 1_0_RentriApi traduce la riga in un "AnnullamentoMovimento" che trasmette solo il riferimento
-- alla registrazione annullata + data + annotazioni, nessun altro campo rifiuto). Numero/Data di
-- registrazione restano quelli calcolati automaticamente (nessuna UI li espone in modifica) ma vengono
-- comunque passati a uspRifiutiRegistrazioni_upd per la sua validazione standard. Tutti gli altri campi
-- vengono riletti invariati dalla riga stessa (snapshot copiato dall'originale al momento dell'INSERT,
-- mai più toccato) e passati pari pari a uspRifiutiRegistrazioni_upd. Come la correzione, un annullamento
-- non modifica mai l'originale e non e' mai bloccato dalle relazioni carico/scarico (l'annullamento va sempre
-- trasmesso al RENTRI). Alla conferma i valori OPERATIVI vengono scritti nella riga di
-- tblRentriRegistrazioniRettifiche (ufnRifiutiRegistrazioni_get_RettificaOperativa): Quantita = 0 (registrazione
-- esclusa da giacenze e relazioni, viewRifiutiRegistrazioniEffettive.IsAnnullata) se l'esclusione non rende
-- incoerenti le relazioni (es. scarico senza carichi derivati, i cui carichi tornano disponibili); per un
-- carico gia' consumato da scarichi o uno scarico da cui derivano carichi (es. I -> M/NP) restano invece i
-- valori operativi precedenti: annullato per il RENTRI, continua ad avere effetto in Ecomatico.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Annullamento]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo (stesso pattern di
		-- uspRifiutiRegistrazioni_upd_Rettifica)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idOriginale CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE
			IdRettifica = @Id
			AND Annullata = 1
		);

		IF @idOriginale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è un annullamento';
			GOTO BRANCH_END;
		END

		SET @RegistrazioneNote = NULLIF(LTRIM(RTRIM(@RegistrazioneNote)), '');

		-- Punto 5 della specifica: unico dato editabile dall'utente, obbligatorio (riporta il motivo
		-- dell'annullamento, diventa "annotazioni" nel payload RENTRI)
		IF @RegistrazioneNote IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
			GOTO BRANCH_END;
		END

		-- Rilettura pass-through di tutti i campi non modificabili qui (snapshot copiato dall'originale
		-- all'INSERT): stessa forma di uspRifiutiRegistrazioni_get, così uspRifiutiRegistrazioni_upd non
		-- vede alcuna differenza rispetto ai valori già presenti e non rifiuta/altera nulla oltre a
		-- Numero/Data/Note.
		DECLARE
			@idMovimento CHAR(16), @idEer CHAR(6), @idProvenienza CHAR(1), @eerDescrizione VARCHAR(200),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idUnitaMisura CHAR(2), @quantita DECIMAL(18, 2),
			@dataInizioTrasporto SMALLDATETIME, @idDocumentoTrasportoTipo CHAR(1), @formularioNumero VARCHAR(20),
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneTrasportatore2 CHAR(16), @idAutorizzazioneTrasportatore3 CHAR(16),
			@idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16), @idAutorizzazioneIntermediario3 CHAR(16),
			@utenteNote VARCHAR(500),
			@isVeicoloFuoriUso BIT, @veicoloFuoriUsoNumero VARCHAR(50), @veicoloFuoriUsoData DATE,
			@idRaee CHAR(1),
			@idEsito CHAR(1), @quantitaVerificata DECIMAL(18, 2), @isQuantitaVerificata BIT, @dataFineTrasporto SMALLDATETIME,
			@idCausaleRespingimento CHAR(1), @causaleRespingimentoAltro VARCHAR(100), @idUnitaMisuraQuantitaRespinta CHAR(2), @quantitaRespinta DECIMAL(18, 2),
			@idMateriale CHAR(2), @materialeDescrizione VARCHAR(200),
			@idAttivitaProvenienza CHAR(1);

		SELECT
			@idMovimento = m.Id,
			@idEer = m.IdEer,
			@idProvenienza = m.IdProvenienza,
			@eerDescrizione = m.EerDescrizione,
			@idStatoFisico = m.IdStatoFisico,
			@idAttivitaRs = m.IdAttivita,
			@idUnitaMisura = m.IdUnitaMisura,
			@quantita = m.Quantita,
			@dataInizioTrasporto = m.DataInizioTrasporto,
			@idDocumentoTrasportoTipo = r.IdTrasportoTransfrontalieroTipo,
			@formularioNumero = m.FormularioNumero,
			@utenteNote = m.Note,
			@isVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),
			@veicoloFuoriUsoNumero = r.VeicoloFuoriUsoNumero,
			@veicoloFuoriUsoData = r.VeicoloFuoriUsoData,
			@idRaee = r.IdRaee,
			@idEsito = r.IdEsito,
			@quantitaVerificata = r.QuantitaVerificata,
			@dataFineTrasporto = r.DataFineTrasporto,
			@idCausaleRespingimento = r.IdCausaleRespingimento,
			@causaleRespingimentoAltro = r.CausaleRespingimentoAltro,
			@idUnitaMisuraQuantitaRespinta = r.IdUnitaMisuraQuantitaRespinta,
			@quantitaRespinta = r.QuantitaRespinta,
			@idMateriale = r.IdMateriale,
			@materialeDescrizione = r.MaterialeDescrizione,
			@idAttivitaProvenienza = r.IdAttivitaProvenienza
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @Id;

		SELECT @idAutorizzazioneProduttoreDetentore = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiProduttori
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneDestinatario = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiDestinatari
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore1 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiTrasportatori
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore2 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiTrasportatori
		WHERE
			Id = @idMovimento
			AND Pos = 1;
		SELECT @idAutorizzazioneTrasportatore3 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiTrasportatori
		WHERE
			Id = @idMovimento
			AND Pos = 2;
		SELECT @idAutorizzazioneIntermediario1 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiIntermediari
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneIntermediario2 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiIntermediari
		WHERE
			Id = @idMovimento
			AND Pos = 1;
		SELECT @idAutorizzazioneIntermediario3 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiIntermediari
		WHERE
			Id = @idMovimento
			AND Pos = 2;

		DECLARE @classiPericolo VARCHAR(50) = (
			SELECT STRING_AGG(c.Codice, ';')
			FROM
				dbo.tblRifiutiMovimentiClassiPericolo mc
				INNER JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
			WHERE mc.Id = @idMovimento);

		DECLARE @idEtichette VARCHAR(50) = (
			SELECT STRING_AGG(IdEtichetta, ';')
			FROM dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id);

		BEGIN TRANSACTION;

			-- Relazioni carico/scarico dell'originale bloccate fino alla fine della transazione
			-- (UPDLOCK/HOLDLOCK): una nuova associazione sull'originale attende la conferma di questo
			-- annullamento, cosi' la decisione sui valori operativi presa sotto resta valida.
			DECLARE @relazioniOriginale INT = (SELECT COUNT(*)
			FROM dbo.tblRifiutiRegistrazioniRelazioni WITH (UPDLOCK, HOLDLOCK)
			WHERE
				Id = @idOriginale
				OR IdParent = @idOriginale
			);

			EXEC dbo.uspRifiutiRegistrazioni_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@IdEer = @idEer,
				@IdProvenienza = @idProvenienza,
				@EerDescrizione = @eerDescrizione,
				@IdStatoFisico = @idStatoFisico,
				@ClassiPericolo = @classiPericolo,
				@IdAttivitaRs = @idAttivitaRs,
				@RegistrazioneData = @RegistrazioneData,
				@RegistrazioneNumero = @RegistrazioneNumero,
				@IdUnitaMisura = @idUnitaMisura,
				@Quantita = @quantita,
				@DataInizioTrasporto = @dataInizioTrasporto,
				@IdDocumentoTrasportoTipo = @idDocumentoTrasportoTipo,
				@FormularioNumero = @formularioNumero,
				@IdAutorizzazioneProduttoreDetentore = @idAutorizzazioneProduttoreDetentore,
				@IdAutorizzazioneDestinatario = @idAutorizzazioneDestinatario,
				@IdAutorizzazioneTrasportatore1 = @idAutorizzazioneTrasportatore1,
				@IdAutorizzazioneTrasportatore2 = @idAutorizzazioneTrasportatore2,
				@IdAutorizzazioneTrasportatore3 = @idAutorizzazioneTrasportatore3,
				@IdAutorizzazioneIntermediario1 = @idAutorizzazioneIntermediario1,
				@IdAutorizzazioneIntermediario2 = @idAutorizzazioneIntermediario2,
				@IdAutorizzazioneIntermediario3 = @idAutorizzazioneIntermediario3,
				@RegistrazioneNote = @RegistrazioneNote,
				@UtenteNote = @utenteNote,
				@IdEtichette = @idEtichette,
				@IsVeicoloFuoriUso = @isVeicoloFuoriUso,
				@VeicoloFuoriUsoNumero = @veicoloFuoriUsoNumero,
				@VeicoloFuoriUsoData = @veicoloFuoriUsoData,
				@IdRaee = @idRaee,
				@IdEsito = @idEsito,
				@QuantitaVerificata = @quantitaVerificata,
				@DataFineTrasporto = @dataFineTrasporto,
				@IdCausaleRespingimento = @idCausaleRespingimento,
				@CausaleRespingimentoAltro = @causaleRespingimentoAltro,
				@IdUnitaMisuraQuantitaRespinta = @idUnitaMisuraQuantitaRespinta,
				@QuantitaRespinta = @quantitaRespinta,
				@IdMateriale = @idMateriale,
				@MaterialeDescrizione = @materialeDescrizione,
				@IdAttivitaProvenienza = @idAttivitaProvenienza,
				@RegistrazioneAuto = @RegistrazioneAuto,
				@RinumeraRegistro = @RinumeraRegistro,
				-- Sempre 1, come per la rettifica di correzione: un annullamento non partecipa mai al grafo
				-- carichi/scarichi, non è un parametro esposto al chiamante
				@NessunaRegistrazioneAssociata = 1;

			-- Valori operativi (vedi header): Quantita = 0 se l'annullamento vale anche per Ecomatico,
			-- altrimenti tutti i valori operativi precedenti
			UPDATE t
			SET
				t.IdEer = o.IdEer,
				t.EerDescrizione = o.EerDescrizione,
				t.IdStatoFisico = o.IdStatoFisico,
				t.IdUnitaMisura = o.IdUnitaMisura,
				t.Quantita = IIF(o.IsOperativa = 1, 0, o.Quantita)
			FROM
				dbo.tblRentriRegistrazioniRettifiche t
				CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, NULL, NULL, NULL, NULL) o
			WHERE t.IdRettifica = @Id;

			-- Magazzino EoW allineato al registro operativo: una M annullata (quantita' operativa 0) perde
			-- tutte le allocazioni sui lotti
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginale;

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

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

-- ============================================================ uspRifiutiRegistrazioni_del
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0,
	@IsMultipla BIT = 0
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id);

		-- Se @Id è una registrazione di rettifica, @idOriginaleRettifica è l'Id della registrazione
		-- rettificata (tblRentriRegistrazioniRettifiche.Id) - NULL per una registrazione normale.
		DECLARE @idOriginaleRettifica CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: registrazione mai esistita o già cancellata (es. doppio invio della
			-- richiesta di annullamento lato UI) — trattata come cancellazione già avvenuta con
			-- successo, non come errore. Salta anche il controllo di titolarità sottostante e
			-- l'intera catena Lock, che non hanno senso su un record inesistente.
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica non ancora inviata al RENTRI è sempre cancellata in modo
		-- irreversibile (mai soft-delete/Undo, vedi sotto) tramite una modale dedicata con conferma
		-- esplicita: la cancellazione multipla (checkbox in elenco) non è ammessa su di essa.
		IF @IsMultipla = 1 AND @idOriginaleRettifica IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND RentriIdentificativo IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica non ancora inviata al RENTRI va cancellata singolarmente';
			GOTO BRANCH_END;
		END

		DECLARE @idMovimento CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @isFormulario BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @conservazioneSostitutiva BIT;

		-- ── CASO 1: registrazione attiva (Lock = 0) → soft delete, o hard delete se è una rettifica ──
		IF @lock = 0
		BEGIN
			SELECT @rentriIdentificativo = RentriIdentificativo, @rentriData = RentriData, @conservazioneSostitutiva = ConservazioneSostitutiva
			FROM dbo.tblRifiutiRegistrazioni
			WHERE Id = @Id;

			-- Una registrazione già trasmessa a RENTRI non può più essere cancellata (vale anche per una rettifica)
			IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			-- Una registrazione bloccata per la conservazione sostitutiva non può più essere cancellata
			IF ISNULL(@conservazioneSostitutiva, 0) = 1
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni a
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.IdParent = r.Id
				WHERE
					a.Id = @Id
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione associata ad altre non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Recupero dati registrazione
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id,
				@operazione = r.Operazione,
				@idOperazione = m.IdOperazione
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
			WHERE r.Id = @Id;

			IF @idOriginaleRettifica IS NOT NULL
			BEGIN
				-- Rettifica confermata (Lock = 0) ma non ancora inviata al RENTRI: cancellazione sempre
				-- irreversibile (punto 6 della specifica, mai passa da Lock = 4/Undo), hard delete completo
				-- della rettifica, stessa sequenza del CASO 3 sotto. L'originale non e' mai stato modificato:
				-- cancellando la rettifica tornano operativi i valori precedenti (quelli scritti dalla rettifica
				-- confermata precedente o i valori propri dell'originale; per un annullamento, la quantita'
				-- piena). Va quindi rifiutata se nel frattempo le relazioni carico/scarico si sono basate sui
				-- valori rettificati e con i valori precedenti una giacenza andrebbe sotto zero. Una rettifica
				-- non applicata a Ecomatico (valori operativi = precedenti) si cancella sempre.
				BEGIN TRANSACTION;

					DECLARE @isAnnullamentoRettifica BIT = (SELECT ISNULL(Annullata, 0)
					FROM dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id
					);

					-- Relazioni attive dell'originale (controparte non in bozza e non annullata), bloccate fino
					-- alla fine della transazione: nessuna nuova associazione puo' nascere durante il controllo
					DECLARE @relazioni TABLE (Id CHAR(16), IdParent CHAR(16), Quantita DECIMAL(18, 2));
					INSERT @relazioni (Id, IdParent, Quantita)
					SELECT l.Id, l.IdParent, l.Quantita
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l WITH (UPDLOCK, HOLDLOCK)
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON l.Id = v.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON l.IdParent = vp.Id
					WHERE
						(
						l.Id = @idOriginaleRettifica
						OR l.IdParent = @idOriginaleRettifica
						)
						AND l.Quantita > 0
						AND r.Lock < 2
						AND rp.Lock < 2
						AND
							(
							v.IsAnnullata = 0
							OR l.Id = @idOriginaleRettifica
							)
						AND
							(
							vp.IsAnnullata = 0
							OR l.IdParent = @idOriginaleRettifica
							);

					IF @isAnnullamentoRettifica = 0 AND EXISTS (SELECT 1
					FROM @relazioni)
					BEGIN
						-- Correzione: valori operativi senza questa rettifica = quelli scritti dall'ultima altra
						-- rettifica confermata, altrimenti i valori propri dell'originale
						DECLARE @precIdEer CHAR(6), @precIdStatoFisico CHAR(1), @precIdUnitaMisura CHAR(2), @precQuantita DECIMAL(18, 2);

						SELECT
							@precIdEer = IdEer,
							@precIdStatoFisico = IdStatoFisico,
							@precIdUnitaMisura = IdUnitaMisura,
							@precQuantita = Quantita
						FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);

						IF EXISTS (
							SELECT 1
							FROM dbo.viewRifiutiRegistrazioniEffettive
							WHERE
								Id = @idOriginaleRettifica
								AND
									(
									ISNULL(@precIdEer, '') <> ISNULL(IdEer, '')
									OR ISNULL(@precIdStatoFisico, '') <> ISNULL(IdStatoFisico, '')
									OR ISNULL(@precIdUnitaMisura, '') <> ISNULL(IdUnitaMisura, '')
									)
						)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0)
						FROM @relazioni
						WHERE Id = @idOriginaleRettifica)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0)
						FROM @relazioni
						WHERE IdParent = @idOriginaleRettifica)
						BEGIN
							ROLLBACK TRANSACTION;
							SET @returnValue = -1;
							SET @returnMessage = 'La registrazione rettificata è stata associata ad altre con i valori corretti: la rettifica non può più essere cancellata';
							GOTO BRANCH_END;
						END
					END

					-- Annullamento di uno scarico: cancellandolo lo scarico torna a consumare i suoi carichi, che
					-- nel frattempo potrebbero essere stati scaricati da altre registrazioni. (Un carico annullato
					-- invece non poteva essere consumato ne' associato: torna disponibile senza problemi.)
					IF @isAnnullamentoRettifica = 1 AND EXISTS (
						SELECT 1
						FROM
							@relazioni l
							INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vc ON l.Id = vc.Id
							INNER JOIN dbo.tblRifiutiRegistrazioni ro ON l.IdParent = ro.Id
						WHERE
							l.IdParent = @idOriginaleRettifica
							AND ro.Operazione = 'S'
							AND vc.Quantita < l.Quantita + ( SELECT ISNULL(SUM(l2.Quantita), 0) FROM dbo.tblRifiutiRegistrazioniRelazioni l2 INNER JOIN dbo.tblRifiutiRegistrazioni rp2 ON l2.IdParent = rp2.Id INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp2 ON l2.IdParent = vp2.Id WHERE l2.Id = l.Id AND rp2.Operazione = 'S' AND l2.IdParent <> @idOriginaleRettifica AND l2.Quantita > 0 AND rp2.Lock < 2 AND vp2.IsAnnullata = 0 )
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'I carichi dello scarico annullato sono stati scaricati da altre registrazioni: l''annullamento non può più essere cancellato';
						GOTO BRANCH_END;
					END

					DELETE dbo.tblRifiutiRegistrazioniRelazioni
					WHERE
						Id = @Id
						OR IdParent = @Id;
					DELETE dbo.tblRifiutiMovimentiClassiPericolo
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiProduttori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiDestinatari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiTrasportatori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiIntermediari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiLog
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiRegistrazioniEtichette
					WHERE Id = @Id;
					-- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione è NOT NULL (fa parte
					-- della PK composta con IdLotto) - non si può azzerare come il vecchio
					-- tblEoWMovimenti.IdRegistrazione (nullable), va rimossa la riga di collegamento.
					DELETE dbo.tblEoWLottiRifiutiRegistrazioni
					WHERE IdRegistrazione = @Id;
					DELETE dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id;
					DELETE dbo.tblRifiutiRegistrazioni
					WHERE Id = @Id;
					DELETE dbo.tblRifiutiFormulari
					WHERE
						IdMovimento = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimenti
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblIdLog
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);
					DELETE dbo.tblId
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);

					-- Magazzino EoW allineato al registro operativo: senza questa rettifica l'originale torna ai
					-- valori operativi precedenti; se sono piu' bassi (la correzione cancellata aveva aumentato
					-- una M) le sue allocazioni sui lotti si riducono
					EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginaleRettifica;

				COMMIT TRANSACTION;
			END
			ELSE
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblRifiutiRegistrazioni
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Registrazione non trovata o già eliminata';
						GOTO BRANCH_END;
					END

					IF @Reset = 1
						DELETE dbo.tblIdCancellati
						WHERE IdSessione = @IdSessione;
					ELSE
						DELETE dbo.tblIdCancellati
						WHERE Id = @Id;

					INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
					VALUES (@Id, @IdSessione, GETDATE());

				COMMIT TRANSACTION;

				EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
			END
		END

		-- ── CASO 2: registrazione non confermata (Lock = 1) ──────────────────
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- ── CASO 3: registrazione in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id
			FROM
				dbo.tblRifiutiRegistrazioni r
				LEFT JOIN dbo.tblRifiutiFormulari f ON r.IdMovimento = f.IdMovimento
			WHERE r.Id = @Id;

			BEGIN TRANSACTION;
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE
					Id = @Id
					OR IdParent = @Id;
				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				-- (stesso gap trovato e corretto in uspRifiutiFormulari_del il 2026-08-21)
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiRegistrazioniEtichette
				WHERE Id = @Id;
				-- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione è NOT NULL (fa parte
				-- della PK composta con IdLotto) - non si può azzerare come il vecchio
				-- tblEoWMovimenti.IdRegistrazione (nullable), va rimossa la riga di collegamento.
				DELETE dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @Id;
				-- Bozza di rettifica mai confermata: non ha mai contato nei valori effettivi
				-- (viewRifiutiRegistrazioniEffettive considera solo Lock = 0), basta rimuovere il collegamento.
				DELETE dbo.tblRentriRegistrazioniRettifiche
				WHERE IdRettifica = @Id;
				DELETE dbo.tblRifiutiRegistrazioni
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE
					IdMovimento = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimenti
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
			COMMIT TRANSACTION;
		END

		-- ── CASO 4: Lock in stato non gestito ────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

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

-- ============================================================ uspRifiutiFormulari_upd
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
					-- Valori effettivi della registrazione associata (ultima rettifica di correzione
					-- confermata, l'originale non viene mai modificato - viewRifiutiRegistrazioniEffettive)
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
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
						v.IdEer <> @IdEer
						OR v.IdStatoFisico <> @IdStatoFisico
						OR v.IdUnitaMisura <> @IdUnitaMisura
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
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
				WHERE
					l.Id = @idRegistrazione
					AND l.Quantita > 0
					AND rp.Lock < 2
					-- Uno scarico annullato non consuma piu' la registrazione (relazione mantenuta per la stampa)
					AND vp.IsAnnullata = 0
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
						-- Valori effettivi (viewRifiutiRegistrazioniEffettive): quantita' dell'ultima correzione
						-- confermata, 0 se annullata; uno scarico annullato non consuma piu' i suoi carichi
						QuantitaResidua = v2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v2 ON r.Id = v2.Id
						LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
								INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
								INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vpq ON pq.Id = vpq.Id
							WHERE
								pq.Lock < 2
								AND vpq.Quantita > 0
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

			-- Magazzino EoW allineato al registro operativo: la quantita' del movimento e' anche quella della
			-- registrazione associata, se e' una M con allocazioni queste si adeguano
			IF @idRegistrazione IS NOT NULL
				EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idRegistrazione;

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

-- ============================================================ uspEoWLotti_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
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
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
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

		SELECT
			l.Id,
			-- Stato: prima l'anomalia "Scaricato più del prodotto" (il magazzino tradizionale ha scaricato
			-- più di quanto il registro operativo attribuisce al lotto: il magazzino EoW prevale e non viene
			-- mai corretto in automatico), poi la capacità (solo con quantità massima impostata; il lotto EoW
			-- è una partita di produzione, gli scarichi non liberano capienza): 2 = anomalia o capacità
			-- superata, 1 = lotto pieno o capacità residua sotto il 30% della quantità massima, 0 = OK
			StatoValore = CASE
				WHEN s.Giacenza < 0 THEN 2
				WHEN l.QuantitaMax IS NULL THEN 0
				WHEN c.QuantitaAttribuita > l.QuantitaMax THEN 2
				WHEN l.QuantitaMax - c.QuantitaAttribuita < l.QuantitaMax * 0.3 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN s.Giacenza < 0
					THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(s.Prodotta, 'N2', 'it-IT') + ' kg, scaricati '
						+ FORMAT(s.Scaricata, 'N2', 'it-IT') + ' kg dal magazzino'
				WHEN l.QuantitaMax IS NULL THEN 'OK'
				WHEN c.QuantitaAttribuita > l.QuantitaMax
					THEN 'Capacità superata di ' + FORMAT(c.QuantitaAttribuita - l.QuantitaMax, 'N2', 'it-IT') + ' kg: attribuiti '
						+ FORMAT(c.QuantitaAttribuita, 'N2', 'it-IT') + ' kg su ' + FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				WHEN c.QuantitaAttribuita = l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
				WHEN l.QuantitaMax - c.QuantitaAttribuita < l.QuantitaMax * 0.3
					THEN 'Capacità residua sotto il 30%: ' + FORMAT(l.QuantitaMax - c.QuantitaAttribuita, 'N2', 'it-IT') + ' kg su '
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
			QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAttribuita, 0) END,
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
					QuantitaAttribuita = SUM(r.Quantita),
					NumeroRegistrazioni = COUNT(DISTINCT r.IdRegistrazione)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
					CROSS APPLY (SELECT QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0)) c
					CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) s
		WHERE
			l.Lock = 0
			AND
				(
				@IdSede IS NULL
				OR l.IdSede = @IdSede
				)
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

-- ============================================================ uspEoWGiacenze_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
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

		-- Giacenza (coerente con Rifiuti/Giacenze): Quantita = quanto c'è oggi nel lotto, cioè le
		-- quote di registrazioni M attive (Lock < 2: una registrazione eliminata mantiene le sue
		-- quote per un eventuale ripristino, ma non conta più) meno gli scarichi dei movimenti di
		-- magazzino confermati; solo le righe con giacenza diversa da 0: una giacenza negativa è
		-- l'anomalia "Scaricato più del prodotto" (il magazzino EoW deriva dal registro operativo e
		-- prevale sul magazzino tradizionale, non viene mai corretto in automatico). GiacenzaGiorni = giorni dalla
		-- prima registrazione M del lotto. La capacità residua resta riferita alla produzione
		-- (QuantitaMax - quantità attribuita): il lotto EoW è una partita di produzione, gli
		-- scarichi non liberano capienza.
		IF @Vista = 'L'
		BEGIN
			SELECT
				l.Id,
				-- 2 = anomalia (scaricato più del prodotto), 1 = lotto pieno (la produzione attribuita ha
				-- raggiunto la quantità massima), 0 = OK
				StatoValore = CASE
					WHEN ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) < 0 THEN 2
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAttribuita, 0) >= l.QuantitaMax THEN 1
					ELSE 0
				END,
				StatoDescrizione = CASE
					WHEN ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) < 0
						THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(ISNULL(q.QuantitaAttribuita, 0), 'N2', 'it-IT') + ' kg, scaricati '
							+ FORMAT(ISNULL(sc.Scaricata, 0), 'N2', 'it-IT') + ' kg dal magazzino'
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAttribuita, 0) >= l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
					ELSE 'OK'
				END,
				l.Nome,
				MaterialeNome = m.Nome,
				SedeNome = s.Nome,
				l.QuantitaMax,
				QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
				Quantita = ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAttribuita, 0) END,
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWLotti l
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
				INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
				LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				OUTER APPLY (
					SELECT
						QuantitaAttribuita = SUM(r.Quantita),
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
				AND
					(
					@IdSede IS NULL
					OR l.IdSede = @IdSede
					)
				AND
					(
					@Search IS NULL
					OR l.Nome LIKE '%' + @Search + '%'
					)
				AND ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) <> 0
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
				SedeNome = s.Nome,
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
				Quantita = ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWMagazzini g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
				OUTER APPLY (
					SELECT
						QuantitaAttribuita = SUM(r.Quantita),
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
				AND
					(
					@IdSede IS NULL
					OR g.IdSede = @IdSede
					)
				AND
					(
					@Search IS NULL
					OR g.Nome LIKE '%' + @Search + '%'
					)
				AND
					(
					ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) <> 0
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

-- ============================================================ uspMagazziniMovimentiRigheEoW_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdMateriale,
			MaterialeNome = m.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Quantità già relazionata ai lotti EoW consumati (costruita in uspMagazziniMovimenti_upd)
			Relazionata = ISNULL(q.Relazionata, 0),
			r.IdLotto,
			LottoNome = lr.Nome,
			-- Movimento confermato: quantità residua (giacenza attuale) del lotto EoW da cui la
			-- riga ha scaricato; su più lotti somma dei residui con il dettaglio per lotto.
			-- NULL su movimento in bozza (residuo non ancora noto).
			ResiduoLotti = IIF(mv.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(mv.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			-- Anomalia "Scaricato più del prodotto": almeno un lotto EoW da cui la riga ha scaricato ha
			-- giacenza negativa (il registro operativo gli attribuisce meno di quanto già scaricato; il
			-- magazzino EoW prevale, i movimenti non vengono corretti in automatico)
			IsScaricatoPiuDelProdotto = CAST(IIF(mv.Lock = 0 AND ISNULL(z.LottiAnomali, 0) > 0, 1, 0) AS BIT),
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
			INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
			OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita)
			FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl
			WHERE rl.Id = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					LottiAnomali = SUM(IIF(g.Giacenza < 0, 1, 0)),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rl
					INNER JOIN dbo.tblEoWLotti lg ON rl.IdLotto = lg.Id
					-- Giacenza del lotto EoW: quote di registrazioni M attive meno scarichi
					-- confermati di questo modulo
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(qp.Quantita)
								FROM
									dbo.tblEoWLottiRifiutiRegistrazioni qp
									INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
								WHERE
									qp.IdLotto = lg.Id
									AND rr.Lock < 2
							), 0) - ISNULL((
								SELECT SUM(rs.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheEoWLotti rs
									INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rs.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
									CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, 'N2', 'it-IT') AS NVARCHAR(MAX))) t
				WHERE rl.Id = r.Id) z
		WHERE r.IdMovimento = @IdMovimento
		ORDER BY r.Id
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

-- ============================================================ uspEoWLottiRifiutiRegistrazioni_get_Allineamento_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Anteprima per la modale di conferma "La modifica operativa andrà a modificare le quantità già allocate":
-- elenca, lotto per lotto, come cambierebbero le allocazioni EoW della registrazione M coinvolta se si
-- salvasse (@Azione = 'U') o cancellasse (@Azione = 'D') la registrazione @Id, con la stessa regola
-- dell'allineamento (ufnEoWLottiRifiutiRegistrazioni_get_Allineamento, applicata al salvataggio da
-- uspEoWLottiRifiutiRegistrazioni_upd_Allinea). Nessuna riga = nessuna allocazione cambia, niente modale.
-- - @Id registrazione normale: 'U' con la quantita' (@Quantita) e il materiale (@IdMateriale, NULL se la
--   causale non e' di materiale prodotto) del form; 'D' = la M cancellata non conta piu' nei lotti
--   (allocazioni conservate per "Annulla cancellazione", QuantitaNuova = 0 indica che non contano).
-- - @Id rettifica: la M coinvolta e' l'originale; 'U' = quantita' operativa dopo il salvataggio (correzione
--   operativa: @Quantita; annullamento operativo: 0; non operativa: invariata, stessa decisione di
--   ufnRifiutiRegistrazioni_get_RettificaOperativa); 'D' = l'originale torna ai valori operativi senza questa
--   rettifica (una bozza mai confermata non ha mai contato: nessun effetto).
-- Scaricata/Giacenza dal saldo del lotto (ufnEoWLotti_get_Saldo); IsSottoScaricato = dopo la modifica il
-- lotto avrebbe meno prodotto di quanto gia' scaricato dal magazzino (anomalia, mai bloccante).
-- Solo con il modulo EoW attivo; permesso della funzione Registrazioni (RRG): la modale compare a chi salva
-- la registrazione, anche senza accesso alla gestione EoW.
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_get_Allineamento_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Azione CHAR(1) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Azione = NULLIF(LTRIM(RTRIM(@Azione)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = ISNULL(NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), ''), 'KG');

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
		IF @Azione IS NULL OR @Azione NOT IN ('U', 'D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Azione deve essere U (salvataggio) o D (cancellazione)';
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

		-- Titolarita' della registrazione
		DECLARE @lock TINYINT;
		SELECT @lock = ISNULL(r.Lock, 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @Id;

		IF @lock IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRegistrazioneM CHAR(16);
		DECLARE @quantitaNuova DECIMAL(18, 2);
		DECLARE @idMaterialeNuovo CHAR(2);

		IF dbo.ufnModuli_get_IsAttivoBySessione('EOW', @IdSessione) = 1
		BEGIN
			DECLARE @idOriginale CHAR(16);
			DECLARE @isAnnullamento BIT;
			SELECT
				@idOriginale = Id,
				@isAnnullamento = ISNULL(Annullata, 0)
			FROM dbo.tblRentriRegistrazioniRettifiche
			WHERE IdRettifica = @Id;

			IF @idOriginale IS NULL
			BEGIN
				-- Registrazione normale: e' essa stessa la M
				SET @idRegistrazioneM = @Id;
				IF @Azione = 'U'
					SELECT
						@quantitaNuova = ISNULL(@Quantita, 0),
						@idMaterialeNuovo = @IdMateriale;
				ELSE
					SELECT
						@quantitaNuova = 0,
						@idMaterialeNuovo = r.IdMateriale
					FROM dbo.tblRifiutiRegistrazioni r
					WHERE r.Id = @Id;
			END
			ELSE
			BEGIN
				-- Rettifica: la M e' l'originale, il materiale operativo resta quello dell'originale
				SET @idRegistrazioneM = @idOriginale;
				SELECT @idMaterialeNuovo = IIF(ISNULL(o.IsMateriale, 0) = 1, r.IdMateriale, NULL)
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				WHERE r.Id = @idOriginale;

				-- Valori operativi senza questa rettifica (ultima altra rettifica confermata o originale)
				DECLARE @precIdEer CHAR(6), @precIdStatoFisico CHAR(1), @precIdUnitaMisura CHAR(2), @precQuantita DECIMAL(18, 2);
				SELECT
					@precIdEer = IdEer,
					@precIdStatoFisico = IdStatoFisico,
					@precIdUnitaMisura = IdUnitaMisura,
					@precQuantita = Quantita
				FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);

				IF @Azione = 'D'
					-- Cancellando una rettifica confermata l'originale torna ai valori precedenti; una bozza
					-- (Lock 2) non ha mai contato: valori operativi invariati
					SET @quantitaNuova = IIF(@lock = 0, @precQuantita, (SELECT Quantita
					FROM dbo.viewRifiutiRegistrazioniEffettive
					WHERE Id = @idOriginale));
				ELSE IF @isAnnullamento = 1
					SELECT @quantitaNuova = IIF(IsOperativa = 1, 0, Quantita)
					FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);
				ELSE
				BEGIN
					-- Correzione: per il materiale EER/stato fisico/UM non sono modificabili (stessa
					-- normalizzazione di uspRifiutiRegistrazioni_get_RettificaIsOperativa)
					IF @idMaterialeNuovo IS NOT NULL
						SELECT
							@IdEer = @precIdEer,
							@IdStatoFisico = @precIdStatoFisico,
							@IdUnitaMisura = 'KG';

					SELECT @quantitaNuova = IIF(IsOperativa = 1, ISNULL(@Quantita, 0), Quantita)
					FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, @IdEer, @IdStatoFisico, @IdUnitaMisura, @Quantita);
				END
			END

			-- Solo registrazioni M attive (una cancellata o in bozza non conta nei lotti)
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @idRegistrazioneM
				AND Lock < 2
			)
				SET @idRegistrazioneM = NULL;
		END

		SELECT
			n.IdLotto,
			LottoNome = l.Nome,
			n.Quantita,
			n.QuantitaNuova,
			s.Scaricata,
			s.Giacenza,
			GiacenzaNuova = s.Giacenza - (n.Quantita - n.QuantitaNuova),
			IsSottoScaricato = CAST(IIF(s.Giacenza - (n.Quantita - n.QuantitaNuova) < 0, 1, 0) AS BIT)
		FROM
			dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento(@idRegistrazioneM, @quantitaNuova, @idMaterialeNuovo) n
			INNER JOIN dbo.tblEoWLotti l ON n.IdLotto = l.Id
			CROSS APPLY dbo.ufnEoWLotti_get_Saldo(n.IdLotto) s
		WHERE
			@idRegistrazioneM IS NOT NULL
			-- Modale solo se almeno un'allocazione cambia; in quel caso tutte le allocazioni, per la fotografia
			AND EXISTS (SELECT 1 FROM dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento(@idRegistrazioneM, @quantitaNuova, @idMaterialeNuovo) x WHERE x.QuantitaNuova <> x.Quantita)
		ORDER BY l.Nome;

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
