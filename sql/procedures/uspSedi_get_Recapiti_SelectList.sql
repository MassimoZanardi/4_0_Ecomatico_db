CREATE PROCEDURE [dbo].[uspSedi_get_Recapiti_SelectList]
	@Tipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');

		-- @Tipo = NULL → restituisce tutti i recapiti
		-- @Tipo = 'T'  → solo telefoni (T0, T1, T2...)
		-- @Tipo = 'M'  → solo email (M0, M1, M2...)
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(0 AS BIT),
			Pos
		FROM
			dbo.tblRecapiti
		WHERE
			@Tipo IS NULL
			OR Id LIKE @Tipo + '[0-9]'
		ORDER BY
			Pos, Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
