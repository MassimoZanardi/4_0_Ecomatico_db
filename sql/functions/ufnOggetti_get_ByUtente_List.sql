
CREATE FUNCTION [dbo].[ufnOggetti_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: oggetti CONDIVISI (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Condiviso = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnOggetti_get_CondivisiByUtente_List(@IdUtente)

	UNION ALL -- mutualmente esclusivi per definizione

	-- Ramo 2: oggetti NON condivisi (Pos = 1 → priorità inferiore)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Condiviso = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnOggetti_get_NonCondivisiByUtente_List(@IdUtente)
);
