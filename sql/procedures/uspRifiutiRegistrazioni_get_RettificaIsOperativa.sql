SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Anteprima per la modale di conferma di Rifiuti/Registrazioni (Edit e Annullamento): dice se la rettifica
-- @Id (di correzione o di annullamento), salvata con i valori indicati, varra' anche per lo stato operativo di
-- Ecomatico (rtn = 1) o solo per il RENTRI (rtn = 0, restano i valori operativi precedenti). Stessa regola
-- applicata alla conferma da uspRifiutiRegistrazioni_upd_Rettifica/_upd_Annullamento
-- (ufnRifiutiRegistrazioni_get_RettificaOperativa); per un annullamento i parametri valore sono ignorati.
-- Normalizzazione minima come uspRifiutiRegistrazioni_upd: unita' di misura KG di default e sempre KG per il
-- Materiale, per il quale Eer e stato fisico non sono modificabili in UI (restano i valori operativi precedenti).
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_RettificaIsOperativa]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18, 2) = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = ISNULL(NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), ''), 'KG');

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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è una rettifica';
			GOTO BRANCH_END;
		END

		DECLARE @isMateriale BIT = IIF(EXISTS (SELECT 1
		FROM dbo.tblRifiutiRegistrazioni
		WHERE
			Id = @Id
			AND IdMateriale IS NOT NULL
		), 1, 0);

		IF @isMateriale = 1
			SELECT
				@IdEer = IdEer,
				@IdStatoFisico = IdStatoFisico,
				@IdUnitaMisura = 'KG'
			FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);

		SELECT rtn = IsOperativa
		FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, @IdEer, @IdStatoFisico, @IdUnitaMisura, @Quantita);

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
