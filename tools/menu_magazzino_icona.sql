SET NOCOUNT ON;

-- Menu Magazzino: icona più stretta. fa-warehouse è larga 640 unità (la più larga del menu insieme a
-- fa-user-edit); fa-box-alt è larga 448, come le icone di Scadenze, Servizi, Rifiuti e Rentri.
-- Rieseguibile.

UPDATE dbo.tblPagineAree
SET Icon = 'fal fa-box-alt'
WHERE
	Id = 'MAG'
	AND Icon <> 'fal fa-box-alt';

SELECT Id, Nome, Icon
FROM dbo.tblPagineAree
WHERE Id = 'MAG';
GO
