SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Primo campo obbligatorio del tipo non compilato (S3.6), per segnare come eseguito un servizio o una scadenza: le SP
-- _upd lo chiamano solo con lo stato Eseguito e restituiscono il messaggio. Il valore e' quello inviato dalla scheda
-- (@Proprieta, JSON [{"Id","Valore"}], normalizzato da ufnEventi_get_ProprietaValori_List) se il campo c'e', altrimenti
-- quello gia' salvato sull'evento. Una casella si/no obbligatoria deve essere spuntata ('true'). Un campo disattivato (S3.8) non
-- e' obbligatorio. Messaggio come gli altri campi obbligatori delle schede (dal 2026-11-24, decisione dell'utente; prima
-- 'Per segnare come eseguito compilare il campo "Nome"'): Indicare "Nome", Selezionare "Nome" per l'Elenco a scelta,
-- Spuntare "Nome" per la casella si/no.
-- Usata da uspScadenze_upd, uspServizi_upd, uspServiziAssegnati_upd
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_ProprietaObbligatoriaMancante]
(
	@IdEvento CHAR(16),
	@IdTipo CHAR(16),
	@Proprieta NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN (
	SELECT TOP (1)
		Messaggio = CASE p.IdTipoDato
			WHEN 'B' THEN 'Spuntare'
			WHEN 'L' THEN 'Selezionare'
			ELSE 'Indicare'
		END + ' "' + t.Nome + '"'
	FROM
		dbo.tblTipiProprieta t
		INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
		OUTER APPLY (
			SELECT TOP (1) v.IdProprieta, v.Valore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @IdTipo, @Proprieta) v
			WHERE v.IdProprieta = t.IdProprieta
		) j
		LEFT JOIN dbo.tblEventiProprieta e ON e.Id = @IdEvento AND e.IdProprieta = t.IdProprieta
		CROSS APPLY (
			SELECT Valore = IIF(j.IdProprieta IS NOT NULL, j.Valore, NULLIF(LTRIM(RTRIM(e.Valore)), ''))
		) x
	WHERE
		t.Id = @IdTipo
		AND t.Lock = 0
		AND t.Attivo = 1
		AND t.Obbligatorio = 1
		AND
			(
			x.Valore IS NULL
			OR (p.IdTipoDato = 'B' AND x.Valore <> 'true')
			)
	ORDER BY t.Pos
);
GO
