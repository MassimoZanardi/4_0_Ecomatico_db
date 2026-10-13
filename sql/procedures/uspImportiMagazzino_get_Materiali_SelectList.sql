SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei materiali EoW per la variabile "Materiale" di un importo di magazzino (righe EoW del DDT). La
-- prima voce (Id a zeri) significa "qualsiasi". I materiali sono un'anagrafica di sistema, uguale per tutti.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Materiali_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idDueZeri CHAR(2) = REPLICATE('0', 2);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idDueZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idDueZeri AS CHAR(2)),
				[Text] = CAST('(Tutti)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idDueZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				m.Id,
				[Text] = CAST(m.Nome AS VARCHAR(400)),
				Selected = CAST(IIF(m.Id = @IdSelected, 1, 0) AS BIT),
				Pos = IIF(m.Nome = 'Altro', 2, 1)
			FROM dbo.tblRifiutiMateriali m
		) x
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
