-- Deploy produzione 2026-10-01: Rifiuti > Registrazioni > Edit, Azioni > Tracciabilita' e select sedi di Magazzino/Movimenti (3 SP).
-- - uspMagazziniMovimentiRighe_get_SediSelectList, uspMagazziniDdt_get_SediSelectList: testo nome + indirizzo (come la
--   select delle sedi interne del contesto), ricerca anche sull'indirizzo; firma e colonne invariate.
-- - uspRifiutiRegistrazioni_get_Tracciabilita_List: filiera della registrazione per livelli (carichi di provenienza,
--   scarichi, carichi derivati, lotti EoW e quantita' da allocare), verso cronologico delle relazioni carico/scarico.
-- Solo SP di lettura, nessuna modifica a tabelle; firme invariate (nessun vincolo di ordine con l'app). Indipendente dal bundle sede_contesto_registro.
-- Da pubblicare insieme all'app con la voce di menu Tracciabilita' (l'app precedente non la chiama: lo script si
-- puo' eseguire anche prima della pubblicazione).
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -I -b -i <questo file>
-- Poi: tools\verifica_crlf_accenti.sql su tutto il DB (deve restituire 0 righe).
-- ============================================================ uspRifiutiRegistrazioni_get_Tracciabilita_List
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

		-- Lotti EoW (solo con modulo attivo e permesso): ultimo livello, una riga per lotto di ogni registrazione di
		-- materiale della filiera, più la quantità ancora da allocare
		DECLARE @isEoW BIT = 0;
		DECLARE @permessoEoW TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permessoEoW OUTPUT;
		IF dbo.ufnModuli_get_IsAttivoBySessione('EOW', @IdSessione) = 1 AND ISNULL(@permessoEoW, 0) >= 1
			SET @isEoW = 1;

		DECLARE @livelloLotti INT = (SELECT MAX(Livello) + 1
		FROM @nodi);

		-- Tipo: R = registrazione, L = lotto EoW, A = quantità da allocare, P = passaggio tra due righe
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
			q.IdLotto,
			IdDa = q.IdRegistrazione,
			r.Numero,
			r.[Data],
			OperazioneCodice = NULL,
			OperazioneNome = NULL,
			EerCodice = NULL,
			MaterialeNome = mat.Nome,
			StatoFisicoNome = NULL,
			q.Quantita,
			UnitaMisuraCodice = u.Codice,
			LottoNome = l.Nome,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = ROW_NUMBER() OVER (ORDER BY r.[Data], r.Numero, q.Pos, l.Nome)
		FROM
			@nodi n
			INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni q ON n.Id = q.IdRegistrazione
			INNER JOIN dbo.tblEoWLotti l ON q.IdLotto = l.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON q.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON l.IdMateriale = mat.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
		WHERE
			@isEoW = 1
			AND q.Quantita > 0
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
			UnitaMisuraCodice = NULL,
			LottoNome = NULL,
			IsCorrente = CAST(0 AS BIT),
			IsAnnullata = CAST(0 AS BIT),
			Ordine = 0
		FROM
			@passaggi p
			INNER JOIN @nodi a ON p.IdA = a.Id
			INNER JOIN @nodi d ON p.IdDa = d.Id
		WHERE a.Livello = d.Livello + 1
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
-- ============================================================ uspMagazziniMovimentiRighe_get_SediSelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_SediSelectList
	@IdMovimento CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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

		-- Sedi della stessa azienda del movimento (l'azienda stessa e le sue sedi figlie),
		-- non tutte le sedi accessibili alla sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SELECT TOP (0) Id = CAST(NULL AS CHAR(16)), [Text] = CAST(NULL AS VARCHAR(220)), Selected = CAST(0 AS BIT);
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			s.Id,
			-- Nome + indirizzo come la select delle sedi interne del contesto (uspSedi_get_SediInterne_SelectList)
			[Text] = s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''),
			Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblSedi s
		WHERE
			(s.Id = @idAzienda OR s.IdParent = @idAzienda)
			AND ISNULL(s.Disabilitata, 0) = 0
			AND (@Search IS NULL OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%')
		ORDER BY s.NomeCompleto
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
-- ============================================================ uspMagazziniDdt_get_SediSelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get_SediSelectList
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		-- Destinatario/Trasportatore possono essere qualunque anagrafica (anche esterna:
		-- clienti, fornitori, trasportatori) gestita dall'azienda interna corrente
		SELECT TOP (50)
			s.Id,
			-- Nome + indirizzo come la select delle sedi interne del contesto (uspSedi_get_SediInterne_SelectList)
			[Text] = s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''),
			Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT)
		FROM
			dbo.tblSedi s
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND ISNULL(s.Disabilitata, 0) = 0
			AND (@Search IS NULL OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%')
		ORDER BY s.NomeCompleto
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
