-- Step 3: ripristina lo SCHEMABINDING sul chiamante (versione finale CRLF-corretta)
CREATE   FUNCTION [dbo].[ufnFunzioni_get_PermessoBySessione]
(
    @IdFunzione CHAR(3),
    @IdSessione CHAR(16)
)
RETURNS TINYINT
WITH SCHEMABINDING
AS
BEGIN
    IF @IdFunzione IS NULL OR @IdSessione IS NULL
        RETURN 0;

    RETURN ISNULL(
        (
            SELECT dbo.ufnFunzioni_get_PermessoByUtente(@IdFunzione, s.IdUtente)
            FROM dbo.tblSessioni AS s
            WHERE s.Id = @IdSessione
        ),
        0
    );
END;
