CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_All_List] (
	@DallaData SMALLDATETIME,
	@AllaData SMALLDATETIME,
	@IdUtente CHAR(16),
	@IdCalendario tvpId_char_16 READONLY,
	@IdTipo tvpId_char_1 READONLY)
RETURNS TABLE
AS
RETURN
(
	-- Ramo 1: tutti gli eventi del calendario (non assegnati o non filtrati per utente)
	SELECT
		Id,
		IdCalendario,
		IdStato,
		Stato,
		IdTipo,
		[Data],
		InGiornata,
		AvvisoTesto,
		Avviso,
		AvvisoAnticipo,
		AvvisoData,
		Assegnato = CAST(0 AS BIT)
	FROM
		dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo)

	UNION ALL -- mutualmente esclusivi: il WHERE NOT EXISTS lo garantisce

	-- Ramo 2: eventi assegnati all'utente non già presenti nel ramo 1
	SELECT
		b.Id,
		b.IdCalendario,
		b.IdStato,
		b.Stato,
		b.IdTipo,
		b.[Data],
		b.InGiornata,
		b.AvvisoTesto,
		b.Avviso,
		b.AvvisoAnticipo,
		b.AvvisoData,
		Assegnato = CAST(1 AS BIT)
	FROM
		dbo.ufnEventi_get_Assegnati_List(@DallaData, @AllaData, @IdUtente, @IdCalendario) b
	WHERE NOT EXISTS ( SELECT 1 FROM dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) a WHERE b.Id = a.Id ));
