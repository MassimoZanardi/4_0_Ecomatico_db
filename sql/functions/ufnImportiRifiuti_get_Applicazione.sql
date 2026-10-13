SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importo e cliente che la fatturazione applica a una registrazione dei rifiuti
-- (regole O5 di docs/regole/offerte-contratti.md). Una riga per la registrazione @Id, anche se nessun importo
-- coincide (IdImporto NULL).
-- È ufnImportiRifiuti_get_Applicazione_List per una sola registrazione, senza il filtro sulle fatturabili: la
-- regola e il significato delle colonne sono descritti lì. Per più registrazioni usare quella, non questa con
-- CROSS APPLY (il confronto verrebbe rifatto per ogni registrazione).
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Applicazione (
	@Id CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		a.[Data],
		a.Numero,
		a.Lock,
		a.IdSedeRegistro,
		a.IdAzienda,
		a.IdOperazione,
		a.IsFatturabile,
		a.IdEer,
		a.IdUnitaMisura,
		a.Quantita,
		a.IsRettifica,
		a.IsAnnullata,
		a.IdProduttore,
		a.IdProduttoreParent,
		a.IdTrasportatore,
		a.IdDestinatario,
		a.IdIntermediario,
		a.FormularioNumero,
		a.IdClienteIndicato,
		a.NonFatturabile,
		a.IdFattura,
		a.IsPreFattura,
		a.IdClientePreFattura,
		a.IdImporto,
		a.IdOffertaContratto,
		a.IdClienteFornitore,
		a.ClienteOrigine,
		a.IdImportoScartato
	FROM dbo.ufnImportiRifiuti_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
);
GO
