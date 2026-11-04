SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati di stampa del formulario unico degli spurghisti (art. 230, comma 5) sul PDF vidimato da Vi.Vi.FIR (modello
-- ModuloArt230c5 - Albo-2022-A). Consumata dall'hub 1_0_ViviFirApi tramite [1_0_vivifir]..uspFormulario_get_Stampa,
-- referenziata letteralmente come [4_0_ecomatico]..viewViviFirFormulari: nome e colonne vanno coordinati con l'hub
-- (ViviFirApi.Domain.Models.FormularioStampa, match per nome colonna).
-- Vi.Vi.FIR scrive già sul PDF serie e numero, denominazione, codice fiscale e iscrizione all'Albo dello spurghista,
-- le prime quattro cifre del codice EER (20 03), QR code e dati della vidimazione: la vista non li ripete.
-- Restano a penna: contenitori, caratteristiche chimico-fisiche, peso lordo e tara, data, ora e sito di arrivo del 5.1,
-- comunicazione art. 110, firme e riquadro del destinatario.
-- Quantità: il modello prevede solo kg o litri, quindi tonnellate e metri cubi si convertono (x 1000); le altre unità
-- si stampano senza casella. Lo stesso fattore vale per le quantità stimate degli indirizzi di intervento.
-- IsDeposito: operazione di carico (P), riquadro 5.1; altrimenti (Q) riquadro 5.2 con destinatario e codice R o D.
CREATE OR ALTER VIEW [dbo].[viewViviFirFormulari]
AS
SELECT
	IdFormulario = f.Id,
	FormularioNumero = m.FormularioNumero,
	ViviFirVidimato = CAST(ISNULL(m.ViviFirVidimato, 0) AS BIT),
	IsFormularioUnico = CAST(ISNULL(o.IsFormularioUnico, 0) AS BIT),
	IsDeposito = CAST(IIF(o.Operazione = 'C', 1, 0) AS BIT),
	DataEmissione = f.DataEmissione,
	RegistrazioneNumero = r.Numero,
	-- Riquadro 1: sede legale dell'azienda interna del registro, data di iscrizione all'Albo del trasportatore
	SedeLegale = UPPER(az.IndirizzoCompleto),
	AlboData = ta1.DataInizio,
	ConducenteCognomeNome = UPPER(NULLIF(LTRIM(RTRIM(CONCAT(fg.ConducenteCognome, ' ', fg.ConducenteNome))), '')),
	DataInizioTrasporto = m.DataInizioTrasporto,
	TargaMotrice = UPPER(fg.TargaMotrice),
	TargaRimorchio = UPPER(fg.TargaRimorchio),
	-- Riquadro 2: indirizzi di intervento in JSON ([{"Pos":1,"Indirizzo":"...","Quantita":12.5}])
	Indirizzi = (
		SELECT
			Pos = sp.Pos,
			Indirizzo = UPPER(CONCAT(s.NomeCompleto, IIF(NULLIF(s.IndirizzoCompleto, '') IS NULL, '', ' - ' + s.IndirizzoCompleto))),
			Quantita = sp.Quantita * IIF(m.IdUnitaMisura IN ('TN', 'MC'), 1000, 1)
		FROM
			dbo.tblRifiutiMovimentiSediProduzione sp
			INNER JOIN dbo.tblSedi s ON sp.IdSede = s.Id
		WHERE sp.Id = m.Id
		ORDER BY sp.Pos
		FOR JSON PATH
	),
	Note = f.Note,
	-- Riquadri 3 e 4
	Eer = m.IdEer,
	StatoFisico = m.IdStatoFisico,
	Quantita = m.Quantita * IIF(m.IdUnitaMisura IN ('TN', 'MC'), 1000, 1),
	UnitaMisura = CASE m.IdUnitaMisura WHEN 'TN' THEN 'KG' WHEN 'MC' THEN 'LT' ELSE m.IdUnitaMisura END,
	VerificatoInPartenza = CAST(ISNULL(f.VerificatoInPartenza, 0) AS BIT),
	-- Riquadro 5.2
	AttivitaCodice = attv.Codice,
	DestinatarioNome = UPPER(sd.NomeCompleto),
	DestinatarioCodiceFiscale = ISNULL(sd.CodiceFiscale, sd.PartitaIva),
	DestinatarioIndirizzo = UPPER(sd.IndirizzoCompleto),
	DestinatarioAutorizzazione = CASE WHEN ISNULL(da.Nessuna, 0) = 1 THEN NULL ELSE UPPER(da.Numero) END,
	DestinatarioAutorizzazioneData = CASE WHEN ISNULL(da.Nessuna, 0) = 1 THEN NULL ELSE da.DataInizio END
FROM
	dbo.tblRifiutiFormulari f
	INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
	LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
	LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento AND r.Lock < 2
	LEFT JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
	LEFT JOIN dbo.tblSedi gs ON g.IdSede = gs.Id
	LEFT JOIN dbo.tblSedi az ON gs.IdAziendaInterna = az.Id
	LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita = attv.Id
	LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni da ON md.IdAutorizzazione = da.Id
	LEFT JOIN dbo.tblSedi sd ON da.IdSede = sd.Id
	LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni ta1 ON mt1.IdAutorizzazione = ta1.Id
	LEFT JOIN dbo.tblRifiutiFormulariTrasportiTerresti fg ON f.Id = fg.Id
WHERE
	f.Lock <= 2;
GO
