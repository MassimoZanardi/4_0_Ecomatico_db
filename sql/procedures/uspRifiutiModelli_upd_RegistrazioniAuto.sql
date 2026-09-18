SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_upd_RegistrazioniAuto]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Percentuale INT = NULL,
	@IdEer CHAR(6) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

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
		IF @Percentuale IS NULL OR @Percentuale <= 0 OR @Percentuale > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere compresa tra 1 e 100';
			GOTO BRANCH_END;
		END
		IF (@IdEer IS NULL AND @IdMateriale IS NULL) OR (@IdEer IS NOT NULL AND @IdMateriale IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare Eer oppure Materiale, non entrambi';
			GOTO BRANCH_END;
		END
		-- Lo Stato fisico non ha senso per il Materiale (per cui deve restare NULL).
		IF @IdMateriale IS NULL AND @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdMateriale IS NOT NULL
			SET @IdStatoFisico = NULL;
		-- L'unità di misura per il Materiale è sempre KG: non ci si fida che client/C# l'abbiano
		-- già impostata correttamente (il campo è disabilitato lato UI quando si seleziona Materiale).
		IF @IdMateriale IS NOT NULL
			SET @IdUnitaMisura = 'KG';
		IF @IdUnitaMisura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUnitaMisura non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: incatenata da tblRifiutiModelliRegistrazioniAuto a tblRifiutiModelli.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelliRegistrazioniAuto ra
				INNER JOIN dbo.tblRifiutiModelli m ON ra.IdModello = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE ra.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			DELETE dbo.tblRifiutiModelliRegistrazioniAutoEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				(Id, IdEtichetta)
			SELECT TOP 3
				@Id,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			UPDATE dbo.tblRifiutiModelliRegistrazioniAuto
			SET
				Percentuale = @Percentuale,
				IdEer = @IdEer,
				IdMateriale = @IdMateriale,
				IdStatoFisico = @IdStatoFisico,
				IdUnitaMisura = @IdUnitaMisura
			WHERE
				Id = @Id
				AND Lock = 0;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione automatica non trovata o già eliminata';
				GOTO BRANCH_END;
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
