SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Vista consumata dall'hub condiviso 1_0_rentri (nuovo branch @App='40' di uspFormulario_get_ByIdFormulario),
-- referenziata letteralmente come [4_0_ecomatico]..viewRentriFormulariDigitali: nome e insieme di colonne NON
-- sono rinominabili/estendibili senza coordinarsi con l'hub. Colonne allineate a RentriApi.Domain.Models.FormularioDigitale
-- (Dapper QuerySingle, match per nome colonna). A differenza del branch gemello @App='31' (3_1_ecomatico..viewRentriFormulariDigitali,
-- schema legacy solo trasporto su gomma) questo schema supporta anche Ferroviario/Marittimo (tblRifiutiMovimentiTrasportatori.IdTipo
-- G/T/N), quindi valorizza anche TrasportoTipo/Trasporto2Tipo/IdentificativoTreno/Tratta/Nave/OpzioneTrenoNave, assenti nel branch 31.
-- Note sui campi lasciati a NULL/default (nessun concetto equivalente in questo schema, non usati dal blocco
-- dati_partenza costruito da ApiHelpers.BuildFormularioContent per le azioni Crea/Modifica):
-- - Produttore/DestinatarioSede: nessun uso lato hub, sempre NULL.
-- - Luogo di produzione diverso dall'unita' locale (tblRifiutiFormulari.LuogoDiProduzione=1): l'indirizzo
--   selezionato nel FIR (Sede dell'autorizzazione produttore) e' il luogo di produzione effettivo (Posizione*),
--   mentre Produttore* (Nome/CodiceFiscale/indirizzo, l'unita' locale/sede legale) va risolto separatamente:
--   nella famiglia della Sede (se stessa/sorelle dirette via IdParent, ancora = ISNULL(IdParent, Id) - stesso
--   raggruppamento dell'invariante di uspSedi_upd), la Sede con UnitaLocale=1, altrimenti la Sede Padre
--   (regola identica sia per sedi interne che esterne, nessun filtro InternaEsterna - confermato dall'utente
--   2026-09-05). NON usare IdAziendaInterna come chiave di famiglia: per le Sedi Esterne quella colonna vale
--   l'azienda interna proprietaria (tblSediEsterne.IdSedeInterna, vedi uspSedi_upd), non la radice della
--   propria parentela - userebbe come "sorelle" tutte le sedi esterne di quell'azienda interna, non quelle
--   della stessa famiglia (bug reale riscontrato in produzione 2026-09-06, corretto qui usando IdParent).
--   Il gate lato hub ApiHelpers.BuildFormularioContent (codice condiviso con le app legacy, non modificabile) allega il blocco
--   luogo_produzione solo se IDCausale='CSX' - per questo IDCausale sopra e' forzato a 'CSX' quando
--   LuogoDiProduzione=1 (nessun altro uso di IDCausale in questo schema/lato hub), invece di modificare il gate.
-- - Esito/DataEsito/QuantitaRegistrata/QuantitaDestino/QuantitaRespinta/EsitoCausaleRespingimento/RespingimentoMotivo/
--   DataOraFineTrasporto: dati di accettazione, non ancora implementati lato app (fase successiva, endpoint /accettazione) -
--   default sicuri per non rompere il mapping Dapper (tipi non nullable lato C#).
-- Autorizzazione Produttore/Destinatario: tblRifiutiAutorizzazioni.IdNumeroTipo distingue 'A' (Albo Gestori Ambientali,
-- popola solo *AutorizzazioneAlbo) da 'C'/altro (Comunicazione/Autorizzazione generica, popola *Autorizzazione +
-- *AutorizzazioneTipo da tblRifiutiAutorizzazioniTipi.Codice, gia' allineato ai valori enum RENTRI tipo_autorizzazione
-- - es. RecSmalArt208/AIA/RecProcSemplificata - verificato confrontando i due lookup). Trasportatori/Intermediari
-- usano sempre e solo il Numero come iscrizione Albo (RENTRI non prevede un tipo alternativo per questi ruoli).
-- DataOraInizioTrasporto: stringa ISO8601 con offset +01:00/+02:00 calcolato correttamente per il DST tramite
-- AT TIME ZONE (non hardcoded come nel branch legacy 31, che ha sempre "+02:00" indipendentemente dal periodo dell'anno).
CREATE OR ALTER VIEW [dbo].[viewRentriFormulariDigitali]
AS
SELECT
	IdFormulario = f.Id,
	-- IDCausale='CSX' forzato quando LuogoDiProduzione=1: e' l'UNICO segnale che ApiHelpers.BuildFormularioContent
	-- (1_0_RentriApi, codice condiviso con le app legacy, non modificabile) usa per decidere se allegare il
	-- blocco luogo_produzione (richiede anche ProduttorePosizione IS NOT NULL e ProduttoreSede <> ProduttorePosizione,
	-- entrambi gia' soddisfatti quando LuogoDiProduzione=1 in questa vista - ProduttoreSede e' sempre NULL).
	-- 'CSX' non ha altro significato/uso in questo schema, e IDCausale non e' letto altrove dall'hub.
	-- Soluzione confermata dall'utente (2026-09-05) per non dover toccare l'endpoint condiviso.
	IDCausale = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN 'CSX' ELSE o.Codice END,
	Numero = m.FormularioNumero,
	DataEmissione = ISNULL(f.DataEmissione, GETDATE()),
	ProduttoreNome = UPPER(CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN spul.NomeCompleto ELSE sp.NomeCompleto END),
	ProduttoreCodiceFiscale = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ISNULL(spul.CodiceFiscale, spul.PartitaIva) ELSE ISNULL(sp.CodiceFiscale, sp.PartitaIva) END,
	ProduttoreSede = CAST(NULL AS VARCHAR(200)),
	-- Luogo di produzione diverso dall'unita' locale (f.LuogoDiProduzione=1): l'indirizzo selezionato nel FIR
	-- (sp/ip, la Sede dell'autorizzazione produttore) e' in realta' il luogo di produzione (va in Posizione*),
	-- mentre l'unita' locale (Produttore*) va risolta separatamente nella famiglia di sp (se stessa/sorelle
	-- dirette via IdParent, stesso raggruppamento dell'invariante di uspSedi_upd - NON IdAziendaInterna, che
	-- per le Sedi Esterne e' l'azienda interna proprietaria e non la radice della propria parentela):
	-- la Sede con UnitaLocale=1, o in sua assenza la Sede Padre di sp (spul, risolta in OUTER APPLY sotto).
	-- Confermato dall'utente (2026-09-05): anche Nome/CodiceFiscale vanno presi dalla Sede risolta (spul), non da sp.
	ProduttorePosizione = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN UPPER(ip.Indirizzo + ISNULL(', ' + NULLIF(ip.NumeroCivico, ''), '')) ELSE NULL END,
	ProduttoreAutorizzazioneAlbo = CASE WHEN ISNULL(pa.Nessuna, 0) = 1 THEN NULL WHEN pa.IdNumeroTipo = 'A' THEN pa.Numero ELSE NULL END,
	ProduttoreAutorizzazione = CASE WHEN ISNULL(pa.Nessuna, 0) = 1 THEN NULL WHEN pa.IdNumeroTipo = 'A' THEN NULL ELSE pa.Numero END,
	ProduttoreAutorizzazioneTipo = CASE WHEN ISNULL(pa.Nessuna, 0) = 1 OR pa.IdNumeroTipo = 'A' THEN NULL ELSE pat.Codice END,
	ProduttoreNazione = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN nzpul.Sigla ELSE nzp.Sigla END,
	ProduttoreIdComune = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.IdComune ELSE ip.IdComune END,
	ProduttoreIndirizzo = UPPER(CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.Indirizzo + ISNULL(', ' + NULLIF(ipul.NumeroCivico, ''), '') ELSE ip.Indirizzo + ISNULL(', ' + NULLIF(ip.NumeroCivico, ''), '') END),
	ProduttoreCAP = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.CAP ELSE ip.CAP END,
	ProduttoreLocalita = UPPER(CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ipul.Localita ELSE ip.Localita END),
	PosizioneNazione = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN nzp.Sigla ELSE NULL END,
	PosizioneIdComune = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ip.IdComune ELSE NULL END,
	PosizioneIndirizzo = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN UPPER(ip.Indirizzo + ISNULL(', ' + NULLIF(ip.NumeroCivico, ''), '')) ELSE NULL END,
	PosizioneCAP = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN ip.CAP ELSE NULL END,
	PosizioneLocalita = CASE WHEN ISNULL(f.LuogoDiProduzione, 0) = 1 THEN UPPER(ip.Localita) ELSE NULL END,
	DestinatarioNome = UPPER(sd.NomeCompleto),
	DestinatarioCodiceFiscale = ISNULL(sd.CodiceFiscale, sd.PartitaIva),
	DestinatarioSede = CAST(NULL AS VARCHAR(200)),
	DestinatarioAutorizzazioneAlbo = CASE WHEN ISNULL(da.Nessuna, 0) = 1 THEN NULL WHEN da.IdNumeroTipo = 'A' THEN da.Numero ELSE NULL END,
	DestinatarioAutorizzazione = CASE WHEN ISNULL(da.Nessuna, 0) = 1 THEN NULL WHEN da.IdNumeroTipo = 'A' THEN NULL ELSE da.Numero END,
	DestinatarioAutorizzazioneTipo = CASE WHEN ISNULL(da.Nessuna, 0) = 1 OR da.IdNumeroTipo = 'A' THEN NULL ELSE dat.Codice END,
	DestinatarioNazione = nzd.Sigla,
	DestinatarioIdComune = id_.IdComune,
	DestinatarioIndirizzo = UPPER(id_.Indirizzo + ISNULL(', ' + NULLIF(id_.NumeroCivico, ''), '')),
	DestinatarioCAP = id_.CAP,
	DestinatarioLocalita = UPPER(id_.Localita),
	Destinazione = attv.Codice,
	TrasportatoreNome = UPPER(st1.NomeCompleto),
	TrasportatoreCodiceFiscale = ISNULL(st1.CodiceFiscale, st1.PartitaIva),
	TrasportatoreAutorizzazioneAlbo = CASE WHEN ISNULL(ta1.Nessuna, 0) = 1 THEN NULL ELSE ta1.Numero END,
	TrasportatoreNazione = nzt1.Sigla,
	TrasportoTipo = CASE mt1.IdTipo WHEN 'T' THEN 'Ferroviario' WHEN 'N' THEN 'Marittimo' ELSE 'Terrestre' END,
	Trasportatore2Nome = UPPER(st2.NomeCompleto),
	Trasportatore2CodiceFiscale = ISNULL(st2.CodiceFiscale, st2.PartitaIva),
	Trasportatore2AutorizzazioneAlbo = CASE WHEN ISNULL(ta2.Nessuna, 0) = 1 THEN NULL ELSE ta2.Numero END,
	Trasportatore2Nazione = nzt2.Sigla,
	Trasporto2Tipo = CASE mt2.IdTipo WHEN 'T' THEN 'Ferroviario' WHEN 'N' THEN 'Marittimo' ELSE 'Terrestre' END,
	IntermediarioNome = UPPER(si1.NomeCompleto),
	IntermediarioCodiceFiscale = ISNULL(si1.CodiceFiscale, si1.PartitaIva),
	IntermediarioAutorizzazioneAlbo = CASE WHEN ISNULL(ia1.Nessuna, 0) = 1 THEN NULL ELSE ia1.Numero END,
	IntermediarioNazione = nzi1.Sigla,
	Intermediario2Nome = UPPER(si2.NomeCompleto),
	Intermediario2CodiceFiscale = ISNULL(si2.CodiceFiscale, si2.PartitaIva),
	Intermediario2AutorizzazioneAlbo = CASE WHEN ISNULL(ia2.Nessuna, 0) = 1 THEN NULL ELSE ia2.Numero END,
	Intermediario2Nazione = nzi2.Sigla,
	Eer = m.IdEer,
	EerDescrizione = m.EerDescrizione,
	StatoFisico = sf.Codice,
	Provenienza = ISNULL(m.IdProvenienza, 'S'),
	ClassiPericolo = cp.ClassiPericolo,
	Quantita = m.Quantita,
	QuantitaDestino = CAST(0 AS DECIMAL(18, 2)),
	QuantitaRespinta = CAST(0 AS DECIMAL(18, 2)),
	UnitaMisura = LOWER(um.Codice),
	QuantitaVerificataPartenza = ISNULL(f.VerificatoInPartenza, 0),
	Colli = f.ColliNumero,
	AllaRinfusa = ISNULL(f.AllaRinfusa, 0),
	ADR = ISNULL(f.TrasportoAdr, 0),
	ClasseADR = adr.Codice,
	NumeroONU = f.NumeroOnu,
	TargaMotrice = CASE WHEN mt1.IdTipo = 'G' THEN fg.TargaMotrice ELSE NULL END,
	TargaRimorchio = CASE WHEN mt1.IdTipo = 'G' THEN fg.TargaRimorchio ELSE NULL END,
	Percorso = CASE WHEN mt1.IdTipo = 'G' THEN fg.Percorso ELSE NULL END,
	ConducenteNome = CASE WHEN mt1.IdTipo = 'G' THEN fg.ConducenteNome ELSE NULL END,
	ConducenteCognome = CASE WHEN mt1.IdTipo = 'G' THEN fg.ConducenteCognome ELSE NULL END,
	DataOraInizioTrasporto = CASE WHEN m.DataInizioTrasporto IS NULL THEN NULL ELSE
		CONVERT(VARCHAR(33), CAST(m.DataInizioTrasporto AS DATETIME2) AT TIME ZONE 'Central European Standard Time', 127)
	END,
	OraInizioTrasporto = CAST(NULL AS VARCHAR(10)),
	Analisi = f.IdAnalisiTipo,
	AnalisiNumero = f.AnalisiNumero,
	AnalisiData = FORMAT(f.AnalisiData, 'yyyy-MM-dd'),
	Note = LEFT(f.Note, 500),
	Detentore = CASE WHEN f.Detentore = 1 THEN 'X' ELSE NULL END,
	AdrNote = f.AdrNote,
	Esito = 'A',
	DataEsito = CAST(NULL AS VARCHAR(30)),
	QuantitaRegistrata = CAST(0 AS DECIMAL(18, 2)),
	DataOraFineTrasporto = CAST('20501231' AS DATE),
	EsitoCausaleRespingimento = CAST(NULL AS VARCHAR(10)),
	RespingimentoMotivo = CAST(NULL AS VARCHAR(200)),
	IdentificativoTreno = CASE WHEN mt1.IdTipo = 'T' THEN ft.Treno ELSE NULL END,
	IdentificativoTratta = CASE WHEN mt1.IdTipo = 'T' THEN ft.Tratta ELSE NULL END,
	IdentificativoNave = CASE WHEN mt1.IdTipo = 'N' THEN fn.Nave ELSE NULL END,
	OpzioneTrenoNave = CASE mt1.IdTipo WHEN 'T' THEN ISNULL(ft.Rid, 0) WHEN 'N' THEN ISNULL(fn.Imdg, 0) ELSE CAST(0 AS BIT) END,
	Stato = m.RentriFormularioStato
FROM
	dbo.tblRifiutiFormulari f
	INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
	LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
	LEFT JOIN dbo.tblRifiutiStatiFisici sf ON m.IdStatoFisico = sf.Id
	LEFT JOIN dbo.tblUnitaMisura um ON m.IdUnitaMisura = um.Id
	LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita = attv.Id
	LEFT JOIN dbo.tblAdr adr ON f.IdAdr = adr.Id
	-- Produttore
	LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni pa ON mp.IdAutorizzazione = pa.Id
	LEFT JOIN dbo.tblRifiutiAutorizzazioniTipi pat ON pa.IdTipo = pat.Id
	LEFT JOIN dbo.tblSedi sp ON pa.IdSede = sp.Id
	LEFT JOIN dbo.tblSediIndirizzi sip ON sp.Id = sip.Id
	LEFT JOIN dbo.tblIndirizzi ip ON sip.IdIndirizzo = ip.Id
	LEFT JOIN dbo.tblNazioni nzp ON ip.IdNazione = nzp.Id
	-- Unita' locale del produttore (usata al posto di sp quando f.LuogoDiProduzione=1): nella famiglia di sp
	-- (se stessa/sorelle dirette via IdParent - ancora = ISNULL(sp.IdParent, sp.Id), stesso raggruppamento
	-- dell'invariante di uspSedi_upd), la Sede con UnitaLocale=1, altrimenti la Sede Padre di sp. NON tramite
	-- IdAziendaInterna: per le Sedi Esterne quella colonna e' l'azienda interna proprietaria (tblSediEsterne.
	-- IdSedeInterna), condivisa da tutte le sedi esterne di quell'azienda interna - non la radice della
	-- famiglia di sp - e avrebbe pescato UnitaLocale=1 da una sede sorella estranea.
	OUTER APPLY (
		SELECT Id = COALESCE(
			(SELECT TOP 1 Id
			FROM dbo.tblSedi
			WHERE
				(Id = ISNULL(sp.IdParent, sp.Id) OR IdParent = ISNULL(sp.IdParent, sp.Id))
				AND UnitaLocale = 1
			),
			sp.IdParent
		)
	) rsul
			LEFT JOIN dbo.tblSedi spul ON rsul.Id = spul.Id
			LEFT JOIN dbo.tblSediIndirizzi sipul ON spul.Id = sipul.Id
			LEFT JOIN dbo.tblIndirizzi ipul ON sipul.IdIndirizzo = ipul.Id
			LEFT JOIN dbo.tblNazioni nzpul ON ipul.IdNazione = nzpul.Id
	-- Destinatario
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni da ON md.IdAutorizzazione = da.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniTipi dat ON da.IdTipo = dat.Id
			LEFT JOIN dbo.tblSedi sd ON da.IdSede = sd.Id
			LEFT JOIN dbo.tblSediIndirizzi sid ON sd.Id = sid.Id
			LEFT JOIN dbo.tblIndirizzi id_ ON sid.IdIndirizzo = id_.Id
			LEFT JOIN dbo.tblNazioni nzd ON id_.IdNazione = nzd.Id
	-- Trasportatore 1/2
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ta1 ON mt1.IdAutorizzazione = ta1.Id
			LEFT JOIN dbo.tblSedi st1 ON ta1.IdSede = st1.Id
			LEFT JOIN dbo.tblSediIndirizzi sit1 ON st1.Id = sit1.Id
			LEFT JOIN dbo.tblIndirizzi it1 ON sit1.IdIndirizzo = it1.Id
			LEFT JOIN dbo.tblNazioni nzt1 ON it1.IdNazione = nzt1.Id
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ta2 ON mt2.IdAutorizzazione = ta2.Id
			LEFT JOIN dbo.tblSedi st2 ON ta2.IdSede = st2.Id
			LEFT JOIN dbo.tblSediIndirizzi sit2 ON st2.Id = sit2.Id
			LEFT JOIN dbo.tblIndirizzi it2 ON sit2.IdIndirizzo = it2.Id
			LEFT JOIN dbo.tblNazioni nzt2 ON it2.IdNazione = nzt2.Id
	-- Intermediario 1/2
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ia1 ON mi1.IdAutorizzazione = ia1.Id
			LEFT JOIN dbo.tblSedi si1 ON ia1.IdSede = si1.Id
			LEFT JOIN dbo.tblSediIndirizzi sii1 ON si1.Id = sii1.Id
			LEFT JOIN dbo.tblIndirizzi ii1 ON sii1.IdIndirizzo = ii1.Id
			LEFT JOIN dbo.tblNazioni nzi1 ON ii1.IdNazione = nzi1.Id
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ia2 ON mi2.IdAutorizzazione = ia2.Id
			LEFT JOIN dbo.tblSedi si2 ON ia2.IdSede = si2.Id
			LEFT JOIN dbo.tblSediIndirizzi sii2 ON si2.Id = sii2.Id
			LEFT JOIN dbo.tblIndirizzi ii2 ON sii2.IdIndirizzo = ii2.Id
			LEFT JOIN dbo.tblNazioni nzi2 ON ii2.IdNazione = nzi2.Id
	-- Trasporti (dettaglio per modalita')
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiTerresti fg ON f.Id = fg.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiFerroviari ft ON f.Id = ft.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiMarittimi fn ON f.Id = fn.Id
			LEFT JOIN (
		SELECT
			mc.Id,
			ClassiPericolo = STRING_AGG(c.Codice, ';') WITHIN GROUP (ORDER BY c.Codice)
		FROM
			dbo.tblRifiutiMovimentiClassiPericolo mc
			LEFT JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
		GROUP BY
			mc.Id
	) cp ON m.Id = cp.Id
GO
