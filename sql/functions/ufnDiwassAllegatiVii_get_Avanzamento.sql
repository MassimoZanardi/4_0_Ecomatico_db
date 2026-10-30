SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Avanzamento di un Allegato VII (docs/regole/diwass.md D6): date dei passaggi dalle conferme di DIWASS (prima presa in
-- carico e quante sui trasportatori indicati, ricezione del destinatario, ricezione dell'impianto, recupero
-- completato), ricezione del destinatario non prevista se destinatario e impianto sono lo stesso operatore (Reg. di
-- esecuzione UE 2025/1290 art. 17.2) e il passaggio che spetta all'azienda con l'eventuale scadenza: impianto
-- (ricezione, poi recupero completato entro un anno dalla ricezione, Reg. UE 2024/1157 art. 18.9), destinatario
-- (ricezione), chi organizza in Ecomatico (presa in carico dal giorno della spedizione). Un trasportatore non conferma
-- da un software (2025/1290 art. 5.2): nessun passaggio. Solo documenti annunciati, in viaggio o ricevuti
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_Avanzamento] (
	@Id CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		v.Trasportatori,
		v.PreseInCarico,
		v.PresaInCaricoData,
		RicezioneDestinatarioPrevista = CAST(IIF(v.DestinatarioImpianto = 1, 0, 1) AS BIT),
		v.RicezioneDestinatarioData,
		v.RicezioneImpiantoData,
		v.CompletamentoData,
		DaFare = CASE
			WHEN v.Attivo = 0 THEN NULL
			WHEN v.Ruoli LIKE '%I%' AND v.RicezioneImpiantoData IS NULL THEN N'Ricezione all''impianto'
			WHEN v.Ruoli LIKE '%I%' AND v.CompletamentoData IS NULL THEN N'Recupero completato'
			WHEN v.Ruoli LIKE '%D%' AND v.DestinatarioImpianto = 0 AND v.RicezioneDestinatarioData IS NULL THEN N'Ricezione del destinatario'
			WHEN v.Ruoli LIKE '%O%' AND v.Ricevuto = 0 AND v.PreseInCarico < v.Trasportatori AND v.DataSpedizione <= CAST(GETDATE() AS DATE) THEN N'Presa in carico'
		END,
		Scadenza = CASE
			WHEN v.Attivo = 1 AND v.Ruoli LIKE '%I%' AND v.RicezioneImpiantoData IS NOT NULL AND v.CompletamentoData IS NULL THEN DATEADD(YEAR, 1, v.RicezioneImpiantoData)
		END
	FROM (
		SELECT
			Attivo = IIF(a.Stato IN ('ANNOUNCED', 'MOVING', 'RECEIVED'), 1, 0),
			Ricevuto = ISNULL(a.Ricevuto, 0),
			Ruoli = ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')),
			a.DataSpedizione,
			t.Trasportatori,
			c.PreseInCarico,
			c.PresaInCaricoData,
			c.RicezioneDestinatarioData,
			c.RicezioneImpiantoData,
			c.CompletamentoData,
			DestinatarioImpianto = IIF(EXISTS (
				SELECT 1
				FROM
					dbo.tblDiwassAllegatiViiSoggetti d
					LEFT JOIN dbo.tblDiwassOperatori od ON d.IdSede = od.Id
					INNER JOIN dbo.tblDiwassAllegatiViiSoggetti i ON d.Id = i.Id AND i.Ruolo = 'I'
					LEFT JOIN dbo.tblDiwassOperatori oi ON i.IdSede = oi.Id
				WHERE
					d.Id = a.Id
					AND d.Ruolo = 'D'
					AND ISNULL(d.OperatorInternalId, od.OperatorInternalId) = ISNULL(i.OperatorInternalId, oi.OperatorInternalId)
			), 1, 0)
		FROM
			dbo.tblDiwassAllegatiVii a
			CROSS APPLY (
				SELECT Trasportatori = COUNT(*)
				FROM dbo.tblDiwassAllegatiViiSoggetti x
				WHERE
					x.Id = a.Id
					AND x.Ruolo = 'T'
			) t
			CROSS APPLY (
				SELECT
					PreseInCarico = COUNT(DISTINCT IIF(Tipo = 'T', OperatorInternalId, NULL)),
					PresaInCaricoData = MIN(IIF(Tipo = 'T', Data, NULL)),
					RicezioneDestinatarioData = MIN(IIF(Tipo = 'D', Data, NULL)),
					RicezioneImpiantoData = MIN(IIF(Tipo = 'I', Data, NULL)),
					CompletamentoData = MIN(IIF(Tipo = 'C', Data, NULL))
				FROM dbo.tblDiwassAllegatiViiConferme
				WHERE Id = a.Id
			) c
		WHERE a.Id = @Id
	) v
);
GO
