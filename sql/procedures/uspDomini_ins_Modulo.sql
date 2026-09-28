CREATE OR ALTER PROCEDURE [dbo].[uspDomini_ins_Modulo]
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Moduli da abilitare: quello richiesto + tutti i moduli da cui dipende
		-- (set-based: gestisce correttamente anche più moduli richiesti per lo stesso IdParent)
		DECLARE @moduli TABLE (IdModulo CHAR(3) PRIMARY KEY);
		INSERT INTO @moduli (IdModulo) VALUES (@IdModulo);
		INSERT INTO @moduli (IdModulo)
		SELECT r.Id
		FROM dbo.tblModuliRelazioni r
		WHERE
			r.IdParent = @IdModulo
			AND r.Id NOT IN (SELECT IdModulo FROM @moduli);

		BEGIN TRANSACTION;

			DELETE dm
			FROM dbo.tblDominiModuli dm
			INNER JOIN @moduli m ON dm.IdModulo = m.IdModulo
			WHERE dm.Id = @Id;

			INSERT INTO dbo.tblDominiModuli (Id, IdModulo)
			SELECT @Id, IdModulo
			FROM @moduli;

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
