SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeInterneByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Amministratori: accesso a tutte le aziende interne del dominio
	SELECT
		i.Id,
		i.IdDominio
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblSediInterne i ON u.IdDominio = i.IdDominio
		INNER JOIN dbo.tblSedi s ON i.Id = s.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'AD' -- AD = Amministratore
		AND s.Lock = 0
	UNION ALL -- ✅ i due rami sono mutualmente esclusivi: UNION ALL evita DISTINCT inutile

	-- Utenti standard: solo le aziende interne direttamente associate. DISTINCT: un utente associato a più sedi
	-- della stessa azienda la riceverebbe più volte, e con lei ogni sede esterna, persona e oggetto dell'azienda
	-- (errore 1505 sull'indice unico di #sediUtente in uspRifiutiAutorizzazioni_get_SelectList)
	SELECT DISTINCT
		i.Id,
		i.IdDominio
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblUtentiSediInterne ui ON u.Id = ui.Id
		INNER JOIN dbo.tblSedi s ON ui.IdSede = s.Id
		INNER JOIN dbo.tblSediInterne i ON s.IdAziendaInterna = i.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo <> 'AD'
		AND s.Lock = 0
);
