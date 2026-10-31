SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Formulari (Lock < 2) del registro indicato con il loro numero - usato dalla firma massiva dei formulari
-- digitali (Rifiuti/Formulari/Index, Azioni > RENTRI - Firma formulari digitali) per indicare quali FIR trovati
-- su RENTRI sono già in Ecomatico e passare all'hub l'Id del formulario, così che l'hub aggiorni lo stato locale
-- dopo la firma. Più formulari con lo stesso numero: si restituisce il primo per Id.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_get_FormularioNumeri_List]
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

		SELECT
			Id = MIN(f.Id),
			m.FormularioNumero
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
		WHERE
			m.IdRegistro = @IdRegistro
			AND m.FormularioNumero IS NOT NULL
			AND f.Lock < 2
		GROUP BY m.FormularioNumero;

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
