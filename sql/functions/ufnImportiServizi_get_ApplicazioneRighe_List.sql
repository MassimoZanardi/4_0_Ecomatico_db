SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, servizi: per ogni risorsa dei servizi (persona o oggetto con quantità maggiore di 0),
-- l'importo applicato al servizio (ufnImportiServizi_get_Scelta_List) e la riga dell'importo che dà il prezzo
-- della risorsa (regole O5S di docs/regole/offerte-contratti.md). Le risorse senza quantità non entrano.
--   Parametri: quelli di ufnImportiServizi_get_Scelta_List.
-- IdRigaImporto: la riga a quantità (tipo SU) dell'importo che indica la risorsa. NULL se il servizio non ha un
-- importo, o se l'importo non ha una riga per quella risorsa: in quel caso il servizio non è fatturabile. Non si
-- cerca il prezzo in un altro importo.
-- Unità di misura: quella della persona o dell'oggetto. Pos: ordine delle risorse nel servizio (per nome).
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_ApplicazioneRighe_List (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@SoloFatturabili BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		IdServizio = s.Id,
		so.IdOsepe,
		Pos = CAST(ROW_NUMBER() OVER (PARTITION BY s.Id ORDER BY ISNULL(pe.NomeCompleto, og.Nome), so.IdOsepe) AS INT),
		Voce = CAST(ISNULL(pe.NomeCompleto, og.Nome) AS VARCHAR(200)),
		so.Quantita,
		IdUnitaMisura = CAST(ISNULL(pe.IdUnitaMisura, og.IdUnitaMisura) AS CHAR(2)),
		s.IdImporto,
		s.IdOffertaContratto,
		s.IdClienteContratto,
		s.IdImportoScartato,
		IdRigaImporto = p.Id
	FROM
		dbo.ufnImportiServizi_get_Scelta_List(@Id, @IdAzienda, @DataDa, @DataA, @SoloFatturabili) s
		INNER JOIN dbo.tblServiziOsepe so ON s.Id = so.Id
		LEFT JOIN dbo.tblPersone pe ON so.IdOsepe = pe.Id
		LEFT JOIN dbo.tblOggetti og ON so.IdOsepe = og.Id
		OUTER APPLY (
			-- Riga a quantità dell'importo per questa risorsa (una sola: lo garantisce uspImportiRighe_upd)
			SELECT TOP (1) x.Id
			FROM
				dbo.tblImportiRighe x
				INNER JOIN dbo.tblImportiRigheServizi xs ON x.Id = xs.Id
			WHERE
				x.IdImporto = s.IdImporto
				AND x.IdTipo = 'SU'
				AND x.Importo IS NOT NULL
				AND ISNULL(x.MinimoFatturabile, 0) = 0
				AND xs.IdOsepe = so.IdOsepe
			ORDER BY ISNULL(x.Pos, 0), x.Id
		) p
	WHERE so.Quantita > 0
);
GO
