CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_ins]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @IdDominio CHAR(16);
		SELECT @IdDominio = IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;
		IF @IdDominio IS NULL OR @IdDominio = REPLICATE('0', 16)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il dominio';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'UTE',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id = @IdDominio
				AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile inserire utenti nel dominio Master';
			GOTO BRANCH_END;
		END
		DECLARE @UtentiMax INT;
		DECLARE @UtentiAttuali INT;
		SELECT
			@UtentiMax = UtentiMax,
			@UtentiAttuali = (
				SELECT COUNT(*)
				FROM dbo.tblUtenti
				WHERE
					IdDominio = @IdDominio
					AND [Master] = 0
					AND Lock = 0
			)
		FROM dbo.tblDomini WITH (UPDLOCK)
		WHERE Id = @IdDominio;
		IF @UtentiMax <= @UtentiAttuali
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'È stato raggiunto il numero massimo di utenti inseribili';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;
		IF @returnId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impossibile generare un Id univoco';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblUtenti
				(Id, IdDominio, IdRuolo, IdStato, Email, Scadenza, [Master], Lock)
			VALUES
				(@returnId, @IdDominio, 'US', 'AT', NULL, DATEADD(YEAR, 3, GETDATE()), 0, 2);
			INSERT INTO dbo.tblUtentiDefault (Id) VALUES (@returnId);
		COMMIT TRANSACTION;
		SELECT @returnId AS Id,
			   @returnValue AS ReturnValue;
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
