CREATE OR ALTER PROCEDURE [dbo].[uspTipi_upd_ProprietaPosizione]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL,
	@Verso INT = NULL -- +1=Su -1=Giù
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');
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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Verso IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Verso non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		-- Legge la posizione corrente FUORI dalla transazione
		DECLARE @pos INT = (
			SELECT Pos
			FROM dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta
		);
		DECLARE @mosso INT = 0;
		BEGIN TRANSACTION;
			IF @Verso > 0 AND @pos > 0
			BEGIN
				-- Sposta in su: scambia con quella precedente
				UPDATE dbo.tblTipiProprieta
				SET Pos = Pos + 1
				WHERE
					Id = @Id
					AND Pos = @pos - 1
					AND Lock <= 2;
				UPDATE dbo.tblTipiProprieta
				SET Pos = Pos - 1
				WHERE
					Id = @Id
					AND IdProprieta = @IdProprieta
					AND Lock <= 2;
				SET @mosso = 1;
			END
			ELSE IF @Verso < 0 AND @pos < (
				SELECT MAX(Pos)
				FROM dbo.tblTipiProprieta
				WHERE
					Id = @Id
					AND Lock = 0
			)
			BEGIN
				-- Sposta in giù: scambia con quella successiva
				UPDATE dbo.tblTipiProprieta
				SET Pos = Pos - 1
				WHERE
					Id = @Id
					AND Pos = @pos + 1
					AND Lock <= 2;
				UPDATE dbo.tblTipiProprieta
				SET Pos = Pos + 1
				WHERE
					Id = @Id
					AND IdProprieta = @IdProprieta
					AND Lock <= 2;
				SET @mosso = 1;
			END
		COMMIT TRANSACTION;
		-- Log FUORI dalla transazione solo se è stato effettivamente spostato
		IF @mosso = 1
		BEGIN
			EXEC dbo.uspId_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@Operazione = 'U';
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
		THROW 50001, @returnMessage, 1
	END
END;
