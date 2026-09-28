
CREATE OR ALTER FUNCTION [dbo].[ufnPersone_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: persone CONDIVISE (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Disabilitata,
		Condivisa = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnPersone_get_CondiviseByUtente_List(@IdUtente)

	UNION ALL -- mutualmente esclusivi per definizione

	-- Ramo 2: persone NON condivise (Pos = 1 → priorità inferiore)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Disabilitata,
		Condivisa = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnPersone_get_NonCondiviseByUtente_List(@IdUtente)
);
