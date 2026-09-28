SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Valori di default per la modale "Invio registrazioni" (Rifiuti/Registrazioni/Index): data e
-- numero/anno dell'ultima registrazione non ancora inviata al RENTRI del Registro indicato.
-- Nessuna riga se il Registro non ha ancora registrazioni non inviate (Lock=0, RentriIdentificativo NULL).
-- Rinominata da uspRifiutiRegistrazioni_get_InvioDefault (2026-09-01) per coerenza col prefisso
-- Rentri delle altre SP dedicate al RENTRI (uspRentriSedi_*, uspRentriRegistri_*, ecc.).
-- exec dbo.uspRentriRegistrazioni_get_InvioDefault @IdRegistro='fd73e743a19b44c0', @IdSessione='...'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_InvioDefault]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
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

		-- OUTER APPLY su una riga fittizia: garantisce sempre esattamente 1 riga in output
		-- (con colonne NULL se non ci sono registrazioni non inviate), richiesto da QuerySingleAsync lato C#.
		SELECT
			UltimaData = t.Data,
			UltimoNumero = t.Numero,
			UltimoAnno = t.Anno
		FROM
			(SELECT 1 AS Dummy) d
			OUTER APPLY (
				SELECT TOP 1
					r.Data, r.Numero, r.Anno
				FROM
					dbo.viewRentriRegistrazioni r WITH (NOLOCK)
				WHERE
					r.IDRegistro = @IdRegistro
					AND r.RentriIdentificativo IS NULL
					AND r.Lock = 0
				ORDER BY
					r.Data DESC, r.Numero DESC
			) t;

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

END
GO
