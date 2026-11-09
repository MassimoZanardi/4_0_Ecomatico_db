SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Passaggi della spedizione di un Allegato VII visti dall'azienda @IdAzienda (docs/regole/diwass.md D6.7, D7): presa in
-- carico di ogni trasportatore (T), ricezione del destinatario (D), ricezione all'impianto (I) e recupero completato (C)
-- di ogni impianto, con l'operatore DIWASS del soggetto (della sede in anagrafica o letto da DIWASS). DellAzienda = il
-- soggetto ha l'operatore di una sede interna dell'azienda (IdSedeAzienda); Prevista = 0 per la ricezione del
-- destinatario che è anche l'impianto (Reg. di esecuzione UE 2025/1290 art. 17.2); Fatta = DIWASS ha già la conferma.
-- Confermabile = l'azienda può confermare il passaggio ora (D7.1): documento annunciato, in viaggio o ricevuto; presa in
-- carico solo da chi organizza in Ecomatico dal giorno della spedizione (il trasportatore non conferma da un software,
-- 2025/1290 art. 5.2); ricezioni dopo la presa in carico (in viaggio o ricevuto) e recupero completato dopo la
-- ricezione all'impianto, dal soggetto stesso o da chi organizza per suo conto (PerConto, allegato III op. 39-44)
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_Passaggi] (
	@Id CHAR(16),
	@IdAzienda CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH soggetti AS (
		SELECT
			x.Ruolo,
			x.Pos,
			x.IdSede,
			OperatorInternalId = ISNULL(o.OperatorInternalId, x.OperatorInternalId),
			Nome = ISNULL(s.NomeCompleto, x.Nome),
			x.MezzoTrasporto,
			x.ContattoNome,
			x.ContattoTelefono,
			x.ContattoEmail
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			LEFT JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
		WHERE
			x.Id = @Id
			AND x.Ruolo IN ('T', 'D', 'I')
	)
	SELECT
		p.Ordine,
		p.Tipo,
		s.Pos,
		s.OperatorInternalId,
		SoggettoNome = s.Nome,
		DellAzienda = CAST(IIF(sa.Id IS NULL, 0, 1) AS BIT),
		IdSedeAzienda = sa.Id,
		Prevista = CAST(IIF(p.Tipo = 'D' AND v.DestinatarioImpianto = 1, 0, 1) AS BIT),
		Fatta = CAST(IIF(k.Fatta IS NULL, 0, 1) AS BIT),
		Confermabile = CAST(CASE
			WHEN a.Lock <> 0 OR ISNULL(a.Stato, '') NOT IN ('ANNOUNCED', 'MOVING', 'RECEIVED') OR k.Fatta IS NOT NULL THEN 0
			WHEN p.Tipo = 'T' THEN IIF(ISNULL(a.Ricevuto, 0) = 0 AND a.DataSpedizione <= CAST(GETDATE() AS DATE), 1, 0)
			WHEN sa.Id IS NULL AND v.Organizza = 0 THEN 0
			WHEN p.Tipo = 'D' THEN IIF(v.DestinatarioImpianto = 0 AND a.Stato IN ('MOVING', 'RECEIVED'), 1, 0)
			WHEN p.Tipo = 'I' THEN IIF(a.Stato IN ('MOVING', 'RECEIVED'), 1, 0)
			ELSE IIF(EXISTS (
				SELECT 1
				FROM dbo.tblDiwassAllegatiViiConferme r
				WHERE
					r.Id = @Id
					AND r.Tipo = 'I'
					AND r.OperatorInternalId = s.OperatorInternalId
					AND r.Data IS NOT NULL
			), 1, 0)
		END AS BIT),
		PerConto = CAST(IIF(p.Tipo <> 'T' AND sa.Id IS NULL, 1, 0) AS BIT),
		s.MezzoTrasporto,
		ContattoNome = ISNULL(s.ContattoNome, c.Nome),
		ContattoTelefono = ISNULL(s.ContattoTelefono, c.Telefono),
		ContattoEmail = ISNULL(s.ContattoEmail, c.Email)
	FROM
		dbo.tblDiwassAllegatiVii a
		CROSS APPLY (
			SELECT
				Organizza = IIF(ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')) LIKE '%O%', 1, 0),
				DestinatarioImpianto = IIF(EXISTS (
					SELECT 1
					FROM
						soggetti d
						INNER JOIN soggetti i ON d.OperatorInternalId = i.OperatorInternalId
					WHERE
						d.Ruolo = 'D'
						AND i.Ruolo = 'I'
				), 1, 0)
		) v
						INNER JOIN soggetti s ON 1 = 1
						CROSS APPLY (
			SELECT
				Ordine = CASE s.Ruolo WHEN 'T' THEN 0 WHEN 'D' THEN 1 ELSE 2 END,
				Tipo = s.Ruolo
			UNION ALL
			SELECT
				Ordine = 2,
				Tipo = 'C'
			WHERE s.Ruolo = 'I') p
						OUTER APPLY (
			SELECT TOP 1 Fatta = 1
			FROM dbo.tblDiwassAllegatiViiConferme k
			WHERE
				k.Id = @Id
				AND k.Tipo = p.Tipo
				AND k.OperatorInternalId = s.OperatorInternalId
				AND k.Data IS NOT NULL
						) k
			OUTER APPLY (
			SELECT TOP 1 x.Id
			FROM
				dbo.tblDiwassOperatori o
				INNER JOIN dbo.tblSedi x ON o.Id = x.Id
			WHERE
				o.OperatorInternalId = s.OperatorInternalId
				AND x.InternaEsterna = 'I'
				AND x.IdAziendaInterna = @IdAzienda
			ORDER BY IIF(x.Id = s.IdSede, 0, 1), x.Id
		) sa
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(ISNULL(s.IdSede, sa.Id)) c
	WHERE a.Id = @Id);
GO
