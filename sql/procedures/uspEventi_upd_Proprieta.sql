CREATE PROCEDURE [dbo].[uspEventi_upd_Proprieta]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL,
	@Valore VARCHAR(50) = NULL
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

		-- Verifica che l'evento appartenga a un calendario/sede accessibile dalla sessione
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE e.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Evento non trovato';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblEventiProprieta
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta;

			IF @Valore IS NOT NULL
				INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				VALUES (@Id, @IdProprieta, @Valore);
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
