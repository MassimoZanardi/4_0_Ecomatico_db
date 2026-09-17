SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_ins_RegistrazioniAuto]
	@IdSessione CHAR(16) = NULL,
	@IdModello CHAR(16) = NULL,
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

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModello IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModello non può essere vuoto';
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
		IF @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		-- Titolarità sul Modello padre.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @IdModello)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Solo i modelli con Operazione 'I' (Scarico di rifiuto per trattamento interno) possono
		-- avere righe di generazione automatica.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE
				m.Id = @IdModello
				AND o.Codice = 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le registrazioni automatiche sono disponibili solo per l''operazione di scarico per trattamento interno';
			GOTO BRANCH_END;
		END

		-- Limite massimo di righe per Modello.
		IF 10 <= (SELECT COUNT(*)
		FROM dbo.tblRifiutiModelliRegistrazioniAuto
		WHERE
			IdModello = @IdModello
			AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'È stato raggiunto il limite massimo di registrazioni automatiche inseribili';
			GOTO BRANCH_END;
		END

		DECLARE @posizione INT = 1 + ISNULL((SELECT MAX(Posizione)
		FROM dbo.tblRifiutiModelliRegistrazioniAuto
		WHERE
			IdModello = @IdModello
			AND Lock = 0), 0);

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			INSERT dbo.tblRifiutiModelliRegistrazioniAuto
				(Id, IdModello, Posizione, Percentuale, IdEer, IdMateriale, IdStatoFisico, IdUnitaMisura, Lock)
			VALUES
				(@returnId, @IdModello, @posizione, @Percentuale, @IdEer, @IdMateriale, @IdStatoFisico, @IdUnitaMisura, 0);

			INSERT dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				(Id, IdEtichetta)
			SELECT TOP 3
				@returnId,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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
