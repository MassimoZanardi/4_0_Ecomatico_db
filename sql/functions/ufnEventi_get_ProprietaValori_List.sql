SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Valori delle proprietà di un evento inviati dalla scheda (JSON [{"Id":"I00","Valore":"12"}, ...]), controllati e
-- normalizzati per tipo di dato. Restituisce solo le proprietà del tipo @IdTipo presenti nel JSON (le altre sono
-- ignorate). Valore NULL = da togliere; Errore valorizzato = valore non ammesso (la SP chiamante lo restituisce).
-- Formati salvati: Sì/No 'true'/'false', Numero con il punto e al massimo 4 decimali (dal 2026-11-23, prima solo intero;
-- dalla scheda arriva con la virgola), Data 'yyyy-MM-dd', Testo fino a 50 caratteri.
-- Usata da uspScadenze_upd, uspServizi_upd, uspServiziAssegnati_upd
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_ProprietaValori_List]
(
	@IdTipo CHAR(16),
	@Proprieta NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN (
	SELECT
		t.IdProprieta,
		t.Pos,
		v.Valore,
		Errore = IIF(j.Valore IS NOT NULL AND v.Valore IS NULL,
						'Il campo "' + t.Nome + '" ' + CASE p.IdTipoDato
							WHEN 'B' THEN 'deve essere Sì o No'
							WHEN 'I' THEN 'deve essere un numero, con al massimo 4 decimali'
							WHEN 'D' THEN 'deve essere una data'
							ELSE 'non può superare i 50 caratteri'
						END,
						NULL)
	FROM
		dbo.tblTipiProprieta t
		INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
		CROSS APPLY (
			SELECT TOP 1 Valore = NULLIF(LTRIM(RTRIM(x.Valore)), '')
			FROM OPENJSON(@Proprieta) WITH (Id CHAR(3) '$.Id', Valore NVARCHAR(4000) '$.Valore') x
			WHERE x.Id = t.IdProprieta
		) j
		-- Numero: con la virgola i punti sono migliaia (1.234,5), senza virgola il punto e' il decimale (12.5)
		CROSS APPLY (
			SELECT Numero = TRY_CONVERT(DECIMAL(28, 10), IIF(CHARINDEX(',', j.Valore) > 0, REPLACE(REPLACE(j.Valore, '.', ''), ',', '.'), j.Valore))
		) n
		CROSS APPLY (
			SELECT Valore = CASE p.IdTipoDato
				WHEN 'B' THEN IIF(LOWER(j.Valore) IN ('true', 'false'), CAST(LOWER(j.Valore) AS VARCHAR(50)), NULL)
				WHEN 'I' THEN IIF(n.Numero IS NOT NULL AND n.Numero = ROUND(n.Numero, 4), FORMAT(CAST(n.Numero AS DECIMAL(18, 4)), '0.####', 'en-US'), NULL)
				WHEN 'D' THEN CONVERT(VARCHAR(50), TRY_CONVERT(DATE, j.Valore, 23), 23)
				ELSE IIF(LEN(j.Valore) <= 50, CAST(j.Valore AS VARCHAR(50)), NULL)
			END
		) v
	WHERE t.Id = @IdTipo
);
GO
