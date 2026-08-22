CREATE   FUNCTION [dbo].[ufnModuli_get_IsAttivoBySessione]
(
    @Id         CHAR(3),
    @IdSessione CHAR(16)
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN (
        SELECT dbo.ufnModuli_get_IsAttivoByUtente(@Id, IdUtente)
        FROM   dbo.tblSessioni
        WHERE  Id = @IdSessione
    );
END;
