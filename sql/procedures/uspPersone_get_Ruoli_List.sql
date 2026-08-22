CREATE PROCEDURE [dbo].[uspPersone_get_Ruoli_List]
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);

		-- Stessa titolarità di uspPersone_get: azienda interna dell'utente OPPURE
		-- persona condivisa da un'altra azienda via Area.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblPersone p
			INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@idUtente) i
					   ON p.IdSede = i.Id
			WHERE p.Id = @Id)
		AND NOT EXISTS (
			SELECT 1
			FROM dbo.ufnPersone_get_CondiviseByUtente_List(@idUtente) c
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.Nome,
			p.DataInizio,
			p.DataFine
		FROM
			dbo.tblPersoneRuoli p
		INNER JOIN dbo.tblRuoli r ON p.IdRuolo = r.Id
		WHERE p.Id = @Id
		ORDER BY
			p.DataInizio DESC;

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
