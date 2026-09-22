SET NOCOUNT ON;

-- Sposta EoW sopra Rentri (tra Rifiuti e Rentri) nel menu principale.
-- Prima: Rifiuti(4), Rentri(5), EoW(6), Impostazioni(7)
-- Dopo:  Rifiuti(4), EoW(5), Rentri(6), Impostazioni(7)
UPDATE dbo.tblMenu
SET Pos = CASE Id WHEN 'AH0' THEN 5 WHEN 'AG0' THEN 6 END
WHERE Id IN ('AH0', 'AG0');
