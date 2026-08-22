CREATE   FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_UltimoNumero]
(
    @IdRegistro CHAR(16),
    @Data       DATE
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @PrimoGiornoAnno DATE = DATEFROMPARTS(YEAR(@Data), 1, 1);

    RETURN
    (
        SELECT ISNULL(MAX(r.Numero), 0)
        FROM   dbo.tblRifiutiMovimenti      m
               INNER JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
        WHERE  m.IdRegistro = @IdRegistro
          AND  r.Data      >= @PrimoGiornoAnno
          AND  r.Data      <= @Data
          AND  r.Lock       < 2
    );
END;
