SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Numeri di formulario già presenti (Lock < 2, stesso filtro del controllo duplicati in
-- uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd) nel registro indicato - usato dalla modale "Ricerca
-- formulari digitali RENTRI" (Rifiuti/Registrazioni e Rifiuti/Formulari) per marcare/filtrare i formulari
-- già importati in questo registro e non riproporli per errore all'utente.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_get_FormularioNumeri_List]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT DISTINCT m.FormularioNumero
		FROM
			dbo.tblRifiutiMovimenti m
			INNER JOIN dbo.tblRifiutiFormulari f ON f.IdMovimento = m.Id
		WHERE
			m.IdRegistro = @IdRegistro
			AND m.FormularioNumero IS NOT NULL
			AND f.Lock < 2;

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
