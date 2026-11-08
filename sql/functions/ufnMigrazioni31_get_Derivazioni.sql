SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1: prelievo delle derivazioni. Nella 3.1 una relazione con quantita' -1 lega un carico K/M
-- (CMC/CRC) allo scarico di trattamento SFC da cui deriva, senza dire quanto ne ha preso. Regola concordata: per ogni
-- scarico i carichi derivati, in ordine di data e numero, prelevano la propria quantita' finche' lo scarico ne ha;
-- quello che lo esaurisce prende il resto, i successivi 0 (la relazione resta, con quantita' 0, perche' il materiale
-- conservi le registrazioni associate inviate al RENTRI).
-- Una relazione legata nella 3.1 a una registrazione di rettifica (tblRentriRegistrazioniRettifiche.IDRegistrazione)
-- passa al suo originale (IDRettifica): in 4.0 una rettifica non ha relazioni proprie (R2.7) e i valori corretti sono
-- quelli operativi dell'originale. IdCarico/IdScarico sono quindi gli Id 3.1 dopo questo spostamento; Spostata = 1 se
-- almeno una delle relazioni 3.1 della coppia era legata a una rettifica.
-- Quantita' effettive della 3.1: ISNULL(QuantitaRettifica, Quantita) dell'originale. Si considerano tutti i carichi
-- derivati attivi (Lock = 0) della 3.1, anche quelli che la migrazione non importa, perche' il residuo dello scarico sia
-- quello vero. Il confronto non tiene conto dell'unita' di misura, come nella 4.0: le differenze sono segnalate dalla
-- verifica.
CREATE OR ALTER FUNCTION dbo.ufnMigrazioni31_get_Derivazioni ()
RETURNS TABLE
AS
RETURN
	WITH coppie AS (
		SELECT
			IdCarico = ISNULL(tc.IDRettifica, l.IDCarico),
			IdScarico = ISNULL(ts.IDRettifica, l.IDScarico),
			Pos = MIN(l.Pos),
			Spostata = MAX(IIF(tc.IDRettifica IS NULL AND ts.IDRettifica IS NULL, 0, 1))
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN dbo.syn31RifiutiRegistrazioni c0 ON l.IDCarico = c0.IDRegistrazione
			INNER JOIN dbo.syn31RifiutiRegistrazioni s0 ON l.IDScarico = s0.IDRegistrazione
			LEFT JOIN dbo.syn31RentriRegistrazioniRettifiche tc ON l.IDCarico = tc.IDRegistrazione
			LEFT JOIN dbo.syn31RentriRegistrazioniRettifiche ts ON l.IDScarico = ts.IDRegistrazione
		WHERE
			l.[Quantità] = -1
			AND ISNULL(c0.Lock, 0) = 0
			AND ISNULL(s0.Lock, 0) = 0
		GROUP BY ISNULL(tc.IDRettifica, l.IDCarico), ISNULL(ts.IDRettifica, l.IDScarico)
	),
	d AS (
		SELECT
			k.IdCarico,
			k.IdScarico,
			k.Pos,
			k.Spostata,
			QuantitaCarico = ISNULL(c.[QuantitàRettifica], c.[Quantità]),
			QuantitaScarico = ISNULL(s.[QuantitàRettifica], s.[Quantità]),
			UnitaMisuraCarico = c.[IDUnitàMisura],
			UnitaMisuraScarico = s.[IDUnitàMisura],
			PrelevatoPrima = ISNULL(SUM(ISNULL(c.[QuantitàRettifica], c.[Quantità])) OVER (
				PARTITION BY k.IdScarico
				ORDER BY c.[Data], c.Numero, c.IDRegistrazione
				ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
		FROM
			coppie k
			INNER JOIN dbo.syn31RifiutiRegistrazioni c ON k.IdCarico = c.IDRegistrazione
			INNER JOIN dbo.syn31RifiutiRegistrazioni s ON k.IdScarico = s.IDRegistrazione
		WHERE
			ISNULL(c.Lock, 0) = 0
			AND ISNULL(s.Lock, 0) = 0
	)
	SELECT
		IdCarico,
		IdScarico,
		Pos,
		Spostata,
		QuantitaCarico,
		QuantitaScarico,
		UnitaMisuraCarico,
		UnitaMisuraScarico,
		Prelievo = CONVERT(DECIMAL(18, 2), CASE
			WHEN QuantitaScarico - PrelevatoPrima <= 0 THEN 0
			WHEN QuantitaCarico <= QuantitaScarico - PrelevatoPrima THEN QuantitaCarico
			ELSE QuantitaScarico - PrelevatoPrima
		END)
	FROM d;
GO
