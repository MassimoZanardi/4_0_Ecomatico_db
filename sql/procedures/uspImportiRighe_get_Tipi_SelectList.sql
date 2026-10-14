SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei tipi di riga di un importo per il modulo indicato (RIF, MAG, SRV): dato di riferimento
-- (tblImportiRigheTipi). Il tipo dice per che cosa si moltiplica l'importo della riga: una volta per documento
-- (Movimento, Servizio) oppure per la quantità (KG, T, L, articolo, risorsa).
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_get_Tipi_SelectList
	@IdModulo CHAR(3) = NULL,
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END

		SELECT
			t.Id,
			[Text] = t.Nome,
			Selected = CAST(IIF(t.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblImportiRigheTipi t
		WHERE t.IdModulo = @IdModulo
		ORDER BY t.Pos;

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
