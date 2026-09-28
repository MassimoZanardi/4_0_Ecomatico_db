SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_Etichette]
(
	@Id CHAR(16)
)
RETURNS VARCHAR(2000)
WITH SCHEMABINDING
AS
BEGIN
	RETURN (
		SELECT
			e.Nome,
			Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
			e.Descrizione,
			e.Visualizzazione
		FROM
			dbo.tblRifiutiRegistrazioniEtichette t
			INNER JOIN dbo.tblEtichette e ON t.IdEtichetta = e.Id
			INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
		WHERE
			t.Id = @Id
			AND e.Lock = 0
		ORDER BY
			e.Nome
		FOR JSON PATH
	);
END;
