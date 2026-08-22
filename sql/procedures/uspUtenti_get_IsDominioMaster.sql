CREATE   PROCEDURE [dbo].[uspUtenti_get_IsDominioMaster]
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF EXISTS (
            SELECT 1
            FROM   dbo.tblUtenti  u
                   INNER JOIN dbo.tblDomini   d ON u.IdDominio = d.Id
                   INNER JOIN dbo.tblSessioni s ON u.Id        = s.IdUtente
            WHERE  s.Id        = @IdSessione
              AND  d.[Master]  = 1
              AND  u.Lock      = 0
        )
            SELECT CAST(1 AS BIT) AS rtn;
        ELSE
            SELECT CAST(0 AS BIT) AS rtn;

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
