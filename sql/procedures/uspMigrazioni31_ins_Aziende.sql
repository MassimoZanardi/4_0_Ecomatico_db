SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 3: aziende interne, sedi dei registri e registri. SP interna di
-- uspMigrazioni31_ins, eseguita dentro la sua transazione; legge #abbinamenti e #registri calcolati da
-- uspMigrazioni31_get_Perimetro e scrive nel #log del chiamante.
-- 1) Aziende interne: gia' migrate (tblMigrazioniId) restano come sono; abbinate per codice fiscale o partita IVA a
--    un'azienda del dominio 4.0 si registrano solo nella corrispondenza (Creato = 0, l'azienda 4.0 non si modifica);
--    le altre si creano (uspMigrazioni31_ins_Sede). Piu' abbinamenti bloccano gia' la verifica.
-- 2) Sedi dei registri diverse dalla loro azienda (unita' locali): create come sedi figlie dell'azienda 4.0.
-- 3) Registri: sempre nuovi, mai abbinati a registri esistenti. Nome obbligatorio e unico nella sede come in
--    uspRifiutiRegistri_upd: senza nome "Registro", con un nome gia' presente nella sede si aggiunge " (2)", " (3)"...
--    Controlli: ControlloAutorizzazioni 3.1 -> ControlloScadenzeAutorizzazioni, targhe e conducenti invariati,
--    patenti e attivita' R/D spenti (non esistono nella 3.1). Il collegamento al RENTRI non si migra.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Aziende
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

		DECLARE @idAzienda31 CHAR(16);
		DECLARE @mappata BIT;
		DECLARE @abbinamenti INT;
		DECLARE @idAzienda40 CHAR(16);
		DECLARE @id CHAR(16);
		DECLARE @nome VARCHAR(200);

		-- 1) Aziende interne
		DECLARE ca CURSOR LOCAL FAST_FORWARD FOR
			SELECT IdAzienda31, Mappata, Abbinamenti, IdAzienda40
			FROM #abbinamenti
			ORDER BY IdAzienda31;

		OPEN ca;
		FETCH ca INTO @idAzienda31, @mappata, @abbinamenti, @idAzienda40;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @nome = (SELECT Nome
			FROM dbo.syn31Sedi
			WHERE IDSede = @idAzienda31);

			IF @mappata = 1
			BEGIN
				IF NOT EXISTS (SELECT 1
				FROM
					dbo.tblSedi s
					INNER JOIN dbo.tblSediInterne i ON s.Id = i.Id
				WHERE
					s.Id = @idAzienda40
					AND i.IdDominio = @IdDominioA
					AND s.Lock < 2
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = CONCAT('L''azienda ', @nome, ' e'' gia'' stata migrata ma l''azienda 4.0 non e'' piu'' attiva');
					GOTO BRANCH_END;
				END

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
				VALUES ('Aziende', 'I', 'tblSedi', @idAzienda31, CONCAT('Azienda interna ', @nome, ' gia'' migrata in ', @idAzienda40));
			END
			ELSE IF @abbinamenti = 1
			BEGIN
				SET @id = @idAzienda40;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblSedi',
					@IdOrigine = @idAzienda31,
					@IdMigrazione = @IdMigrazione,
					@Id = @id OUTPUT;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				SELECT 'Aziende', 'I', 'tblSedi', @idAzienda31, 0, CONCAT('Azienda interna ', @nome, ' abbinata a ', s.Nome, ' (', s.Id, ')')
				FROM dbo.tblSedi s
				WHERE s.Id = @idAzienda40;
			END
			ELSE IF @abbinamenti = 0
			BEGIN
				EXEC dbo.uspMigrazioni31_ins_Sede
					@IdMigrazione = @IdMigrazione,
					@IdDominioA = @IdDominioA,
					@IdSede31 = @idAzienda31,
					@IdParent = NULL,
					@InternaEsterna = 'I',
					@Id = @id OUTPUT;
			END
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('L''azienda ', @nome, ' ha piu'' abbinamenti nella 4.0');
				GOTO BRANCH_END;
			END

			FETCH ca INTO @idAzienda31, @mappata, @abbinamenti, @idAzienda40;
		END

		CLOSE ca;
		DEALLOCATE ca;

		-- 2) Sedi dei registri diverse dalla loro azienda
		DECLARE @idSede31 CHAR(16);
		DECLARE @idParent CHAR(16);

		DECLARE cs CURSOR LOCAL FAST_FORWARD FOR
			SELECT DISTINCT g.IdSede, mi.IdDestinazione
			FROM
				#registri g
				INNER JOIN dbo.tblMigrazioniId mi ON mi.Versione = '31'
					AND mi.IdDominioA = @IdDominioA
					AND mi.Tabella = 'tblSedi'
					AND mi.IdOrigine = g.IdAzienda
			WHERE
				g.IdSede <> g.IdAzienda
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId ms WHERE ms.Versione = '31' AND ms.IdDominioA = @IdDominioA AND ms.Tabella = 'tblSedi' AND ms.IdOrigine = g.IdSede);

		OPEN cs;
		FETCH cs INTO @idSede31, @idParent;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXEC dbo.uspMigrazioni31_ins_Sede
				@IdMigrazione = @IdMigrazione,
				@IdDominioA = @IdDominioA,
				@IdSede31 = @idSede31,
				@IdParent = @idParent,
				@InternaEsterna = 'I',
				@Id = @id OUTPUT;

			FETCH cs INTO @idSede31, @idParent;
		END

		CLOSE cs;
		DEALLOCATE cs;

		-- 3) Registri
		DECLARE @idRegistro31 CHAR(16);
		DECLARE @idSede40 CHAR(16);
		DECLARE @idTipo CHAR(1);
		DECLARE @nomeBase VARCHAR(50);
		DECLARE @nomeRegistro VARCHAR(50);
		DECLARE @progressivo INT;
		DECLARE @controlloAutorizzazioni BIT;
		DECLARE @controlloTarghe BIT;
		DECLARE @controlloConducenti BIT;
		DECLARE @dataInserimento DATETIME2(0);

		DECLARE cr CURSOR LOCAL FAST_FORWARD FOR
			SELECT
				g.Id,
				ms.IdDestinazione,
				k.CodiceDestinazione,
				ISNULL(NULLIF(LTRIM(RTRIM(rg.Nome)), ''), 'Registro'),
				ISNULL(rg.ControlloAutorizzazioni, 0),
				ISNULL(rg.ControlloTarghe, 0),
				ISNULL(rg.ControlloConducenti, 0),
				x.DataInserimento
			FROM
				#registri g
				INNER JOIN dbo.syn31RifiutiRegistri rg ON g.Id = rg.IDRegistro COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.syn31ID x ON rg.IDRegistro = x.ID
				LEFT JOIN dbo.tblMigrazioniId ms ON ms.Versione = '31'
					AND ms.IdDominioA = @IdDominioA
					AND ms.Tabella = 'tblSedi'
					AND ms.IdOrigine = g.IdSede
				LEFT JOIN dbo.tblMigrazioniCodici k ON k.Versione = '31'
					AND k.Tabella = 'tblRifiutiRegistriTipi'
					AND k.CodiceOrigine = g.IdTipo
			WHERE NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mr WHERE mr.Versione = '31' AND mr.IdDominioA = @IdDominioA AND mr.Tabella = 'tblRifiutiRegistri' AND mr.IdOrigine = g.Id)
			ORDER BY g.Id;

		OPEN cr;
		FETCH cr INTO @idRegistro31, @idSede40, @idTipo, @nomeBase, @controlloAutorizzazioni, @controlloTarghe, @controlloConducenti, @dataInserimento;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @idSede40 IS NULL OR @idTipo IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Registro ', @idRegistro31, ': sede non migrata o tipo non mappato');
				GOTO BRANCH_END;
			END

			-- Nome unico nella sede (registri attivi), come uspRifiutiRegistri_upd
			SET @nomeRegistro = @nomeBase;
			SET @progressivo = 1;

			WHILE EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				IdSede = @idSede40
				AND Lock = 0
				AND Nome = @nomeRegistro
			)
			BEGIN
				SET @progressivo += 1;
				SET @nomeRegistro = CONCAT(LEFT(@nomeBase, 50 - LEN(CONCAT(' (', @progressivo, ')'))), ' (', @progressivo, ')');
			END

			SET @id = NULL;

			EXEC dbo.uspMigrazioniId_ins
				@Versione = '31',
				@IdDominioA = @IdDominioA,
				@Tabella = 'tblRifiutiRegistri',
				@IdOrigine = @idRegistro31,
				@IdMigrazione = @IdMigrazione,
				@DataInserimento = @dataInserimento,
				@Id = @id OUTPUT;

			INSERT INTO dbo.tblRifiutiRegistri
				(Id, IdSede, IdTipo, Nome, ControlloScadenzeAutorizzazioni, ControlloTarghe, ControlloConducenti, ControlloPatenti, ControlloAttivitaRs, Lock)
			VALUES
				(@id, @idSede40, @idTipo, @nomeRegistro, @controlloAutorizzazioni, @controlloTarghe, @controlloConducenti, 0, 0, 0);

			INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
			VALUES ('Registri', IIF(@nomeRegistro = @nomeBase, 'I', 'W'), 'tblRifiutiRegistri', @idRegistro31, 1,
				CONCAT('Creato il registro ', @id, ' "', @nomeRegistro, '"', IIF(@nomeRegistro = @nomeBase, '', ' (nome gia'' presente nella sede)')));

			FETCH cr INTO @idRegistro31, @idSede40, @idTipo, @nomeBase, @controlloAutorizzazioni, @controlloTarghe, @controlloConducenti, @dataInserimento;
		END

		CLOSE cr;
		DEALLOCATE cr;
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
