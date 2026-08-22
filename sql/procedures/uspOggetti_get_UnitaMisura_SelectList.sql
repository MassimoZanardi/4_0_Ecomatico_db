CREATE       PROCEDURE [dbo].[uspOggetti_get_UnitaMisura_SelectList]
    @IdSelected CHAR(2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

        SELECT
            Id,
            [Text]   = Nome,
            Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
        FROM
            dbo.tblUnitaMisura
        WHERE
            SoloOggetti = 1
        ORDER BY
            Nome;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH

END;


