SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnOsepe_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: Osepe CONDIVISE (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	SELECT
		Id,
		Tipo,
		IdSede,
		IdDominio,
		Disabilitata,
		[Text],
		ImpiegabileServizi,
		Condivisa = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnOsepe_get_CondiviseByUtente_List(@IdUtente)
	UNION ALL -- mutualmente esclusivi per definizione
	-- Ramo 2: Osepe NON condivise (Pos = 1 → priorità inferiore)
	SELECT
		Id,
		Tipo,
		IdSede,
		IdDominio,
		Disabilitata,
		[Text],
		ImpiegabileServizi,
		Condivisa = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnOsepe_get_NonCondiviseByUtente_List(@IdUtente)
);
