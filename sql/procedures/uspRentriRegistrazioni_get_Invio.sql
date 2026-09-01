SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Elenco grezzo (Numero, Anno, Data) delle registrazioni non ancora inviate al RENTRI
-- nell'intervallo scelto - stessa identica selezione/filtro di uspRentriRegistrazioni_get_InvioControllo
-- (stesso calcolo di @DataInizioRegistrazioni, stesso WHERE), ma senza i controlli di business
-- (causale, quantità, autorizzazioni, ecc.): usata per il confronto con l'elenco restituito da
-- RENTRI durante la sincronizzazione (Rifiuti/Registrazioni/Index, checkbox "sincronizza" in
-- modale 2), non per validare cosa può essere inviato.
-- exec dbo.uspRentriRegistrazioni_get_Invio @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AllaData='20501231'
-- exec dbo.uspRentriRegistrazioni_get_Invio @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AlNumero=10, @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_Invio]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@AllaData DATE = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL
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

		DECLARE @IsData BIT = CAST(IIF(@AllaData IS NOT NULL, 1, 0) AS BIT);

		IF @IsData = 0 AND (@AlNumero IS NULL OR @Anno IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare una data oppure un numero e un anno';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @DataInizioRegistrazioni DATE;

		IF EXISTS (
			SELECT 1
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2
		)
			SELECT @DataInizioRegistrazioni = MAX(Data)
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2;
		ELSE
			SELECT @DataInizioRegistrazioni = z.DataInizioInvio
			FROM
				dbo.tblRentriRegistri                    g
				LEFT JOIN [1_0_rentri]..tblRegistri z ON g.IdRentri = z.Id COLLATE DATABASE_DEFAULT
			WHERE g.Id = @IdRegistro;

		SELECT
			r.Numero,
			Anno = YEAR(r.Data),
			r.Data
		FROM dbo.viewRentriRegistrazioni r WITH (NOLOCK)
		WHERE
			r.IDRegistro = @IdRegistro
			AND r.RentriIdentificativo IS NULL
			AND r.Lock < 2
			AND (@DataInizioRegistrazioni IS NULL OR r.Data >= @DataInizioRegistrazioni)
			AND (
				(@IsData = 1 AND r.Data <= @AllaData)
				OR (@IsData = 0 AND ((r.Anno < @Anno) OR (r.Anno = @Anno AND r.Numero BETWEEN 1 AND @AlNumero)))
			)
		ORDER BY r.Data, r.Numero;

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
