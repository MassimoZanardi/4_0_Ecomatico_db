SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_get_Verifica]
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Se @IdSede è indicata, deve essere una sede interna della sessione
		IF @IdSede IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			WHERE i.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Calcolo delegato a ufnRifiutiLimiti_get_Verifica_List (condivisa con
		-- uspAvvisi_get_Limiti_List/uspAvvisi_get_Count): qui restano solo permesso e titolarità.
		SELECT
			v.Id,
			v.Nome,
			v.IdSede,
			v.IdRegistro,
			v.IdRegistroVerifica,
			v.RegistroVerificaNome,
			v.IdUnitaMisura,
			v.Riferimento,
			v.Intervallo,
			v.Valore,
			v.ValoreAttuale,
			v.Superato
		FROM
			dbo.ufnRifiutiLimiti_get_Verifica_List(@IdSede) v
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON v.IdSede = i.Id
		ORDER BY v.Nome, v.RegistroVerificaNome
		OPTION (RECOMPILE);

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
