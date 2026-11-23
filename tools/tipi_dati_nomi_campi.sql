SET NOCOUNT ON;

-- Tipi di campo dei campi aggiuntivi dei tipi di scadenza e di servizio (tblTipiDati, S3.3): nomi per l'utente al posto
-- dei termini da sviluppatore ("Sì/No (booleano)", "Numerico (intero)", "Testo (stringa)"), decisione dell'utente del
-- 2026-11-23. Cambiano solo i nomi mostrati nella scheda del tipo; Id e controlli restano. Rieseguibile.
-- Eseguito su dev il 2026-11-23. NON ancora eseguito in produzione.

UPDATE d
SET Nome = n.Nome
FROM
	dbo.tblTipiDati d
	INNER JOIN (VALUES
		('B', 'Casella sì/no'),
		('D', 'Data'),
		('I', 'Numero'),
		('S', 'Testo')
	) n (Id, Nome) ON d.Id = n.Id COLLATE Latin1_General_CI_AS
WHERE d.Nome <> n.Nome COLLATE Latin1_General_CI_AS;

SELECT Id, Nome FROM dbo.tblTipiDati ORDER BY Id;
GO