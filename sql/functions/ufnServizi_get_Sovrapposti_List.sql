SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnServizi_get_Sovrapposti_List] (
	@DallaData SMALLDATETIME,
	@AllaData SMALLDATETIME,
	@IdCalendario tvpId_char_16 READONLY,
	@IdTipo tvpId_char_1 READONLY)
RETURNS TABLE
-- WITH SCHEMABINDING non applicabile: dipende da TVP (tvpId_char_16, tvpId_char_1)
-- che non sono oggetti schema-bound
AS
-- Servizi sovrapposti per risorsa (S9.4.1, filtro "Solo con sovrapposizioni" degli Impegni, S9.14): una riga per
-- risorsa e occorrenza del servizio (IdServizio + Inizio, le occorrenze generate di una serie hanno lo stesso servizio
-- e date diverse) che si accavalla davvero con un'altra della stessa risorsa: inizia prima della sua fine e finisce
-- dopo il suo inizio. Senza durata conta il solo minuto di inizio; i servizi "In giornata" non hanno un'ora e non si
-- confrontano; annullati esclusi. Stessa regola delle viste a blocchi (calendario-blocchi.js, segnaSovrapposti) e di
-- uspServizi_get_Impegni_List. @IdCalendario: i calendari di tutti i servizi delle risorse, anche quelli non visibili
-- ("Occupato" conta), @IdTipo = 'V'. Il servizio termina entro la mezzanotte del giorno di inizio (uspServizi_upd),
-- quindi bastano i servizi che iniziano nel periodo
RETURN
(
	WITH cteServizi AS (
		SELECT
			o.IdOsepe,
			IdServizio = s.Id,
			Inizio = e.[Data],
			Fine = DATEADD(MINUTE, ISNULL(s.Durata, 1), e.[Data])
		FROM
			dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
		WHERE
			e.IdStato <> 'A'
			AND ISNULL(e.InGiornata, 0) = 0
	)
	SELECT DISTINCT
		a.IdOsepe,
		a.IdServizio,
		a.Inizio
	FROM
		cteServizi a
		INNER JOIN cteServizi b ON
			b.IdOsepe = a.IdOsepe
			AND NOT (b.IdServizio = a.IdServizio AND b.Inizio = a.Inizio)
			AND b.Inizio < a.Fine
			AND a.Inizio < b.Fine
);
GO
