SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Saldo di un lotto EoW: Prodotta = allocazioni di registrazioni M attive (Lock < 2: una registrazione
-- cancellata mantiene le allocazioni per un eventuale ripristino ma non conta), Scaricata = righe EoW dei
-- movimenti di magazzino confermati (riga e movimento Lock = 0), Giacenza = Prodotta - Scaricata.
-- Il magazzino EoW deriva dal registro operativo e prevale sul magazzino tradizionale: una Giacenza negativa
-- non viene mai corretta in automatico, e' l'anomalia "Scaricato più del prodotto" da mostrare all'utente.
CREATE OR ALTER FUNCTION dbo.ufnEoWLotti_get_Saldo (
	@IdLotto CHAR(16)
)
RETURNS TABLE
AS
RETURN
SELECT
	p.Prodotta,
	s.Scaricata,
	Giacenza = p.Prodotta - s.Scaricata
FROM
	(
	SELECT Prodotta = ISNULL(SUM(q.Quantita), 0)
	FROM
		dbo.tblEoWLottiRifiutiRegistrazioni q
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON q.IdRegistrazione = r.Id
	WHERE
		q.IdLotto = @IdLotto
		AND r.Lock < 2
	) p
		CROSS JOIN (
	SELECT Scaricata = ISNULL(SUM(rl.Quantita), 0)
	FROM
		dbo.tblMagazziniMovimentiRigheEoWLotti rl
		INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rl.Id = rg.Id
		INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
	WHERE
		rl.IdLotto = @IdLotto
		AND rg.Lock = 0
		AND ms.Lock = 0
		) s;
GO
