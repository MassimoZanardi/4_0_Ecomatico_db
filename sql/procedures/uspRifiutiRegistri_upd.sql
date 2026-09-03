SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistri_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@ControlloScadenzeAutorizzazioni BIT = 1,
	@ControlloTarghe BIT = 1,
	@ControlloConducenti BIT = 1,
	@ControlloPatenti BIT = 1,
	@ControlloAttivitaRs BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @ControlloScadenzeAutorizzazioni = ISNULL(@ControlloScadenzeAutorizzazioni, 1);
		SET @ControlloTarghe = ISNULL(@ControlloTarghe, 1);
		SET @ControlloConducenti = ISNULL(@ControlloConducenti, 1);
		SET @ControlloPatenti = ISNULL(@ControlloPatenti, 1);
		SET @ControlloAttivitaRs = ISNULL(@ControlloAttivitaRs, 1);

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
		IF @IdTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdTipo non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del registro
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblRifiutiRegistri c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro record con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro registro con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se il registro contiene registrazioni o formulari
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdTipo <> @IdTipo
				AND EXISTS ( SELECT 1 FROM dbo.tblRifiutiMovimenti m LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento WHERE m.IdRegistro = @Id AND (r.Lock < 2 OR f.Lock < 2) )
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo ad un registro con registrazioni o formulari associati';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se il registro contiene modelli
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdTipo <> @IdTipo
				AND EXISTS ( SELECT 1 FROM dbo.tblRifiutiModelli WHERE IdRegistro = @Id AND Lock < 2 )
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo ad un registro con modelli associati';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblRifiutiRegistri
			SET
				Lock = 0,
				Nome = @Nome,
				IdTipo = @IdTipo,
				ControlloScadenzeAutorizzazioni = @ControlloScadenzeAutorizzazioni,
				ControlloTarghe = @ControlloTarghe,
				ControlloConducenti = @ControlloConducenti,
				ControlloPatenti = @ControlloPatenti,
				ControlloAttivitaRs = @ControlloAttivitaRs
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registro non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
