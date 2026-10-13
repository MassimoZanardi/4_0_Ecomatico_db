SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: i DDT che la fatturazione considera, uno per movimento. Il documento
-- fatturabile è il movimento con il suo DDT: Id è l'Id del movimento (chiave di tblFattureDocumenti).
--   @Id: un solo movimento; altrimenti i movimenti dell'azienda @IdAzienda con la data del DDT tra @DataDa e
--        @DataA. Due rami distinti, ciascuno con il suo accesso (come ufnImportiRifiuti_get_Applicazione_List).
-- Nessuna riga per un movimento senza DDT.
-- IsFatturabile: DDT emesso (non ricevuto da un fornitore, sezionale R) di un movimento di scarico, con una
-- causale fatturabile (tblMagazziniCausali.IsFatturabile, oggi la sola vendita).
-- Lock: 0 solo se movimento e DDT sono confermati.
-- Destinatario: IdDestinatario è l'anagrafica indicata sul DDT, IdDestinatarioParent il suo soggetto.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_Documenti (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE)
RETURNS TABLE
AS
RETURN
(
	WITH ids AS (
		SELECT m.Id
		FROM dbo.tblMagazziniMovimenti m
		WHERE m.Id = @Id

		UNION ALL

		SELECT m.Id
		FROM
			dbo.tblMagazziniMovimenti m
			INNER JOIN dbo.tblMagazziniDdt d ON m.Id = d.IdMovimento
		WHERE
			@Id IS NULL
			AND m.IdSede = @IdAzienda
			AND d.[Data] >= @DataDa
			AND d.[Data] <= @DataA
	)
	SELECT
		m.Id,
		IdDdt = d.Id,
		d.[Data],
		d.Numero,
		d.Sezionale,
		Lock = CAST(IIF(m.Lock = 0 AND d.Lock = 0, 0, IIF(m.Lock = 4 OR d.Lock = 4, 4, 2)) AS TINYINT),
		IdAzienda = m.IdSede,
		IdSedeDdt = d.IdSede,
		IsFatturabile = CAST(IIF(ISNULL(ca.IsFatturabile, 0) = 1 AND ISNULL(d.Sezionale, '') <> 'R' AND m.IdOperazione = 'S', 1, 0) AS BIT),
		d.IdDestinatario,
		IdDestinatarioParent = ISNULL(sd.IdParent, sd.Id),
		d.IdDestinazione
	FROM
		ids k
		INNER JOIN dbo.tblMagazziniMovimenti m ON k.Id = m.Id
		INNER JOIN dbo.tblMagazziniDdt d ON m.Id = d.IdMovimento
		LEFT JOIN dbo.tblMagazziniCausali ca ON d.IdCausale = ca.Id
		LEFT JOIN dbo.tblSedi sd ON d.IdDestinatario = sd.Id
);
GO
