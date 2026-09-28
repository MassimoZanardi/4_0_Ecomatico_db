CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_ins]
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idCalendario CHAR(16);
		SELECT @idCalendario = s.IdCalendario
		FROM dbo.tblSessioni s
		INNER JOIN dbo.tblCalendari c ON s.IdCalendario = c.Id
										   AND c.IdModulo = 'SRV'
		WHERE s.Id = @IdSessione;

		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END

		DECLARE @returnIdEvento CHAR(16) = NULL;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			INSERT INTO dbo.tblEventi
				(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Lock)
			VALUES
				(@returnIdEvento, @idCalendario, 'D', 'V', NULL, 0, 0, 2);

			INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo)
			VALUES (@returnId, @returnIdEvento, @IdTipo);

			INSERT INTO dbo.tblEventiUtenti (Id, IdUtente)
			SELECT @returnIdEvento, IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;

		COMMIT TRANSACTION;

		SELECT @returnId AS Id;

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
