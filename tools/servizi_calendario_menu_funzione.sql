SET NOCOUNT ON;

-- Servizi > Calendario: la voce di menu (tblMenu AE1) usava la pagina CAL, la stessa di Scadenze > Calendario, con la
-- funzione SCD: la vedeva chi ha le Scadenze, non chi ha i Servizi. Ora usa la pagina SRV (funzione SRV, gia'
-- presente senza Url), con lo stesso indirizzo 'calendario/settimana'. Scadenze > Calendario (AD1) resta su CAL.
-- Rieseguibile. Eseguito su dev il 2026-11-20. NON ancora eseguito in produzione.

UPDATE dbo.tblPagine
SET [Url] = 'calendario/settimana'
WHERE
	Id = 'SRV'
	AND IdFunzione = 'SRV'
	AND [Url] IS NULL;

UPDATE dbo.tblMenu
SET IdPagina = 'SRV'
WHERE
	Id = 'AE1'
	AND IdParent = 'AE0'
	AND IdPagina = 'CAL'
	AND EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'SRV' AND IdFunzione = 'SRV' AND [Url] = 'calendario/settimana');

SELECT m.Id, m.IdParent, m.Pos, p.Id AS IdPagina, p.Nome, p.[Url], p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.Id IN ('AD1', 'AE1');
GO
