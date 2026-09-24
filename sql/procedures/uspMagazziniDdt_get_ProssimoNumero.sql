SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get_ProssimoNumero
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
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Solo un suggerimento in UI, mai scritto su DB qui - la determinazione definitiva
		-- avviene alla conferma (uspMagazziniMovimenti_upd). Scoped su IdSede (immutabile dalla
		-- creazione) + Sezionale attualmente salvato (per un DDT nuovo è NULL).
		DECLARE @idSede CHAR(16), @sezionale CHAR(1);
		SELECT
			@idSede = d.IdSede,
			@sezionale = d.Sezionale
		FROM
			dbo.tblMagazziniDdt d
			INNER JOIN dbo.tblMagazziniMovimenti m ON d.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			d.Id = @Id
			AND e.Id = @IdSessione;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il DDT non esiste';
			GOTO BRANCH_END;
		END

		DECLARE @numero INT;
		SELECT @numero = ISNULL(MAX(Numero), 0) + 1
		FROM dbo.tblMagazziniDdt
		WHERE
			IdSede = @idSede
			AND (Sezionale = @sezionale OR (Sezionale IS NULL AND @sezionale IS NULL))
			AND Id <> @Id;

		SELECT Numero = @numero;

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
