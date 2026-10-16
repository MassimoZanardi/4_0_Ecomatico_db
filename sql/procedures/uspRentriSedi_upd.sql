SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_upd]
	@IdSede CHAR(16) = NULL,
	@IdCredenzialePrimaria CHAR(16) = NULL,
	@IdCredenzialeSecondaria CHAR(16) = NULL,
	@IdentificativoSede VARCHAR(30) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdCredenzialePrimaria = NULLIF(LTRIM(RTRIM(@IdCredenzialePrimaria)), '');
		SET @IdCredenzialeSecondaria = NULLIF(LTRIM(RTRIM(@IdCredenzialeSecondaria)), '');
		SET @IdentificativoSede = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@IdentificativoSede, 0, 1));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdCredenzialePrimaria = @idSediciZeri SET @IdCredenzialePrimaria = NULL;
		IF @IdCredenzialeSecondaria = @idSediciZeri SET @IdCredenzialeSecondaria = NULL;

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenzialePrimaria IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la credenziale primaria';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenzialeSecondaria IS NOT NULL AND @IdCredenzialeSecondaria = @IdCredenzialePrimaria
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale secondaria deve essere diversa dalla primaria';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla sede + dominio della sede
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
		WHERE i.Id = @IdSede;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La credenziale deve appartenere allo stesso dominio, essere attiva e già collegata all'hub
		DECLARE @idRentriPrimaria CHAR(16), @accreditamentoPrimaria CHAR(1);
		SELECT
			@idRentriPrimaria = IdRentri,
			@accreditamentoPrimaria = IdAccreditamento
		FROM dbo.tblRentriCredenziali
		WHERE
			Id = @IdCredenzialePrimaria
			AND IdDominio = @idDominio
			AND Lock = 0;

		IF @idRentriPrimaria IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale primaria selezionata non è valida';
			GOTO BRANCH_END;
		END

		DECLARE @idRentriSecondaria CHAR(16), @accreditamentoSecondaria CHAR(1);
		IF @IdCredenzialeSecondaria IS NOT NULL
		BEGIN
			SELECT
				@idRentriSecondaria = IdRentri,
				@accreditamentoSecondaria = IdAccreditamento
			FROM dbo.tblRentriCredenziali
			WHERE
				Id = @IdCredenzialeSecondaria
				AND IdDominio = @idDominio
				AND Lock = 0;

			IF @idRentriSecondaria IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale secondaria selezionata non è valida';
				GOTO BRANCH_END;
			END

			-- La seconda credenziale serve solo alle associazioni di categoria: la credenziale da
			-- Delegato per le API che prevedono l'accreditamento, quella da Operatore del cliente per
			-- le altre (formulari digitali). Ogni altra coppia non ha senso.
			IF NOT (
				(ISNULL(@accreditamentoPrimaria, '') = 'D' AND ISNULL(@accreditamentoSecondaria, '') = 'O')
				OR (ISNULL(@accreditamentoPrimaria, '') = 'O' AND ISNULL(@accreditamentoSecondaria, '') = 'D')
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Due credenziali si associano solo se una è da Delegato e l''altra da Operatore';
				GOTO BRANCH_END;
			END
		END

		-- La credenziale con accreditamento Delegato è sempre la primaria (Pos=0), indipendentemente dallo slot scelto in UI.
		-- L'Identificativo Sede (dato reale, digitato dall'utente) va sempre sulla riga hub di Pos=0;
		-- la riga hub di Pos=1 (se presente) è un dettaglio tecnico dell'hub, mai mostrato, valorizzato a caso.
		DECLARE @idCredenzialePos0 CHAR(16) = @IdCredenzialePrimaria;
		DECLARE @idRentriCredPos0 CHAR(16) = @idRentriPrimaria;
		DECLARE @idCredenzialePos1 CHAR(16) = @IdCredenzialeSecondaria;
		DECLARE @idRentriCredPos1 CHAR(16) = @idRentriSecondaria;

		IF @IdCredenzialeSecondaria IS NOT NULL AND ISNULL(@accreditamentoSecondaria, '') = 'D' AND ISNULL(@accreditamentoPrimaria, '') <> 'D'
		BEGIN
			SET @idCredenzialePos0 = @IdCredenzialeSecondaria;
			SET @idRentriCredPos0 = @idRentriSecondaria;
			SET @idCredenzialePos1 = @IdCredenzialePrimaria;
			SET @idRentriCredPos1 = @idRentriPrimaria;
		END

		BEGIN TRANSACTION;

			-- Collegamento hub tra la sede da Delegato e la credenziale da Operatore del cliente
			-- (tblSediOperatori): si toglie qui e si riscrive in fondo dalle posizioni finali
			DELETE [1_0_rentri]..tblSediOperatori
			WHERE Id COLLATE DATABASE_DEFAULT IN (
				SELECT rcs.IdRentri COLLATE DATABASE_DEFAULT
				FROM dbo.tblRentriCredenzialiSedi rcs
				WHERE rcs.IdSede = @IdSede
			);

			-- Rimuove le associazioni esistenti non più presenti nelle 2 posizioni finali
			DELETE [1_0_rentri]..tblSedi
			WHERE Id COLLATE DATABASE_DEFAULT IN (
				SELECT rcs.IdRentri COLLATE DATABASE_DEFAULT
				FROM dbo.tblRentriCredenzialiSedi rcs
				WHERE
					rcs.IdSede = @IdSede
					AND rcs.IdCredenziale <> @idCredenzialePos0
					AND (@idCredenzialePos1 IS NULL OR rcs.IdCredenziale <> @idCredenzialePos1)
			);

			DELETE dbo.tblRentriCredenzialiSedi
			WHERE
				IdSede = @IdSede
				AND IdCredenziale <> @idCredenzialePos0
				AND (@idCredenzialePos1 IS NULL OR IdCredenziale <> @idCredenzialePos1);

			-- Posizione 0 (primaria effettiva): l'Identificativo Sede va sempre aggiornato qui
			IF EXISTS (SELECT 1 FROM dbo.tblRentriCredenzialiSedi WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos0)
			BEGIN
				UPDATE dbo.tblRentriCredenzialiSedi
				SET Pos = 0
				WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos0;

				UPDATE h
				SET Identificativo = @IdentificativoSede
				FROM [1_0_rentri]..tblSedi h
				INNER JOIN dbo.tblRentriCredenzialiSedi rcs ON h.Id COLLATE DATABASE_DEFAULT = rcs.IdRentri COLLATE DATABASE_DEFAULT
				WHERE rcs.IdSede = @IdSede AND rcs.IdCredenziale = @idCredenzialePos0;
			END
			ELSE
			BEGIN
				DECLARE @idRentriAssocPos0 CHAR(16) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

				INSERT INTO [1_0_rentri]..tblSedi (Id, IdCredenziale, Identificativo)
				VALUES (@idRentriAssocPos0, @idRentriCredPos0, @IdentificativoSede);

				INSERT INTO dbo.tblRentriCredenzialiSedi (IdSede, IdCredenziale, IdRentri, Pos)
				VALUES (@IdSede, @idCredenzialePos0, @idRentriAssocPos0, 0);
			END

			-- Posizione 1 (secondaria effettiva, opzionale): l'Identificativo hub è un dettaglio tecnico,
			-- generato una sola volta alla creazione e mai più toccato/mostrato
			IF @idCredenzialePos1 IS NOT NULL
			BEGIN
				IF EXISTS (SELECT 1 FROM dbo.tblRentriCredenzialiSedi WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos1)
				BEGIN
					UPDATE dbo.tblRentriCredenzialiSedi
					SET Pos = 1
					WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos1;
				END
				ELSE
				BEGIN
					DECLARE @idRentriAssocPos1 CHAR(16) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
					DECLARE @identificativoTecnicoPos1 VARCHAR(30) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

					INSERT INTO [1_0_rentri]..tblSedi (Id, IdCredenziale, Identificativo)
					VALUES (@idRentriAssocPos1, @idRentriCredPos1, @identificativoTecnicoPos1);

					INSERT INTO dbo.tblRentriCredenzialiSedi (IdSede, IdCredenziale, IdRentri, Pos)
					VALUES (@IdSede, @idCredenzialePos1, @idRentriAssocPos1, 1);
				END

				-- Con due credenziali la posizione 0 è sempre da Delegato e la 1 da Operatore:
				-- l'hub usa la seconda per i formulari digitali (uspConnector_get_ByRegistro_Operatore)
				INSERT INTO [1_0_rentri]..tblSediOperatori (Id, IdCredenziale)
				SELECT rcs.IdRentri, @idRentriCredPos1
				FROM dbo.tblRentriCredenzialiSedi rcs
				WHERE rcs.IdSede = @IdSede AND rcs.IdCredenziale = @idCredenzialePos0;
			END

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
