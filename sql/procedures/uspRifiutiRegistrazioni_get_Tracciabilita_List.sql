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
