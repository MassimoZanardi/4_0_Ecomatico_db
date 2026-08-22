CREATE   PROCEDURE [dbo].[uspProvince_get_SelectList]
    @IdSelected CHAR(3) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Ramo 1: opzione vuota
        -- Ramo 2: provincia speciale '999' (Estero o simile) sempre in cima alla lista
        -- Ramo 3: tutte le altre province con sigla
        SELECT
            Id       = '000',
            [Text]   = '(Selezionare)',
            Selected = CAST(0 AS BIT),
            Pos      = 0

        UNION ALL

        SELECT
            Id,
            [Text]   = Nome,
            Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
            Pos      = 1
        FROM   dbo.tblProvince
        WHERE  Id = '999'

        UNION ALL

        SELECT
            Id,
            [Text]   = Nome + ' (' + Sigla + ')',
            Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
            Pos      = 2
        FROM   dbo.tblProvince
        WHERE  Id <> '999'

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
        THROW 50001, @returnMessage, 1
    END

END;
