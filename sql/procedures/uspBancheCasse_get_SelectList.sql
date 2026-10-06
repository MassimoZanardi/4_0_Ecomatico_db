SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: la select serve alla scheda cliente (ANC) e fornitore (ANF)
		-- oltre che alla configurazione (FTC); basta la lettura su una delle tre
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: banche e casse dell'azienda interna corrente della sessione
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				b.Id,
				[Text] = CAST(b.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(b.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblBancheCasse b
				INNER JOIN dbo.tblSessioni e ON b.IdSede = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND b.Lock = 0
		) t
		ORDER BY Pos, [Text];

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
