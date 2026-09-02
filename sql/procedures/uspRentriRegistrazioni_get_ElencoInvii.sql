SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Storico degli invii al RENTRI già effettuati per il Registro indicato, filtrati per anno
-- (default anno corrente), più recente prima. tblRegistriInvii vive sul DB hub 1_0_rentri (join
-- cross-db diretto, stesso pattern di uspRentriRegistrazioni_get_Invio); IdUtente è l'Id
-- applicativo di 4_0_ecomatico salvato dall'hub al momento dell'invio, risolto qui in Email
-- tramite tblUtenti.
-- exec dbo.uspRentriRegistrazioni_get_ElencoInvii @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_ElencoInvii]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
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

		DECLARE @IdRentri CHAR(16);
		SELECT @IdRentri = IdRentri FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		SET @Anno = ISNULL(@Anno, YEAR(GETDATE()));

		SELECT TOP (100)
			i.[Data],
			Utente = u.Email,
			i.DalNumero,
			i.DalNumeroAnno,
			i.AlNumero,
			i.AlNumeroAnno
		FROM
			[1_0_rentri]..tblRegistriInvii i WITH (NOLOCK)
			LEFT OUTER JOIN dbo.tblUtenti u ON u.Id = i.IdUtente COLLATE DATABASE_DEFAULT
		WHERE
			i.IdRegistro = @IdRentri COLLATE DATABASE_DEFAULT
			AND YEAR(i.[Data]) = @Anno
		ORDER BY
			i.[Data] DESC;

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
