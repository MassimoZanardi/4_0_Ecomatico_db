SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 4: sedi interne usate, soggetti con le loro sedi e autorizzazioni. SP interna di
-- uspMigrazioni31_ins, eseguita dentro la sua transazione dopo uspMigrazioni31_ins_Aziende (le aziende interne di
-- #abbinamenti sono gia' migrate); legge #sedi, #soggetti, #autorizzazioni di uspMigrazioni31_get_Perimetro e scrive
-- nel #log del chiamante. In 4.0 le sedi hanno due livelli: il padre 4.0 di una sede figlia e' la sua radice.
-- 1) Sedi interne figlie non ancora migrate: create sotto la loro azienda interna 4.0.
-- 2) Soggetti: gia' migrati restano come sono; abbinati per codice fiscale o partita IVA a un soggetto dell'azienda
--    4.0 proprietaria si registrano solo nella corrispondenza (Creato = 0); gli altri si creano (tblSediEsterne con
--    l'azienda proprietaria scelta dal perimetro). La condivisione della 3.1 non si migra (in 4.0: Aree).
-- 3) Sedi figlie dei soggetti non ancora migrate: create sotto il soggetto 4.0.
-- 4) Autorizzazioni usate dalle registrazioni:
--    - "Nessuna": riusata quella attiva della sede 4.0 (la 4.0 ne tiene una per sede, come uspRifiutiRegistrazioni_upd),
--      altrimenti creata con le date 01/01/1900 - 31/12/2050 e senza numero;
--    - le altre: abbinate a un'autorizzazione della stessa sede 4.0 con lo stesso ruolo e lo stesso numero (senza
--      toccarla), altrimenti create con EER (solo quelli presenti in 4.0), attivita' (destinazioni 3.1), targhe, EER
--      esclusi per targa e conducenti. Categoria -> ruolo, tipo, NoAlbo -> tipo di numero con tblMigrazioniCodici; una
--      autorizzazione cancellata nella 3.1 ma usata da registrazioni si crea cancellata (Lock = 4).
--    Conducenti: la 3.1 chiede "Nome e Cognome" in un solo campo: prima parola = nome, il resto = cognome; una sola
--    parola va nel cognome con nome "-".
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Soggetti
	@IdMigrazione INT = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @IdMigrazione IS NULL OR @IdDominioA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdMigrazione e @IdDominioA sono obbligatori';
			GOTO BRANCH_END;
		END

		DECLARE @id CHAR(16);
		DECLARE @idSede31 CHAR(16);
		DECLARE @idParent CHAR(16);
		DECLARE @idAzienda40 CHAR(16);
		DECLARE @mappato BIT;
		DECLARE @abbinamenti INT;
		DECLARE @idSoggetto40 CHAR(16);
		DECLARE @nome VARCHAR(200);

		-- 1) Sedi interne figlie
		DECLARE ci CURSOR LOCAL FAST_FORWARD FOR
			SELECT x.Id, mr.IdDestinazione
			FROM
				#sedi x
				LEFT JOIN dbo.tblMigrazioniId mr ON mr.Versione = '31'
					AND mr.IdDominioA = @IdDominioA
					AND mr.Tabella = 'tblSedi'
					AND mr.IdOrigine = x.Radice31
			WHERE
				x.InternaEsterna = 'I'
				AND x.Id <> x.Radice31
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId ms WHERE ms.Versione = '31' AND ms.IdDominioA = @IdDominioA AND ms.Tabella = 'tblSedi' AND ms.IdOrigine = x.Id)
			ORDER BY x.Id;

		OPEN ci;
		FETCH ci INTO @idSede31, @idParent;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @idParent IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Sede interna ', @idSede31, ': azienda interna non migrata');
				GOTO BRANCH_END;
			END

			EXEC dbo.uspMigrazioni31_ins_Sede
				@IdMigrazione = @IdMigrazione,
				@IdDominioA = @IdDominioA,
				@IdSede31 = @idSede31,
				@IdParent = @idParent,
				@InternaEsterna = 'I',
				@Id = @id OUTPUT;

			FETCH ci INTO @idSede31, @idParent;
		END

		CLOSE ci;
		DEALLOCATE ci;

		-- 2) Soggetti
		DECLARE cg CURSOR LOCAL FAST_FORWARD FOR
			SELECT g.IdSoggetto31, g.Mappato, g.Abbinamenti, g.IdSoggetto40, mp.IdDestinazione
			FROM
				#soggetti g
				LEFT JOIN dbo.tblMigrazioniId mp ON mp.Versione = '31'
					AND mp.IdDominioA = @IdDominioA
					AND mp.Tabella = 'tblSedi'
					AND mp.IdOrigine = g.IdProprietario31
			ORDER BY g.IdSoggetto31;

		OPEN cg;
		FETCH cg INTO @idSede31, @mappato, @abbinamenti, @idSoggetto40, @idAzienda40;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @nome = (SELECT COALESCE(Cognome + ' ' + Nome, Nome)
			FROM dbo.syn31Sedi
			WHERE IDSede = @idSede31);

			IF @mappato = 1
			BEGIN
				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
				VALUES ('Soggetti', 'I', 'tblSedi', @idSede31, CONCAT('Soggetto ', @nome, ' gia'' migrato in ', @idSoggetto40));
			END
			ELSE IF @abbinamenti = 1
			BEGIN
				SET @id = @idSoggetto40;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblSedi',
					@IdOrigine = @idSede31,
					@IdMigrazione = @IdMigrazione,
					@Id = @id OUTPUT;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				SELECT 'Soggetti', 'I', 'tblSedi', @idSede31, 0, CONCAT('Soggetto ', @nome, ' abbinato a ', s.NomeCompleto, ' (', s.Id, ')')
				FROM dbo.tblSedi s
				WHERE s.Id = @idSoggetto40;
			END
			ELSE IF @abbinamenti = 0
			BEGIN
				IF @idAzienda40 IS NULL
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = CONCAT('Soggetto ', @nome, ': azienda proprietaria non migrata');
					GOTO BRANCH_END;
				END

				EXEC dbo.uspMigrazioni31_ins_Sede
					@IdMigrazione = @IdMigrazione,
					@IdDominioA = @IdDominioA,
					@IdSede31 = @idSede31,
					@IdParent = NULL,
					@InternaEsterna = 'E',
					@IdAziendaInterna = @idAzienda40,
					@Id = @id OUTPUT;
			END
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Il soggetto ', @nome, ' ha piu'' abbinamenti nella 4.0');
				GOTO BRANCH_END;
			END

			FETCH cg INTO @idSede31, @mappato, @abbinamenti, @idSoggetto40, @idAzienda40;
		END

		CLOSE cg;
		DEALLOCATE cg;

		-- 3) Sedi figlie dei soggetti
		DECLARE ce CURSOR LOCAL FAST_FORWARD FOR
			SELECT x.Id, mr.IdDestinazione
			FROM
				#sedi x
				LEFT JOIN dbo.tblMigrazioniId mr ON mr.Versione = '31'
					AND mr.IdDominioA = @IdDominioA
					AND mr.Tabella = 'tblSedi'
					AND mr.IdOrigine = x.Radice31
			WHERE
				x.InternaEsterna = 'E'
				AND x.Id <> x.Radice31
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId ms WHERE ms.Versione = '31' AND ms.IdDominioA = @IdDominioA AND ms.Tabella = 'tblSedi' AND ms.IdOrigine = x.Id)
			ORDER BY x.Id;

		OPEN ce;
		FETCH ce INTO @idSede31, @idParent;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @idParent IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Sede esterna ', @idSede31, ': soggetto non migrato');
				GOTO BRANCH_END;
			END

			EXEC dbo.uspMigrazioni31_ins_Sede
				@IdMigrazione = @IdMigrazione,
				@IdDominioA = @IdDominioA,
				@IdSede31 = @idSede31,
				@IdParent = @idParent,
				@InternaEsterna = 'E',
				@Id = @id OUTPUT;

			FETCH ce INTO @idSede31, @idParent;
		END

		CLOSE ce;
		DEALLOCATE ce;

		-- 4) Autorizzazioni
		DECLARE @idAutorizzazione31 CHAR(16);
		DECLARE @idSede40 CHAR(16);
		DECLARE @creata BIT;
		DECLARE @nessuna BIT;
		DECLARE @idRuolo CHAR(1);
		DECLARE @idTipo CHAR(1);
		DECLARE @idNumeroTipo CHAR(1);
		DECLARE @numero VARCHAR(50);
		DECLARE @identificativo VARCHAR(50);
		DECLARE @dataInizio DATE;
		DECLARE @dataFine DATE;
		DECLARE @note VARCHAR(500);
		DECLARE @disabilitata BIT;
		DECLARE @lock TINYINT;
		DECLARE @dataInserimento DATETIME2(0);
		DECLARE @categoria31 CHAR(1);

		DECLARE ca CURSOR LOCAL FAST_FORWARD FOR
			SELECT
				a.IDAutorizzazione,
				ms.IdDestinazione,
				ISNULL(a.Nessuna, 0),
				a.IDCategoria,
				kr.CodiceDestinazione,
				kt.CodiceDestinazione,
				kn.CodiceDestinazione,
				NULLIF(LTRIM(RTRIM(a.Numero)), ''),
				NULLIF(LTRIM(RTRIM(a.Identificativo)), ''),
				a.DataInizio,
				a.DataFine,
				NULLIF(LTRIM(RTRIM(a.Note)), ''),
				ISNULL(a.Disabilitata, 0),
				IIF(ISNULL(a.Lock, 0) = 0, 0, 4),
				x.DataInserimento
			FROM
				#autorizzazioni z
				INNER JOIN dbo.syn31RifiutiAutorizzazioni a ON z.Id = a.IDAutorizzazione COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.syn31ID x ON a.IDAutorizzazione = x.ID
				LEFT JOIN dbo.tblMigrazioniId ms ON ms.Versione = '31'
					AND ms.IdDominioA = @IdDominioA
					AND ms.Tabella = 'tblSedi'
					AND ms.IdOrigine = a.IDSede COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.tblMigrazioniCodici kr ON kr.Versione = '31'
					AND kr.Tabella = 'tblRifiutiRuoli'
					AND kr.CodiceOrigine = a.IDCategoria COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.tblMigrazioniCodici kt ON kt.Versione = '31'
					AND kt.Tabella = 'tblRifiutiAutorizzazioniTipi'
					AND kt.CodiceOrigine = a.IDTipo COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.tblMigrazioniCodici kn ON kn.Versione = '31'
					AND kn.Tabella = 'tblRifiutiAutorizzazioniNumeriTipi'
					AND kn.CodiceOrigine = CONVERT(VARCHAR(20), CONVERT(TINYINT, a.NoAlbo))
			WHERE NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mz WHERE mz.Versione = '31' AND mz.IdDominioA = @IdDominioA AND mz.Tabella = 'tblRifiutiAutorizzazioni' AND mz.IdOrigine = z.Id)
			ORDER BY z.Id;

		OPEN ca;
		FETCH ca INTO @idAutorizzazione31, @idSede40, @nessuna, @categoria31, @idRuolo, @idTipo, @idNumeroTipo, @numero, @identificativo, @dataInizio, @dataFine, @note, @disabilitata, @lock, @dataInserimento;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @idSede40 IS NULL OR @idRuolo IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Autorizzazione ', @idAutorizzazione31, ': sede non migrata o categoria ', ISNULL(@categoria31, '(vuota)'), ' non mappata');
				GOTO BRANCH_END;
			END

			-- Autorizzazione 4.0 esistente da riusare
			SET @id = NULL;

			IF @nessuna = 1
				SELECT TOP (1) @id = Id
				FROM dbo.tblRifiutiAutorizzazioni
				WHERE
					IdSede = @idSede40
					AND Nessuna = 1
					AND Lock = 0
				ORDER BY Id;
			ELSE IF @numero IS NOT NULL
				SELECT TOP (1) @id = Id
				FROM dbo.tblRifiutiAutorizzazioni
				WHERE
					IdSede = @idSede40
					AND IdRuolo = @idRuolo
					AND ISNULL(Nessuna, 0) = 0
					AND Lock < 2
					AND UPPER(LTRIM(RTRIM(Numero))) = UPPER(@numero)
				ORDER BY Lock, Id;

			SET @creata = IIF(@id IS NULL, 1, 0);

			EXEC dbo.uspMigrazioniId_ins
				@Versione = '31',
				@IdDominioA = @IdDominioA,
				@Tabella = 'tblRifiutiAutorizzazioni',
				@IdOrigine = @idAutorizzazione31,
				@IdMigrazione = @IdMigrazione,
				@DataInserimento = @dataInserimento,
				@Id = @id OUTPUT;

			IF @creata = 0
			BEGIN
				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('Autorizzazioni', 'I', 'tblRifiutiAutorizzazioni', @idAutorizzazione31, 0,
					CONCAT(IIF(@nessuna = 1, 'Autorizzazione "Nessuna" riusata: ', CONCAT('Autorizzazione ', @numero, ' abbinata a ')), @id));
			END
			ELSE IF @nessuna = 1
			BEGIN
				INSERT INTO dbo.tblRifiutiAutorizzazioni (Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
				VALUES (@id, @idSede40, @idRuolo, '19000101', '20501231', 1, 0, 0);

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('Autorizzazioni', 'I', 'tblRifiutiAutorizzazioni', @idAutorizzazione31, 1, CONCAT('Creata l''autorizzazione "Nessuna" ', @id));
			END
			ELSE
			BEGIN
				INSERT INTO dbo.tblRifiutiAutorizzazioni
					(Id, IdSede, IdRuolo, IdTipo, IdNumeroTipo, Numero, Identificativo, DataInizio, DataFine, Note, Nessuna, Disabilitata, Lock)
				VALUES
					(@id, @idSede40, @idRuolo, @idTipo, @idNumeroTipo, @numero, @identificativo, @dataInizio, @dataFine, @note, 0, @disabilitata, @lock);

				INSERT INTO dbo.tblRifiutiAutorizzazioniEer (Id, IdEer)
				SELECT DISTINCT @id, e.Id
				FROM
					dbo.syn31RifiutiAutorizzazioniCER c
					INNER JOIN dbo.tblRifiutiEer e ON c.IDCER = e.Id COLLATE DATABASE_DEFAULT
				WHERE c.IDAutorizzazione = @idAutorizzazione31;

				INSERT INTO dbo.tblRifiutiAutorizzazioniAttivita (Id, IdAttivita)
				SELECT DISTINCT @id, k.CodiceDestinazione
				FROM
					dbo.syn31RifiutiAutorizzazioniDestinazioni d
					INNER JOIN dbo.tblMigrazioniCodici k ON k.Versione = '31'
						AND k.Tabella = 'tblRifiutiAttivitaRecuperoSmaltimento'
						AND k.CodiceOrigine = d.IDDestinazione COLLATE DATABASE_DEFAULT
				WHERE
					d.IDAutorizzazione = @idAutorizzazione31
					AND k.CodiceDestinazione IS NOT NULL;

				INSERT INTO dbo.tblRifiutiAutorizzazioniTarghe (Id, Targa, Rimorchio)
				SELECT @id, t.Targa, MAX(CONVERT(TINYINT, ISNULL(t.Rimorchio, 0)))
				FROM dbo.syn31RifiutiAutorizzazioniTarghe t
				WHERE t.IDAutorizzazione = @idAutorizzazione31
				GROUP BY t.Targa;

				INSERT INTO dbo.tblRifiutiAutorizzazioniTargheEerEsclusi (Id, Targa, IdEer)
				SELECT DISTINCT @id, x.Targa, e.Id
				FROM
					dbo.syn31RifiutiAutorizzazioniTargheCEREsclusi x
					INNER JOIN dbo.tblRifiutiEer e ON x.IDCER = e.Id COLLATE DATABASE_DEFAULT
				WHERE
					x.IDAutorizzazione = @idAutorizzazione31
					AND EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniTarghe t WHERE t.Id = @id AND t.Targa = x.Targa COLLATE DATABASE_DEFAULT);

				-- Conducenti: prima parola = nome, il resto = cognome
				INSERT INTO dbo.tblRifiutiAutorizzazioniConducenti (Id, Nome, Cognome, ScadenzaPatente, ScadenzaPatenteAdr)
				SELECT @id, n.Nome, n.Cognome, MAX(c.ScadenzaPatente), MAX(c.ScadenzaPatenteADR)
				FROM
					dbo.syn31RifiutiAutorizzazioniConducenti c
					CROSS APPLY (SELECT Testo = LTRIM(RTRIM(c.Nome))) t
					CROSS APPLY (SELECT
						Nome = CONVERT(VARCHAR(50), IIF(CHARINDEX(' ', t.Testo) = 0, '-', LEFT(t.Testo, CHARINDEX(' ', t.Testo) - 1))),
						Cognome = CONVERT(VARCHAR(50), IIF(CHARINDEX(' ', t.Testo) = 0, t.Testo, LTRIM(SUBSTRING(t.Testo, CHARINDEX(' ', t.Testo) + 1, 100))))) n
				WHERE
					c.IDAutorizzazione = @idAutorizzazione31
					AND t.Testo <> ''
				GROUP BY n.Nome, n.Cognome;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('Autorizzazioni', 'I', 'tblRifiutiAutorizzazioni', @idAutorizzazione31, 1,
					CONCAT('Creata l''autorizzazione ', ISNULL(@numero, '(senza numero)'), ' ', @id, IIF(@lock = 4, ' (cancellata nella 3.1)', '')));
			END

			FETCH ca INTO @idAutorizzazione31, @idSede40, @nessuna, @categoria31, @idRuolo, @idTipo, @idNumeroTipo, @numero, @identificativo, @dataInizio, @dataFine, @note, @disabilitata, @lock, @dataInserimento;
		END

		CLOSE ca;
		DEALLOCATE ca;
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
