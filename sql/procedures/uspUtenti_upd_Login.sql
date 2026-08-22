CREATE PROCEDURE [dbo].[uspUtenti_upd_Login]
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @dataMin SMALLDATETIME;
		SELECT TOP 1 @dataMin = [Data]
		FROM (
			SELECT [Data],
				   Pos = ROW_NUMBER() OVER (ORDER BY [Data] DESC)
			FROM dbo.tblUtentiLogin
			WHERE Id = @Id) t
		WHERE t.Pos > 9
		ORDER BY Pos;

		BEGIN TRANSACTION;

			IF NOT EXISTS (SELECT 1
			FROM dbo.tblUtentiDefault
			WHERE Id = @Id)
				INSERT INTO dbo.tblUtentiDefault (Id) VALUES (@Id);

			IF @dataMin IS NOT NULL
				DELETE dbo.tblUtentiLogin
				WHERE
					Id = @Id
					AND [Data] <= @dataMin;

			INSERT INTO dbo.tblUtentiLogin (Id, [Data])
			VALUES (@Id, GETDATE());

			-- Rimuove tutte le password temporanee dopo il login:
			-- sono generate dal sistema e casuali, non vanno incluse
			-- nello storico per il controllo di riutilizzo
			DELETE dbo.tblUtentiPassword
			WHERE
				Id = @Id
				AND Temporanea = 1;

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
