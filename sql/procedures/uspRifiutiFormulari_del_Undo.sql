CREATE   PROCEDURE [dbo].[uspRifiutiFormulari_del_Undo]
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        BEGIN TRANSACTION;

            UPDATE i
            SET    Lock = 0
            FROM
                dbo.tblRifiutiFormulari  i
                INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
            WHERE
                c.IdSessione = @IdSessione;

            -- Aggiorna il Log
            DELETE i
            FROM
                dbo.tblIdLog         i
                INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
            WHERE
                c.IdSessione = @IdSessione
                AND i.Operazione = 'D';

            DELETE dbo.tblIdCancellati WHERE IdSessione = @IdSessione;

            SET @returnMessage = IIF(@@ROWCOUNT = 1, 'Entità ripristinata', FORMAT(@@ROWCOUNT, 'N0', 'it-IT') + ' entità ripristinate');

        COMMIT TRANSACTION;

        SELECT ReturnMessage = @returnMessage;

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
