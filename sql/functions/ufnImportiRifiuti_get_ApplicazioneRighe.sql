SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: righe di fattura che l'importo applicato a una registrazione dei rifiuti
-- (ufnImportiRifiuti_get_Applicazione) genera per quella registrazione, nell'ordine delle righe dell'importo.
-- Per una sola registrazione: determina importo e cliente e ne legge le righe con
-- ufnImportiRifiuti_get_RigheImporto, dove sono descritte le regole (quantità, sola descrizione, minimo
-- fatturabile, segnaposto, aliquota IVA). Chi ha già importo e cliente di più registrazioni usa direttamente
-- quella, senza rifare il confronto.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_ApplicazioneRighe (
	@Id CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		g.Id,
		g.Pos,
		g.IdTipo,
		g.MinimoFatturabile,
		g.SolaDescrizione,
		g.Descrizione,
		g.Quantita,
		g.IdUnitaMisura,
		g.Importo,
		g.Imponibile,
		g.IdAliquotaIva,
		g.IdConto
	FROM
		dbo.ufnImportiRifiuti_get_Applicazione(@Id) x
		CROSS APPLY dbo.ufnImportiRifiuti_get_RigheImporto(x.Id, x.IdImporto, x.IdClienteFornitore) g
);
GO
