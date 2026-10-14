/*
Deploy produzione 2026-10-13 - Offerte e contratti, fase magazzino: importi e fatturazione dei DDT

Da eseguire DOPO deploy_produzione_2026-10-12_offerte_contratti.sql e
deploy_produzione_2026-10-13_magazzino_etichette.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I (oppure da SSMS). Va deployato insieme all'app.

L'importo di magazzino è un listino: si sceglie sul DDT (uno solo) e ha una riga per ogni articolo o materiale.

1. Struttura: tblMagazziniCausali.IsFatturabile (solo Vendita); tblImportiMagazzino senza il mittente, con
   IdSedePartenza e IdSede; nuova tabella tblImportiRigheMagazzino (articolo o materiale della riga a quantità);
   indici IX_ImportiMagazzino_IdSede e IX_ImportiRigheMagazzino_IdArticolo.
2. Funzioni degli importi di magazzino: elenco (ufnImportiMagazzino_get_List), regola di coincidenza con il DDT
   (_get_Coincidenti), DDT considerati (_get_Documenti), importo del DDT e prezzo di ogni riga
   (_get_ApplicazioneRighe_List), riepilogo e cliente per DDT (_get_Applicazione_List), righe di fattura
   (_get_RigheFattura).
3. Funzioni della fatturazione: ufnFattureDocumenti_get_Magazzino (DDT candidati), ufnFattureDocumenti_get_Rifiuti
   (colonna SenzaImporto), ufnFattureGenera_get_Documenti (rifiuti e magazzino insieme, colonna IdModulo, parametri
   @Rifiuti e @Magazzino), ufnFattureDocumenti_get_Documento (documento del blocco "Cliente a cui fatturare").
4. Stored procedure degli importi di magazzino: uspImportiMagazzino_ins, _get, _upd, _get_List, _get_Esportazione,
   _get_Sedi_SelectList, _get_SediInterne_SelectList, _get_Etichette_SelectList, _get_Articoli_SelectList,
   _get_Materiali_SelectList, _get_Verifica, _get_Conflitti.
5. Stored procedure modificate: uspImportiRighe_upd e _get_List (articolo o materiale della riga); uspFattureDocumenti_get,
   _get_Righe, _upd, _del_Fattura, _get_Clienti_List (anche per il modulo MAG); uspFatture_ins_Genera (un DDT con
   @IdModulo = 'MAG', parametro @Magazzino); uspFatture_get_Genera_Riepilogo, _Fatture_List e _List (parametro
   @Magazzino: i DDT nella procedura automatica, solo con il modulo Magazzino attivo);
   uspMagazziniArticoli_del, uspSedi_del_SediEsterne, uspSedi_del_SediInterne e le due cancellazioni a cascata di
   sviluppo.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'tools/offerte_contratti_magazzino_struttura.sql';
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Offerte e contratti, fase magazzino: importi dei DDT e causali fatturabili.
-- L'importo di magazzino è un LISTINO: vale per una tratta e un destinatario (o per tutti) e ha una riga per ogni
-- articolo o materiale, con il suo prezzo. L'articolo non è una variabile dell'importo: sta sulla riga, come
-- nella 3.1.
--   1. tblMagazziniCausali.IsFatturabile: causali i cui DDT entrano nella fatturazione. Solo Vendita (V).
--   2. tblImportiMagazzino: variabili sede di partenza (IdSedePartenza, la sede interna del DDT), destinatario
--      (soggetto e sede: la sede si confronta con la destinazione finale della merce) ed etichetta; via il
--      mittente; IdSede NOT NULL, copia dell'azienda dell'importo, per il confronto con i documenti (come
--      tblImportiRifiuti.IdSede). Le colonne IdArticolo e IdMateriale, esistite solo in sviluppo, vengono tolte.
--   3. tblImportiRigheMagazzino: articolo oppure materiale EoW a cui si applica il prezzo di una riga a quantità
--      (tipo MA). Chiave esterna sulla riga ON DELETE CASCADE: cancellata la riga, sparisce da sola.
--   4. Indici.
-- Rieseguibile. Da eseguire dopo offerte_contratti_struttura.sql e magazzino_etichette_struttura.sql.

BEGIN TRANSACTION;

-- 1. Causali fatturabili
IF COL_LENGTH('dbo.tblMagazziniCausali', 'IsFatturabile') IS NULL
	ALTER TABLE dbo.tblMagazziniCausali ADD IsFatturabile BIT NULL;

-- 2. Variabili degli importi di magazzino
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiMagazzino_IdSede')
	DROP INDEX IX_ImportiMagazzino_IdSede ON dbo.tblImportiMagazzino;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblSedi_IdMittenteParent', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdMittenteParent;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblSedi_IdMittente', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdMittente;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblMagazziniArticoli', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblMagazziniArticoli;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblRifiutiMateriali', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblRifiutiMateriali;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMittenteParent') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMittenteParent;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMittente') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMittente;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdArticolo') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdArticolo;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMateriale') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMateriale;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdSedePartenza') IS NULL
BEGIN
	ALTER TABLE dbo.tblImportiMagazzino ADD IdSedePartenza CHAR(16) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblImportiMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdSedePartenza
		FOREIGN KEY (IdSedePartenza) REFERENCES dbo.tblSedi (Id);
END

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdSede') IS NULL
	ALTER TABLE dbo.tblImportiMagazzino ADD IdSede CHAR(16) COLLATE Latin1_General_CI_AS NULL;

-- 3. Articolo o materiale delle righe a quantità
IF OBJECT_ID('dbo.tblImportiRigheMagazzino', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblImportiRigheMagazzino (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdArticolo CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdMateriale CHAR(2) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblImportiRigheMagazzino PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblImportiRigheMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiRigheMagazzino_tblImportiRighe
		FOREIGN KEY (Id) REFERENCES dbo.tblImportiRighe (Id) ON DELETE CASCADE;
	ALTER TABLE dbo.tblImportiRigheMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiRigheMagazzino_tblMagazziniArticoli
		FOREIGN KEY (IdArticolo) REFERENCES dbo.tblMagazziniArticoli (Id);
	ALTER TABLE dbo.tblImportiRigheMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiRigheMagazzino_tblRifiutiMateriali
		FOREIGN KEY (IdMateriale) REFERENCES dbo.tblRifiutiMateriali (Id);
END

COMMIT TRANSACTION;
GO

BEGIN TRANSACTION;

-- 1. Solo Vendita
UPDATE dbo.tblMagazziniCausali
SET IsFatturabile = IIF(Id = 'V', 1, 0)
WHERE IsFatturabile IS NULL;

-- 2. Importi esistenti: l'azienda dell'importo
UPDATE m
SET IdSede = i.IdSede
FROM
	dbo.tblImportiMagazzino m
	INNER JOIN dbo.tblImporti i ON m.Id = i.Id
WHERE m.IdSede IS NULL;

-- La copia è obbligatoria, come per i rifiuti: un importo senza l'azienda non verrebbe mai letto dal confronto
-- con i DDT, e senza errori. L'indice sulla colonna va tolto prima di cambiarla e viene ricreato al punto 4
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblImportiMagazzino') AND name = 'IdSede' AND is_nullable = 1)
BEGIN
	IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiMagazzino_IdSede')
		DROP INDEX IX_ImportiMagazzino_IdSede ON dbo.tblImportiMagazzino;

	ALTER TABLE dbo.tblImportiMagazzino ALTER COLUMN IdSede CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL;
END

-- 4. Indici
-- Importi di magazzino dell'azienda con le loro variabili: il confronto con ogni DDT legge solo questi
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiMagazzino_IdSede')
	CREATE NONCLUSTERED INDEX IX_ImportiMagazzino_IdSede ON dbo.tblImportiMagazzino (IdSede)
		INCLUDE (IdSedePartenza, IdDestinatarioParent, IdDestinatario, IdEtichetta);

-- Righe di importo di un articolo: controllo di cancellazione dell'articolo e chiave esterna
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRigheMagazzino_IdArticolo')
	CREATE NONCLUSTERED INDEX IX_ImportiRigheMagazzino_IdArticolo ON dbo.tblImportiRigheMagazzino (IdArticolo)
		WHERE IdArticolo IS NOT NULL;

COMMIT TRANSACTION;
GO

SELECT Id, Nome, IsFatturabile FROM dbo.tblMagazziniCausali ORDER BY Nome;
GO

PRINT 'sql/functions/ufnImportiMagazzino_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi magazzino: righe dell'elenco e dell'esportazione (uspImportiMagazzino_get_List,
-- uspImportiMagazzino_get_Esportazione), così leggono le stesse righe con la stessa ricerca.
-- Scope: importi di magazzino attivi dell'azienda interna corrente della sessione.
-- Variabili: sede di partenza (sede interna del DDT), destinatario (soggetto e, facoltativa, una sua sede),
-- etichetta del DDT. Una variabile NULL vale "qualsiasi". Articoli e materiali stanno sulle righe dell'importo.
-- StatoValore 1 (avviso): importo senza righe, importo di un'offerta, contratto scaduto.
--   @SoloContrattoScaduto = 1: solo gli importi di un contratto confermato la cui validità è finita prima di oggi.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_List (
	@IdSessione CHAR(16),
	@Search VARCHAR(50),
	@SoloContrattoScaduto BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		i.Id,
		StatoValore = CASE
			WHEN g.Righe IS NULL THEN 1
			WHEN c.Tipo = 'O' THEN 1
			WHEN c.DataFine < CAST(GETDATE() AS DATE) THEN 1
			ELSE 0
		END,
		StatoDescrizione = CASE
			WHEN g.Righe IS NULL THEN 'Importo senza righe: non genera righe in fattura'
			WHEN c.Tipo = 'O' THEN 'Importo di un''offerta: non viene applicato nella fatturazione'
			WHEN c.DataFine < CAST(GETDATE() AS DATE) THEN 'Contratto scaduto il ' + CONVERT(VARCHAR(10), c.DataFine, 103)
			ELSE 'OK'
		END,
		i.Nome,
		i.IdPriorita,
		Priorita = p.Nome,
		Partenza = sp.NomeCompleto + ISNULL(' ' + sp.IndirizzoCompleto, ''),
		Destinatario = IIF(r.IdDestinatario IS NULL, da.NomeCompleto, ds.NomeCompleto + ISNULL(' ' + ds.IndirizzoCompleto, '')),
		Etichetta = et.Nome,
		c.Cliente,
		ContrattoTipo = c.Tipo,
		ContrattoDataInizio = c.DataInizio,
		ContrattoDataFine = c.DataFine,
		Righe = ISNULL(g.Righe, 0)
	FROM
		dbo.tblImporti i
		INNER JOIN dbo.tblSessioni s ON i.IdSede = s.IdAzienda
		INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
		LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
		LEFT JOIN dbo.tblSedi sp ON r.IdSedePartenza = sp.Id
		LEFT JOIN dbo.tblSedi da ON r.IdDestinatarioParent = da.Id
		LEFT JOIN dbo.tblSedi ds ON r.IdDestinatario = ds.Id
		LEFT JOIN dbo.tblEtichette et ON r.IdEtichetta = et.Id
		OUTER APPLY (
			SELECT Righe = COUNT(*)
			FROM dbo.tblImportiRighe x
			WHERE x.IdImporto = i.Id
			HAVING COUNT(*) > 0
		) g
		OUTER APPLY (
			SELECT TOP (1)
				oc.Tipo,
				oc.Lock,
				oc.DataInizio,
				oc.DataFine,
				Cliente = cs.NomeCompleto
			FROM
				dbo.tblOfferteContrattiImporti ci
				INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
				LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
			WHERE
				ci.IdImporto = i.Id
				AND oc.Lock <= 2
		) c
	WHERE
		s.Id = @IdSessione
		AND i.Lock = 0
		-- Solo gli importi di un contratto confermato la cui validità è finita prima di oggi
		AND
			(
			ISNULL(@SoloContrattoScaduto, 0) = 0
			OR (c.Tipo = 'C' AND c.Lock = 0 AND c.DataFine < CAST(GETDATE() AS DATE))
			)
		AND
			(
			@Search IS NULL
			OR i.Nome LIKE '%' + @Search + '%'
			OR sp.NomeCompleto LIKE '%' + @Search + '%'
			OR da.NomeCompleto LIKE '%' + @Search + '%'
			OR ds.NomeCompleto LIKE '%' + @Search + '%'
			OR et.Nome LIKE '%' + @Search + '%'
			OR c.Cliente LIKE '%' + @Search + '%'
			)
);
GO

PRINT 'sql/functions/ufnImportiMagazzino_get_Coincidenti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importi di magazzino attivi dell'azienda le cui variabili coincidono con i valori di un
-- DDT. È l'unico punto in cui è scritta la regola di coincidenza per il magazzino, come
-- ufnImportiRifiuti_get_Coincidenti per i rifiuti: la leggono la fatturazione e la verifica degli importi.
-- Funzione in linea senza TOP né sottoquery: applicata a più DDT diventa un join. Per questo non va aggiunto qui
-- nulla che dipenda dal documento oltre ai confronti delle variabili.
--
-- L'importo di magazzino è un listino: si sceglie sul DDT, non sulla riga. Articoli e materiali non sono
-- variabili: stanno sulle righe dell'importo (tblImportiRigheMagazzino) e li guarda chi calcola le righe di fattura.
-- Coincidenza: tutte le variabili indicate nell'importo coincidono con i valori (una variabile NULL vale
-- "qualsiasi").
--   @IdSedePartenza: sede interna del DDT, da cui parte la merce.
--   @IdDestinatarioParent: soggetto del destinatario del DDT.
--   @IdDestinatario: dove arriva la merce, cioè la destinazione del DDT o, se manca, il destinatario.
-- ETICHETTA: qui non viene verificata. IdEtichetta è quella indicata nell'importo (NULL = qualsiasi): chi
-- chiama scarta l'importo se la indica e il DDT non ce l'ha tra le sue.
-- Classe:
--   V  candidato: importo standard (non associato a un contratto o a un'offerta), oppure importo di un
--      contratto attivo di un cliente con @Data compresa tra inizio e fine;
--   S  scartato: importo di un contratto attivo di un cliente non valido alla data (avviso "contratto scaduto");
--   X  mai candidato: importo di un'offerta o di un contratto cancellato.
-- Ordine di scelta tra i candidati: IdPriorita DESC, Standard (prima quello di un contratto), IdImporto.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_Coincidenti (
	@IdAzienda CHAR(16),
	@Data DATE,
	@IdSedePartenza CHAR(16),
	@IdDestinatarioParent CHAR(16),
	@IdDestinatario CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		IdImporto = i.Id,
		i.IdPriorita,
		ir.IdEtichetta,
		IdOffertaContratto = oc.Id,
		IdClienteContratto = oc.IdClienteFornitore,
		Standard = CAST(IIF(ci.IdImporto IS NULL, 1, 0) AS BIT),
		Classe = CAST(CASE
			WHEN ci.IdImporto IS NULL THEN 'V'
			WHEN oc.Lock = 0 AND oc.Tipo = 'C' AND oc.ClienteFornitoreTipo = 'C' AND @Data BETWEEN oc.DataInizio AND oc.DataFine THEN 'V'
			WHEN oc.Lock = 0 AND oc.Tipo = 'C' AND oc.ClienteFornitoreTipo = 'C' AND NOT (@Data BETWEEN oc.DataInizio AND oc.DataFine) THEN 'S'
			ELSE 'X'
		END AS CHAR(1))
	FROM
		dbo.tblImportiMagazzino ir
		INNER JOIN dbo.tblImporti i ON ir.Id = i.Id
		LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
		-- FORCESEEK: il contratto si legge per chiave, come in ufnImportiRifiuti_get_Coincidenti
		LEFT JOIN dbo.tblOfferteContratti oc WITH (FORCESEEK) ON ci.IdOffertaContratto = oc.Id
	WHERE
		-- Azienda: quella copiata sulle variabili (tblImportiMagazzino.IdSede)
		ir.IdSede = @IdAzienda
		AND i.Lock = 0
		AND (ir.IdSedePartenza IS NULL OR ir.IdSedePartenza = @IdSedePartenza)
		AND (ir.IdDestinatarioParent IS NULL OR ir.IdDestinatarioParent = @IdDestinatarioParent)
		AND (ir.IdDestinatario IS NULL OR ir.IdDestinatario = @IdDestinatario)
);
GO

PRINT 'sql/functions/ufnImportiMagazzino_get_Documenti.sql';
GO
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
-- IdDestinazioneEffettiva: dove arriva la merce, cioè la destinazione del DDT o, se manca, il destinatario: è il
-- valore che si confronta con la variabile "Sede del destinatario" degli importi. IdSedeDdt è la sede interna da
-- cui parte la merce (variabile "Sede di partenza").
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
		d.IdDestinazione,
		IdDestinazioneEffettiva = ISNULL(d.IdDestinazione, d.IdDestinatario)
	FROM
		ids k
		INNER JOIN dbo.tblMagazziniMovimenti m ON k.Id = m.Id
		INNER JOIN dbo.tblMagazziniDdt d ON m.Id = d.IdMovimento
		LEFT JOIN dbo.tblMagazziniCausali ca ON d.IdCausale = ca.Id
		LEFT JOIN dbo.tblSedi sd ON d.IdDestinatario = sd.Id
);
GO

PRINT 'sql/functions/ufnImportiMagazzino_get_ApplicazioneRighe_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: per ogni riga dei DDT, l'importo applicato al DDT e la riga dell'importo che
-- dà il prezzo dell'articolo o del materiale (regole O5M di docs/regole/offerte-contratti.md). Una riga per
-- ogni riga articolo o EoW del DDT; le righe descrittive del DDT non entrano.
--   Parametri: quelli di ufnImportiMagazzino_get_Documenti. @SoloFatturabili = 1: solo i DDT confermati e
--        fatturabili; il confronto non viene fatto per gli altri.
-- Importo: UNO SOLO PER DDT, lo stesso su tutte le sue righe: tra gli importi di magazzino attivi dell'azienda, il
-- primo le cui variabili coincidono con il DDT (ufnImportiMagazzino_get_Coincidenti: sede di partenza,
-- destinatario, destinazione; l'etichetta è una di quelle del DDT), in ordine di priorità decrescente e, a parità,
-- prima quello di un contratto e poi quello standard. La validità del contratto è alla data del DDT.
-- IdRigaImporto: la riga a quantità (tipo MA) dell'importo che indica l'articolo o il materiale della riga del DDT.
-- NULL se il DDT non ha un importo, o se l'importo non ha una riga per quell'articolo: in quel caso il DDT non è
-- fatturabile. Non si cerca il prezzo in un altro importo.
-- Riga articolo: unità di misura dell'articolo. Riga EoW: chilogrammi.
-- IdImportoScartato: importo di un contratto che coinciderebbe con il DDT ma non è valido alla sua data.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@SoloFatturabili BIT)
RETURNS TABLE
AS
RETURN
(
	WITH scelta AS (
		-- Per ogni DDT gli importi che coincidono: N = 1 è il primo candidato (classe V) in ordine di scelta, o
		-- una riga senza candidato; IdImportoScartato il primo degli scartati (classe S). Un importo che indica
		-- un'etichetta che il DDT non ha non coincide: passa alla classe X
		SELECT
			doc.Id,
			IdImporto = IIF(q.Classe = 'V', c.IdImporto, NULL),
			IdOffertaContratto = IIF(q.Classe = 'V', c.IdOffertaContratto, NULL),
			IdClienteContratto = IIF(q.Classe = 'V', c.IdClienteContratto, NULL),
			IdImportoScartato = FIRST_VALUE(IIF(q.Classe = 'S', c.IdImporto, NULL)) OVER (
				PARTITION BY doc.Id
				ORDER BY IIF(q.Classe = 'S', 0, 1), c.IdPriorita DESC, c.IdImporto
				ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
			N = ROW_NUMBER() OVER (
				PARTITION BY doc.Id
				ORDER BY IIF(q.Classe = 'V', 0, 1), c.IdPriorita DESC, c.Standard, c.IdImporto)
		FROM
			dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
			OUTER APPLY dbo.ufnImportiMagazzino_get_Coincidenti(doc.IdAzienda, doc.[Data], doc.IdSedeDdt, doc.IdDestinatarioParent, doc.IdDestinazioneEffettiva) c
			-- Al massimo una riga: (Id, IdEtichetta) è la chiave primaria
			LEFT JOIN dbo.tblMagazziniDdtEtichette e ON e.Id = doc.IdDdt
													 AND e.IdEtichetta = c.IdEtichetta
			CROSS APPLY (SELECT Classe = IIF(c.IdEtichetta IS NOT NULL AND e.Id IS NULL, 'X', c.Classe)) q
		WHERE
			ISNULL(@SoloFatturabili, 0) = 0
			OR (doc.Lock = 0 AND doc.IsFatturabile = 1)
	),
	righe AS (
		SELECT
			r.IdMovimento,
			IdRiga = r.Id,
			IsEoW = CAST(0 AS BIT),
			r.Pos,
			r.IdArticolo,
			IdMateriale = CAST(NULL AS CHAR(2)),
			Voce = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(200)),
			r.Quantita,
			IdUnitaMisura = a.IdUnitaMisura
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
		WHERE r.Lock <= 2

		UNION ALL

		SELECT
			r.IdMovimento,
			IdRiga = r.Id,
			IsEoW = CAST(1 AS BIT),
			r.Pos,
			IdArticolo = CAST(NULL AS CHAR(16)),
			r.IdMateriale,
			Voce = CAST(ma.Nome AS VARCHAR(200)),
			r.Quantita,
			IdUnitaMisura = CAST('KG' AS CHAR(2))
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
			LEFT JOIN dbo.tblRifiutiMateriali ma ON r.IdMateriale = ma.Id
		WHERE r.Lock <= 2
	)
	SELECT
		g.IdMovimento,
		g.IdRiga,
		g.IsEoW,
		g.Pos,
		g.IdArticolo,
		g.IdMateriale,
		g.Voce,
		g.Quantita,
		g.IdUnitaMisura,
		s.IdImporto,
		s.IdOffertaContratto,
		s.IdClienteContratto,
		s.IdImportoScartato,
		IdRigaImporto = p.Id
	FROM
		scelta s
		INNER JOIN righe g ON s.Id = g.IdMovimento
		OUTER APPLY (
			-- Riga a quantità dell'importo per l'articolo o il materiale di questa riga del DDT (una sola: lo
			-- garantisce uspImportiRighe_upd)
			SELECT TOP (1) x.Id
			FROM
				dbo.tblImportiRighe x
				INNER JOIN dbo.tblImportiRigheMagazzino xm ON x.Id = xm.Id
			WHERE
				x.IdImporto = s.IdImporto
				AND x.IdTipo = 'MA'
				AND x.Importo IS NOT NULL
				AND ISNULL(x.MinimoFatturabile, 0) = 0
				AND (xm.IdArticolo = g.IdArticolo OR xm.IdMateriale = g.IdMateriale)
			ORDER BY ISNULL(x.Pos, 0), x.Id
		) p
	WHERE s.N = 1
);
GO

PRINT 'sql/functions/ufnImportiMagazzino_get_Applicazione_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: per ogni DDT, l'importo applicato (uno solo: l'importo di magazzino è un
-- listino), il cliente a cui fatturarlo e il riepilogo delle sue righe
-- (ufnImportiMagazzino_get_ApplicazioneRighe_List). Una riga per movimento con un DDT; è l'analogo di
-- ufnImportiRifiuti_get_Applicazione_List.
--   Parametri: quelli di ufnImportiMagazzino_get_ApplicazioneRighe_List.
-- Righe: righe articolo ed EoW del DDT. RigheSenzaImporto: quelle il cui articolo o materiale non ha una riga
-- nell'importo applicato (tutte, se nessun importo coincide): se ce n'è anche una sola il DDT intero non viene
-- fatturato. Un DDT senza righe non ha importo.
-- Cliente (ClienteOrigine): D quello indicato sul DDT (tblFattureDocumenti), altrimenti C quello del contratto
-- dell'importo applicato, altrimenti P la scheda cliente attiva del soggetto destinatario (per un importo
-- standard). NULL se nessuno dei tre.
-- IdImportoScartato: importo di un contratto che coinciderebbe con il DDT ma non è valido alla sua data.
-- IdFattura: solo se la fattura non è cancellata. IsPreFattura, IdClientePreFattura: come per i rifiuti.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_Applicazione_List (
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
		doc.Id,
		doc.IdDdt,
		doc.[Data],
		doc.Numero,
		doc.Sezionale,
		doc.Lock,
		doc.IdAzienda,
		doc.IdSedeDdt,
		doc.IsFatturabile,
		doc.IdDestinatario,
		doc.IdDestinatarioParent,
		doc.IdDestinazione,
		IdClienteIndicato = d.IdClienteFornitore,
		NonFatturabile = CAST(ISNULL(d.NonFatturabile, 0) AS BIT),
		IdFattura = f.Id,
		IsPreFattura = CAST(IIF(f.IdTipo = 'TD00', 1, 0) AS BIT),
		IdClientePreFattura = IIF(f.IdTipo = 'TD00', f.IdClienteFornitore, NULL),
		Righe = ISNULL(g.Righe, 0),
		RigheSenzaImporto = ISNULL(g.RigheSenzaImporto, 0),
		g.IdImporto,
		g.IdOffertaContratto,
		g.IdImportoScartato,
		IdClienteFornitore = COALESCE(d.IdClienteFornitore, g.IdClienteContratto, cp.Id),
		ClienteOrigine = CAST(CASE
			WHEN d.IdClienteFornitore IS NOT NULL THEN 'D'
			WHEN g.IdClienteContratto IS NOT NULL THEN 'C'
			WHEN cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1))
	FROM
		dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
		LEFT JOIN dbo.tblFattureDocumenti d ON doc.Id = d.Id
		LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
								  AND f.Lock IN (0, 2)
		LEFT JOIN (
			-- Importo, contratto e cliente sono gli stessi su tutte le righe del DDT
			SELECT
				r.IdMovimento,
				Righe = COUNT(*),
				RigheSenzaImporto = SUM(IIF(r.IdRigaImporto IS NULL, 1, 0)),
				IdImporto = MIN(r.IdImporto),
				IdOffertaContratto = MIN(r.IdOffertaContratto),
				IdClienteContratto = MIN(r.IdClienteContratto),
				IdImportoScartato = MIN(r.IdImportoScartato)
			FROM dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, @IdAzienda, @DataDa, @DataA, @SoloFatturabili) r
			GROUP BY r.IdMovimento
		) g ON doc.Id = g.IdMovimento
		OUTER APPLY (
			SELECT TOP (1) c.Id
			FROM dbo.tblClientiFornitori c
			WHERE
				c.IdSede = doc.IdDestinatarioParent
				AND c.IdAziendaInterna = doc.IdAzienda
				AND c.Tipo = 'C'
				AND c.Lock = 0
			ORDER BY c.Id
		) cp
	WHERE
		ISNULL(@SoloFatturabili, 0) = 0
		OR (doc.Lock = 0 AND doc.IsFatturabile = 1)
);
GO

PRINT 'sql/functions/ufnImportiMagazzino_get_RigheFattura.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: righe di fattura che l'importo applicato al DDT del movimento @Id genera.
-- Funzione in linea: si può usare con CROSS APPLY su più DDT. Nessuna riga se il DDT non ha un importo.
--
-- Righe a quantità (tipo MA, con l'articolo o il materiale): una per ogni riga del DDT con quell'articolo o quel
-- materiale, nell'ordine delle righe del DDT, con la quantità e l'unità di misura della riga (riga articolo:
-- unità dell'articolo; riga EoW: chilogrammi). Una riga a quantità il cui articolo non è nel DDT non entra.
-- Righe per movimento (tipo MM) e righe di sola descrizione (importo NULL): una volta per DDT, dopo le righe a
-- quantità, nell'ordine delle righe dell'importo; quantità 1 (unità NR) se hanno un importo.
-- Minimo fatturabile (al massimo una riga per importo): è il minimo da fatturare per il DDT. Si confronta con la
-- somma degli imponibili delle altre righe (se la riga del minimo è di tipo MM, di tutte; altrimenti di quelle a
-- quantità): se il minimo è maggiore la riga entra con quantità 1 e importo pari alla differenza.
-- Testo: i segnaposto #1 articolo o materiale della riga del DDT (vuoto sulle righe "una volta per DDT"),
-- #2 numero del DDT, #3 data del DDT, #4 destinatario, #5 destinazione (se non indicata, il destinatario).
-- Aliquota IVA: quella della riga dell'importo, altrimenti quella della scheda del cliente @IdClienteFornitore.
-- Ordine: PosDdt (0 per le righe "una volta per DDT", che vanno in coda con Gruppo = 1), poi Pos.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_RigheFattura (
	@Id CHAR(16),
	@IdClienteFornitore CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH testata AS (
		SELECT
			doc.Id,
			IdAliquotaIvaCliente = c.IdAliquotaIva,
			DdtNumero = CAST(CAST(doc.Numero AS VARCHAR(10)) + ISNULL('/' + doc.Sezionale, '') AS VARCHAR(20)),
			DdtData = CONVERT(VARCHAR(10), doc.[Data], 103),
			Destinatario = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
			Destinazione = sz.NomeCompleto + ISNULL(' ' + sz.IndirizzoCompleto, '')
		FROM
			dbo.ufnImportiMagazzino_get_Documenti(@Id, NULL, NULL, NULL) doc
			LEFT JOIN dbo.tblClientiFornitori c ON c.Id = @IdClienteFornitore
			LEFT JOIN dbo.tblSedi sd ON doc.IdDestinatario = sd.Id
			LEFT JOIN dbo.tblSedi sz ON doc.IdDestinazioneEffettiva = sz.Id
	),
	ddt AS (
		SELECT
			x.IdRiga,
			PosDdt = ISNULL(x.Pos, 0),
			x.IdImporto,
			x.IdRigaImporto,
			x.Voce,
			x.Quantita,
			x.IdUnitaMisura
		FROM dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, NULL, NULL, NULL, 0) x
		WHERE x.IdImporto IS NOT NULL
	),
	righe AS (
		-- Righe a quantità: una per ogni riga del DDT che ha il suo prezzo nell'importo
		SELECT
			Gruppo = 0,
			IdRigaDdt = a.IdRiga,
			a.PosDdt,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(0 AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(a.Quantita AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(a.IdUnitaMisura AS CHAR(2)),
			a.Voce
		FROM
			ddt a
			INNER JOIN dbo.tblImportiRighe g ON a.IdRigaImporto = g.Id

		UNION ALL

		-- Righe per movimento, di sola descrizione e minimo fatturabile: una volta per DDT
		SELECT
			Gruppo = 1,
			IdRigaDdt = CAST(NULL AS CHAR(16)),
			PosDdt = 0,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(ISNULL(g.MinimoFatturabile, 0) AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(IIF(g.Importo IS NULL, NULL, 1) AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(IIF(g.Importo IS NULL, NULL, 'NR') AS CHAR(2)),
			Voce = CAST(NULL AS VARCHAR(200))
		FROM
			(SELECT DISTINCT IdImporto FROM ddt) a
			INNER JOIN dbo.tblImportiRighe g ON a.IdImporto = g.IdImporto
		WHERE
			g.Importo IS NULL
			OR g.IdTipo = 'MM'
			OR ISNULL(g.MinimoFatturabile, 0) = 1
	),
	minimo AS (
		-- Somma degli imponibili delle righe con cui si confronta il minimo fatturabile
		SELECT
			Altre = ISNULL((
				SELECT SUM(ROUND(x.Prezzo * x.Quantita, 2))
				FROM righe x
				WHERE
					x.MinimoFatturabile = 0
					AND x.Quantita IS NOT NULL
					AND (m.IdTipo = 'MM' OR x.IdTipo <> 'MM')
			), 0)
		FROM righe m
		WHERE
			m.MinimoFatturabile = 1
			AND m.Prezzo IS NOT NULL
	)
	SELECT
		t.Gruppo,
		t.IdRigaDdt,
		t.PosDdt,
		t.Id,
		t.Pos,
		t.IdTipo,
		t.MinimoFatturabile,
		SolaDescrizione = CAST(IIF(t.Prezzo IS NULL, 1, 0) AS BIT),
		Descrizione = CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(d.Descrizione, ''),
			'#1', ISNULL(t.Voce, '')),
			'#2', ISNULL(h.DdtNumero, '')),
			'#3', ISNULL(h.DdtData, '__/__/____')),
			'#4', ISNULL(h.Destinatario, '')),
			'#5', ISNULL(h.Destinazione, '')) AS VARCHAR(1000)),
		t.Quantita,
		t.IdUnitaMisura,
		Importo = CAST(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo) AS DECIMAL(18, 4)),
		Imponibile = CAST(ROUND(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo * t.Quantita), 2) AS DECIMAL(18, 2)),
		IdAliquotaIva = ISNULL(d.IdAliquotaIva, h.IdAliquotaIvaCliente),
		d.IdConto
	FROM
		righe t
		CROSS JOIN testata h
		LEFT JOIN dbo.tblImportiRigheDettagli d ON t.Id = d.Id
		LEFT JOIN minimo n ON t.MinimoFatturabile = 1
	WHERE
		-- Sola descrizione: sempre
		t.Prezzo IS NULL
		-- Riga normale: sempre (ha una quantità)
		OR t.MinimoFatturabile = 0
		-- Minimo fatturabile: solo per la differenza non raggiunta dalle altre righe
		OR (t.MinimoFatturabile = 1 AND t.Prezzo > n.Altre)
);
GO

PRINT 'sql/functions/ufnFattureDocumenti_get_Rifiuti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: registrazioni dei rifiuti candidate, con l'importo e il cliente che
-- verrebbero applicati (ufnImportiRifiuti_get_Applicazione_List: il confronto con gli importi è fatto una volta
-- per tutte le registrazioni; le righe si leggono con ufnImportiRifiuti_get_RigheImporto) e l'esito. Serve sia alla verifica
-- (uspFatture_get_Genera_List) sia alla generazione (uspFatture_ins_Genera), così leggono le stesse righe.
--   @Id: una sola registrazione ("Genera la fattura" dalla scheda); altrimenti @IdAzienda e l'intervallo di date.
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente (quelli che gli verrebbero fatturati).
--   @IncludiPreFatture = 1: rientrano anche i documenti già in una pre-fattura (IdPreFattura), che verrà
--        convertita: in fattura vanno le righe della pre-fattura, non quelle ricalcolate dagli importi, e il
--        cliente è quello della pre-fattura.
-- Candidate: registrazioni confermate (Lock = 0) di un'operazione fatturabile, non rettifiche, di un registro
-- di una sede che la sessione vede (titolarità), non ancora in una fattura (le pre-fatture non contano come
-- fattura quando si includono).
-- Fatturabile = 1: non annullata, non "Non fatturabile", con un importo che coincide, un
-- cliente determinato, almeno una riga e l'aliquota IVA su ogni riga con importo (della riga o della scheda del
-- cliente). Stessa condizione di uspFattureDocumenti_get ("Verifica importo e
-- cliente" sulla scheda): vanno tenute allineate. Un documento in una pre-fattura inclusa è sempre fatturabile.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Rifiuti (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		a.[Data],
		a.Numero,
		a.IdAzienda,
		a.IdProduttore,
		a.IdEer,
		a.IdUnitaMisura,
		a.Quantita,
		a.IsAnnullata,
		a.NonFatturabile,
		IdPreFattura = IIF(a.IsPreFattura = 1, a.IdFattura, NULL),
		a.IdImporto,
		a.IdOffertaContratto,
		IdClienteFornitore = IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore),
		a.ClienteOrigine,
		a.IdImportoScartato,
		-- Nessun importo coincide (per i DDT di magazzino: con almeno una riga)
		SenzaImporto = CAST(IIF(a.IdImporto IS NULL, 1, 0) AS BIT),
		Righe = ISNULL(t.Righe, 0),
		Totale = t.Totale,
		SenzaIva = ISNULL(t.SenzaIva, 0),
		Fatturabile = CAST(CASE
			WHEN a.IsPreFattura = 1 THEN 1
			WHEN a.IsAnnullata = 0 AND a.NonFatturabile = 0
				AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0 THEN 1
			ELSE 0
		END AS BIT)
	FROM
		-- Registrazioni confermate di un'operazione fatturabile, non rettifiche, di @Id o dell'azienda nel
		-- periodo, con l'importo e il cliente applicati: il confronto è fatto una volta per tutte
		dbo.ufnImportiRifiuti_get_Applicazione_List(@Id, @IdAzienda, @DataDa, @DataA, 1) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
		OUTER APPLY (
			SELECT
				Totale = SUM(ISNULL(q.Imponibile, 0)),
				Righe = COUNT(*),
				SenzaIva = SUM(IIF(q.SolaDescrizione = 0 AND q.IdAliquotaIva IS NULL, 1, 0))
			FROM dbo.ufnImportiRifiuti_get_RigheImporto(a.Id, a.IdImporto, a.IdClienteFornitore) q
		) t
	WHERE
		-- Non ancora in una fattura; in una pre-fattura solo se si includono
			(
			a.IdFattura IS NULL
			OR (a.IsPreFattura = 1 AND @IncludiPreFatture = 1)
			)
		AND
			(
			@IdClienteFornitore IS NULL
			OR IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore) = @IdClienteFornitore
			)
);
GO

PRINT 'sql/functions/ufnFattureDocumenti_get_Magazzino.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: DDT di magazzino candidati, con gli importi e il cliente che verrebbero
-- applicati (ufnImportiMagazzino_get_Applicazione_List: un solo importo per DDT) e l'esito. Stesse
-- colonne e stessi parametri di ufnFattureDocumenti_get_Rifiuti: le due si leggono insieme in
-- ufnFattureGenera_get_Documenti. Id è l'Id del movimento, Data e Numero quelli del DDT.
--   @Id: un solo movimento ("Genera la fattura" dalla scheda); altrimenti @IdAzienda e l'intervallo di date.
-- Candidati: DDT emessi e confermati di un movimento di scarico con una causale fatturabile, di una sede che la
-- sessione vede, non ancora in una fattura (le pre-fatture non contano come fattura quando si includono).
-- IdProduttore: qui è il destinatario del DDT, la sede per il raggruppamento "una fattura per sede".
-- IdImporto, IdOffertaContratto: quelli dell'importo applicato al DDT.
-- SenzaImporto = 1: il DDT non ha righe, nessun importo coincide, oppure l'importo applicato non ha una riga per
-- uno dei suoi articoli o materiali.
-- Fatturabile = 1: non "Non fatturabile", un importo con una riga per ogni articolo, un cliente determinato, almeno una riga
-- di fattura e l'aliquota IVA su ogni riga con importo. Stessa condizione di uspFattureDocumenti_get: vanno tenute
-- allineate. Un DDT in una pre-fattura inclusa è sempre fatturabile.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Magazzino (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		a.[Data],
		a.Numero,
		a.IdAzienda,
		IdProduttore = a.IdDestinatario,
		IdEer = CAST(NULL AS CHAR(6)),
		IdUnitaMisura = CAST(NULL AS CHAR(2)),
		Quantita = CAST(NULL AS DECIMAL(18, 2)),
		IsAnnullata = CAST(0 AS BIT),
		a.NonFatturabile,
		IdPreFattura = IIF(a.IsPreFattura = 1, a.IdFattura, NULL),
		a.IdImporto,
		a.IdOffertaContratto,
		IdClienteFornitore = IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore),
		a.ClienteOrigine,
		a.IdImportoScartato,
		SenzaImporto = CAST(IIF(a.Righe = 0 OR a.IdImporto IS NULL OR a.RigheSenzaImporto > 0, 1, 0) AS BIT),
		Righe = ISNULL(t.Righe, 0),
		Totale = t.Totale,
		SenzaIva = ISNULL(t.SenzaIva, 0),
		Fatturabile = CAST(CASE
			WHEN a.IsPreFattura = 1 THEN 1
			WHEN a.NonFatturabile = 0 AND a.Righe > 0 AND a.IdImporto IS NOT NULL AND a.RigheSenzaImporto = 0
				AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0 THEN 1
			ELSE 0
		END AS BIT)
	FROM
		dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, @IdAzienda, @DataDa, @DataA, 1) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
		OUTER APPLY (
			SELECT
				Totale = SUM(ISNULL(q.Imponibile, 0)),
				Righe = COUNT(*),
				SenzaIva = SUM(IIF(q.SolaDescrizione = 0 AND q.IdAliquotaIva IS NULL, 1, 0))
			FROM dbo.ufnImportiMagazzino_get_RigheFattura(a.Id, a.IdClienteFornitore) q
		) t
	WHERE
		-- Non ancora in una fattura; in una pre-fattura solo se si includono
			(
			a.IdFattura IS NULL
			OR (a.IsPreFattura = 1 AND @IncludiPreFatture = 1)
			)
		AND
			(
			@IdClienteFornitore IS NULL
			OR IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore) = @IdClienteFornitore
			)
);
GO

PRINT 'sql/functions/ufnFattureGenera_get_Documenti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: i documenti candidati, cioè le registrazioni dei rifiuti
-- (ufnFattureDocumenti_get_Rifiuti, con @Rifiuti = 1) e i DDT di magazzino (ufnFattureDocumenti_get_Magazzino,
-- con @Magazzino = 1), con in più ciò che serve a raggrupparli in fatture e a riepilogarli. IdModulo dice da
-- quale dei due viene il documento (RIF, MAG): per un DDT, Id è l'Id del movimento.
-- La leggono il riepilogo (uspFatture_get_Genera_Riepilogo), l'anteprima delle fatture
-- (uspFatture_get_Genera_Fatture_List), l'elenco di dettaglio (uspFatture_get_Genera_List) e la generazione
-- (uspFatture_ins_Genera): così contano, mostrano e generano le stesse cose.
--   GruppoSede, GruppoContratto: con il cliente dicono in quale fattura va il documento, secondo il
--        raggruppamento della scheda del cliente (tblClientiFornitori.IdRaggruppamento): S una fattura per sede
--        del produttore, T una per contratto, altrimenti una per cliente (entrambi NULL). I documenti di una
--        stessa pre-fattura restano insieme: prendono il gruppo del suo primo documento (data, numero).
--   PrimoDellaPreFattura: il primo documento della sua pre-fattura, che ne porta le righe e l'imponibile.
--   Imponibile: quello delle righe dell'importo applicato; per una pre-fattura il suo imponibile, una volta
--        sola, sul primo documento (NULL sugli altri).
--   Esito: F fatturabile; S fatturabile con l'importo standard perché il contratto non è valido alla data;
--        P in una pre-fattura che verrà convertita; A annullata; N indicata come non fatturabile; I nessun
--        importo coincide; C cliente non determinato; R l'importo non ha righe applicabili; V manca
--        l'aliquota IVA. F, S e P entrano in una fattura (Fatturabile = 1).
CREATE OR ALTER FUNCTION dbo.ufnFattureGenera_get_Documenti (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT,
	@Rifiuti BIT,
	@Magazzino BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		t.Id,
		t.IdModulo,
		t.[Data],
		t.Numero,
		t.IdAzienda,
		t.IdProduttore,
		t.IdEer,
		t.IdUnitaMisura,
		t.Quantita,
		t.IsAnnullata,
		t.NonFatturabile,
		t.IdPreFattura,
		t.IdImporto,
		t.IdOffertaContratto,
		t.IdClienteFornitore,
		t.ClienteOrigine,
		t.IdImportoScartato,
		t.Righe,
		t.Totale,
		t.SenzaIva,
		t.Fatturabile,
		PrimoDellaPreFattura = CAST(IIF(t.IdPreFattura IS NOT NULL AND t.N = 1, 1, 0) AS BIT),
		GruppoSede = IIF(t.IdPreFattura IS NULL, t.GruppoSedeProprio,
			FIRST_VALUE(t.GruppoSedeProprio) OVER (PARTITION BY t.IdPreFattura ORDER BY t.[Data], t.Numero, t.Id)),
		GruppoContratto = IIF(t.IdPreFattura IS NULL, t.GruppoContrattoProprio,
			FIRST_VALUE(t.GruppoContrattoProprio) OVER (PARTITION BY t.IdPreFattura ORDER BY t.[Data], t.Numero, t.Id)),
		Imponibile = CASE
			WHEN t.IdPreFattura IS NULL THEN t.Totale
			WHEN t.N = 1 THEN pf.Imponibile
		END,
		Esito = CAST(CASE
			WHEN t.IdPreFattura IS NOT NULL THEN 'P'
			WHEN t.Fatturabile = 1 AND t.IdImportoScartato IS NOT NULL AND t.IdOffertaContratto IS NULL THEN 'S'
			WHEN t.Fatturabile = 1 THEN 'F'
			WHEN t.IsAnnullata = 1 THEN 'A'
			WHEN t.NonFatturabile = 1 THEN 'N'
			WHEN t.SenzaImporto = 1 THEN 'I'
			WHEN t.IdClienteFornitore IS NULL THEN 'C'
			WHEN t.Righe = 0 THEN 'R'
			ELSE 'V'
		END AS CHAR(1))
	FROM
		(
			SELECT
				d.Id,
				d.IdModulo,
				d.[Data],
				d.Numero,
				d.IdAzienda,
				d.IdProduttore,
				d.IdEer,
				d.IdUnitaMisura,
				d.Quantita,
				d.IsAnnullata,
				d.NonFatturabile,
				d.IdPreFattura,
				d.IdImporto,
				d.IdOffertaContratto,
				d.IdClienteFornitore,
				d.ClienteOrigine,
				d.IdImportoScartato,
				d.SenzaImporto,
				d.Righe,
				d.Totale,
				d.SenzaIva,
				d.Fatturabile,
				GruppoSedeProprio = IIF(c.IdRaggruppamento = 'S', d.IdProduttore, NULL),
				GruppoContrattoProprio = IIF(c.IdRaggruppamento = 'T', d.IdOffertaContratto, NULL),
				-- Posizione del documento nella sua pre-fattura (conta solo dove IdPreFattura non è NULL)
				N = ROW_NUMBER() OVER (PARTITION BY d.IdPreFattura ORDER BY d.[Data], d.Numero, d.Id)
			FROM
				(
					SELECT IdModulo = CAST('RIF' AS CHAR(3)), Id, [Data], Numero, IdAzienda, IdProduttore, IdEer, IdUnitaMisura, Quantita, IsAnnullata, NonFatturabile, IdPreFattura, IdImporto, IdOffertaContratto, IdClienteFornitore, ClienteOrigine, IdImportoScartato, SenzaImporto, Righe, Totale, SenzaIva, Fatturabile
					FROM dbo.ufnFattureDocumenti_get_Rifiuti(@IdSessione, @IdAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture)
					WHERE @Rifiuti = 1

					UNION ALL

					SELECT IdModulo = CAST('MAG' AS CHAR(3)), Id, [Data], Numero, IdAzienda, IdProduttore, IdEer, IdUnitaMisura, Quantita, IsAnnullata, NonFatturabile, IdPreFattura, IdImporto, IdOffertaContratto, IdClienteFornitore, ClienteOrigine, IdImportoScartato, SenzaImporto, Righe, Totale, SenzaIva, Fatturabile
					FROM dbo.ufnFattureDocumenti_get_Magazzino(@IdSessione, @IdAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture)
					WHERE @Magazzino = 1
				) d
				LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
		) t
		OUTER APPLY dbo.ufnFatture_get_Totali(IIF(t.N = 1, t.IdPreFattura, NULL)) pf
);
GO

PRINT 'sql/functions/ufnFattureDocumenti_get_Documento.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Blocco "Cliente a cui fatturare": il documento @Id del modulo @IdModulo (RIF registrazione dei rifiuti, MAG
-- movimento di magazzino con il suo DDT), se la sessione lo vede (titolarità sulla sede del registro o del DDT).
-- Una riga al massimo. Serve alle SP uspFattureDocumenti_*, così permessi e dati di base del documento sono
-- letti nello stesso modo per ogni modulo.
-- IsFatturabile: registrazione di un'operazione fatturabile e non rettifica; DDT emesso di un movimento di
-- scarico con una causale fatturabile. Lock: 0 se il documento è confermato.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Documento (
	@Id CHAR(16),
	@IdModulo CHAR(3),
	@IdSessione CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		IdModulo = CAST('RIF' AS CHAR(3)),
		a.IdAzienda,
		Lock = CAST(a.Lock AS TINYINT),
		IsFatturabile = CAST(IIF(a.IsFatturabile = 1 AND a.IsRettifica = 0, 1, 0) AS BIT),
		a.IdFattura,
		a.IdClienteIndicato
	FROM
		dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
	WHERE @IdModulo = 'RIF'

	UNION ALL

	SELECT
		a.Id,
		IdModulo = CAST('MAG' AS CHAR(3)),
		a.IdAzienda,
		a.Lock,
		a.IsFatturabile,
		a.IdFattura,
		a.IdClienteIndicato
	FROM
		dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
	WHERE @IdModulo = 'MAG'
);
GO

PRINT 'sql/procedures/uspImportiMagazzino_ins.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo importo di magazzino, in bozza (Lock = 2), dell'azienda interna corrente della sessione, con priorità Media.
-- @IdOffertaContratto (facoltativo): l'importo nasce già associato a quel contratto o a quell'offerta ("Nuovo
-- importo" dalla scheda del contratto); serve anche il permesso di modifica sui contratti (OCC).
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_ins
	@IdSessione CHAR(16) = NULL,
	@IdOffertaContratto CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOffertaContratto = NULLIF(NULLIF(LTRIM(RTRIM(@IdOffertaContratto)), ''), REPLICATE('0', 16));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo appartiene all'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Contratto o offerta a cui associare l'importo: della stessa azienda, attivo o in bozza
		IF @IdOffertaContratto IS NOT NULL
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCC',
				@Permesso = @permesso OUTPUT;
			IF 2 > @permesso OR NOT EXISTS (
				SELECT 1
				FROM dbo.tblOfferteContratti
				WHERE
					Id = @IdOffertaContratto
					AND IdSede = @idAzienda
					AND Lock <= 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
				GOTO BRANCH_END;
			END
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblImporti (Id, IdSede, IdPriorita, Lock)
			VALUES (@returnId, @idAzienda, 4, 2);

			-- IdSede: copia dell'azienda dell'importo (che non cambia più), per il confronto con i DDT
			-- (ufnImportiMagazzino_get_Coincidenti)
			INSERT dbo.tblImportiMagazzino (Id, IdSede)
			VALUES (@returnId, @idAzienda);

			IF @IdOffertaContratto IS NOT NULL
				INSERT dbo.tblOfferteContrattiImporti (IdOffertaContratto, IdImporto)
				VALUES (@IdOffertaContratto, @returnId);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda di un importo di magazzino dell'azienda interna corrente della sessione (attivo o in bozza).
-- Contratto: descrizione del contratto o dell'offerta a cui l'importo è associato, NULL se è un importo standard.
-- ContrattoScaduto = 1: è associato a un contratto la cui validità è finita prima di oggi (avviso nella scheda).
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
				INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			WHERE
				i.Id = @Id
				AND e.Id = @IdSessione
				AND i.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			i.Id,
			i.IdSede,
			i.Nome,
			i.IdPriorita,
			i.Lock,
			r.IdSedePartenza,
			r.IdDestinatarioParent,
			r.IdDestinatario,
			r.IdEtichetta,
			Contratto = c.Contratto,
			c.IdOffertaContratto,
			ContrattoTipo = c.Tipo,
			ContrattoDataFine = c.DataFine,
			-- Contratto (non offerta) confermato la cui validità è finita prima di oggi: la scheda lo segnala
			ContrattoScaduto = CAST(IIF(c.Tipo = 'C' AND c.Lock = 0 AND c.DataFine < CAST(GETDATE() AS DATE), 1, 0) AS BIT)
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
			OUTER APPLY (
				SELECT TOP (1)
					IdOffertaContratto = oc.Id,
					oc.Tipo,
					oc.DataFine,
					oc.Lock,
					Contratto = IIF(oc.Tipo = 'O', 'Offerta', 'Contratto')
						+ ISNULL(' ' + cs.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				FROM
					dbo.tblOfferteContrattiImporti ci
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
					LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
					LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
				WHERE
					ci.IdImporto = i.Id
					AND oc.Lock <= 2
			) c
		WHERE i.Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un importo di magazzino e conferma la bozza (Lock 2 -> 0).
-- L'importo di magazzino è un listino: gli articoli e i materiali stanno sulle sue righe (uspImportiRighe_upd).
-- Le variabili (sede di partenza, destinatario, etichetta) sono facoltative: una variabile non indicata vale
-- "qualsiasi" nel confronto con il DDT.
-- Sede di partenza: una sede interna dell'azienda, quella da cui parte la merce (la sede del DDT).
-- Destinatario: @IdDestinatarioParent è il soggetto (tutte le sue sedi), @IdDestinatario una sua sede precisa,
-- che si confronta con la destinazione finale della merce. Indicata la sola sede, il soggetto si ricava dalla sede.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdPriorita INT = NULL,
	@IdSedePartenza CHAR(16) = NULL,
	@IdDestinatarioParent CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @IdSedePartenza = NULLIF(NULLIF(LTRIM(RTRIM(@IdSedePartenza)), ''), @idSediciZeri);
		SET @IdDestinatarioParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatarioParent)), ''), @idSediciZeri);
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), @idSediciZeri);
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), @idSediciZeri);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL OR LEN(@Nome) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome dell''importo (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END
		IF @IdPriorita IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = @IdPriorita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la priorità';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idSedePartenzaAttuale CHAR(16);
		DECLARE @idDestinatarioParentAttuale CHAR(16);
		DECLARE @idDestinatarioAttuale CHAR(16);
		DECLARE @idEtichettaAttuale CHAR(16);
		SELECT
			@idAzienda = i.IdSede,
			@idSedePartenzaAttuale = r.IdSedePartenza,
			@idDestinatarioParentAttuale = r.IdDestinatarioParent,
			@idDestinatarioAttuale = r.IdDestinatario,
			@idEtichettaAttuale = r.IdEtichetta
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
		WHERE
			i.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Nome unico tra gli importi di magazzino attivi dell'azienda
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
			WHERE
				i.Id <> @Id
				AND i.IdSede = @idAzienda
				AND i.Lock = 0
				AND i.Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un importo di magazzino con questo nome';
			GOTO BRANCH_END;
		END

		-- Sede di partenza: una sede interna dell'azienda; quella già sull'importo resta valida
		IF @IdSedePartenza IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSedePartenza
				AND s.InternaEsterna = 'I'
				AND s.IdAziendaInterna = @idAzienda
				AND (s.Lock = 0 OR s.Id = @idSedePartenzaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede di partenza indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Sede del destinatario: è il soggetto stesso o una sua sede; indicata la sola sede, il soggetto si ricava
		IF @IdDestinatario IS NOT NULL
		BEGIN
			DECLARE @idParentDellaSede CHAR(16);
			SELECT @idParentDellaSede = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdDestinatario;

			IF @IdDestinatarioParent IS NULL
				SET @IdDestinatarioParent = @idParentDellaSede;
			ELSE IF ISNULL(@idParentDellaSede, '') <> @IdDestinatarioParent
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La sede del destinatario non appartiene al destinatario indicato';
				GOTO BRANCH_END;
			END
		END

		-- Soggetti e sedi: tra quelli che l'utente vede (propri dell'azienda o condivisi nel dominio tramite
		-- un'area), come nelle select; quelli già sull'importo restano validi
		DECLARE @sedi TABLE (
			Ruolo VARCHAR(50) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAttuale CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);
		INSERT @sedi (Ruolo, Id, IdAttuale)
		VALUES
			('Il destinatario indicato', @IdDestinatarioParent, @idDestinatarioParentAttuale),
			('La sede del destinatario indicata', @IdDestinatario, @idDestinatarioAttuale);

		DECLARE @ruoloNonValido VARCHAR(50);
		SELECT TOP (1) @ruoloNonValido = t.Ruolo
		FROM @sedi t
		WHERE
			t.Id IS NOT NULL
			AND (t.IdAttuale IS NULL OR t.Id <> t.IdAttuale)
			AND NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblSessioni e
					CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
				WHERE
					e.Id = @IdSessione
					AND u.Id = t.Id
					AND
						(
							(
							u.IdDominio = e.IdDominio
							AND u.Condivisa = 1
							)
						OR u.IdAziendaInterna = @idAzienda
						)
			);

		IF @ruoloNonValido IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = @ruoloNonValido + ' non esiste o non è accessibile';
			GOTO BRANCH_END;
		END

		-- Etichetta: del modulo Magazzino, di una sede dell'azienda; quella già sull'importo resta valida
		IF @IdEtichetta IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.Id = @IdEtichetta
				AND t.IdModulo = 'MAG'
				AND s.IdAziendaInterna = @idAzienda
				AND (t.Lock = 0 OR t.Id = @idEtichettaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''etichetta indicata non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblImporti
			SET
				Lock = 0,
				Nome = @Nome,
				IdPriorita = @IdPriorita
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Importo non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblImportiMagazzino
			SET
				IdSedePartenza = @IdSedePartenza,
				IdDestinatarioParent = @IdDestinatarioParent,
				IdDestinatario = @IdDestinatario,
				IdEtichetta = @IdEtichetta
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi magazzino: elenco degli importi dell'azienda interna corrente della sessione.
-- Righe, scope e ricerca sono in ufnImportiMagazzino_get_List, comune all'esportazione.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloContrattoScaduto BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			t.Id,
			t.StatoValore,
			t.StatoDescrizione,
			t.Nome,
			t.Priorita,
			t.Partenza,
			t.Destinatario,
			t.Etichetta,
			t.Cliente,
			t.ContrattoTipo,
			t.ContrattoDataFine,
			t.Righe,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnImportiMagazzino_get_List(@IdSessione, @Search, @SoloContrattoScaduto) t
		ORDER BY t.Nome, t.Id
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Esportazione.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi magazzino: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: scope e criteri di ricerca sono in ufnImportiMagazzino_get_List,
-- comune a uspImportiMagazzino_get_List. Tutte le righe, senza paginazione: al massimo @MaxRighe + 1 (la riga in
-- più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloContrattoScaduto BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Nome] = t.Nome,
			[Priorità] = t.Priorita,
			[Sede di partenza] = t.Partenza,
			[Destinatario] = t.Destinatario,
			[Etichetta] = t.Etichetta,
			[Cliente] = t.Cliente,
			[Contratto o offerta] = CASE t.ContrattoTipo WHEN 'C' THEN 'Contratto' WHEN 'O' THEN 'Offerta' END,
			[Valido dal] = t.ContrattoDataInizio,
			[Valido al] = t.ContrattoDataFine,
			[Righe] = t.Righe
		FROM dbo.ufnImportiMagazzino_get_List(@IdSessione, @Search, @SoloContrattoScaduto) t
		ORDER BY t.Nome, t.Id
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Sedi_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei soggetti e delle sedi per le variabili di un importo di magazzino. La prima voce (Id a zeri) significa
-- "qualsiasi": la variabile non viene confrontata con il DDT.
--   @Livello = 'A': solo i soggetti (aziende, sedi radice): destinatario
--   @Livello = 'S': il soggetto @IdParent e le sue sedi: sede del destinatario (senza @IdParent solo la prima voce)
--   @Livello = 'T': soggetti e sedi (non usato dagli importi di magazzino)
-- Visibilità come uspSedi_get_Sedi_SelectList: anagrafiche dell'azienda interna corrente della sessione o
-- condivise nel dominio tramite un'area. La voce selezionata è sempre presente, anche se disabilitata, fuori
-- dalla ricerca o oltre le prime 50.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Sedi_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Livello CHAR(1) = 'T',
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Livello = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@Livello))), ''), 'T');
		SET @IdParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdParent)), ''), @idSediciZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Livello NOT IN ('A', 'S', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Livello deve essere A, S o T';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST(IIF(@Livello = 'S', '(Tutte)', '(Tutti)') AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + IIF(@Livello = 'A', '', ISNULL(' ' + s.IndirizzoCompleto, '')) AS VARCHAR(400)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSelected
				AND s.Id <> @idSediciZeri
			UNION ALL
			SELECT
				t.Id,
				t.[Text],
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				(
					SELECT TOP (50)
						s.Id,
						[Text] = CAST(s.NomeCompleto + IIF(@Livello = 'A', '', ISNULL(' ' + s.IndirizzoCompleto, '')) AS VARCHAR(400))
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
						INNER JOIN dbo.tblSedi s ON u.Id = s.Id
					WHERE
						e.Id = @IdSessione
						AND
							(
								(
								u.IdDominio = e.IdDominio
								AND u.Condivisa = 1
								)
							OR u.IdAziendaInterna = e.IdAzienda
							)
						AND u.Disabilitata = 0
						AND s.Id <> @IdSelected
						AND
							(
							@Livello = 'T'
							OR (@Livello = 'A' AND u.IdParent IS NULL)
							OR (@Livello = 'S' AND (u.Id = @IdParent OR u.IdParent = @IdParent))
							)
						AND
							(
							@Search IS NULL
							OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
							)
					ORDER BY s.NomeCompleto, s.IndirizzoCompleto
				) t
		)
		SELECT
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text]
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_SediInterne_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select delle sedi interne per la variabile "Sede di partenza" di un importo di magazzino: l'azienda interna
-- corrente della sessione e le sue sedi interne, cioè quelle da cui può partire la merce di un DDT. La prima
-- voce (Id a zeri) significa "qualsiasi". La sede selezionata è sempre presente, anche se cancellata.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_SediInterne_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Tutte)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(400)),
				Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblSedi s
			WHERE
				s.InternaEsterna = 'I'
				AND s.IdAziendaInterna = @idAzienda
				AND (s.Lock = 0 OR s.Id = @IdSelected)
		) x
		ORDER BY Pos, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Etichette_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select delle etichette per un importo di magazzino: etichette del modulo Magazzino delle sedi dell'azienda interna
-- corrente della sessione. Le etichette appartengono alla sede: quando la sede non è l'azienda stessa il suo
-- nome segue quello dell'etichetta. La prima voce (Id a zeri) significa "qualsiasi". L'etichetta selezionata è
-- sempre presente, anche se cancellata.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Etichette_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Tutte)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				t.Id,
				[Text] = CAST(t.Nome + IIF(t.IdSede = @idAzienda, '', ISNULL(' - ' + s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''), '')) AS VARCHAR(400)),
				Selected = CAST(IIF(t.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.IdModulo = 'MAG'
				AND s.IdAziendaInterna = @idAzienda
				AND (t.Lock = 0 OR t.Id = @IdSelected)
		) x
		ORDER BY Pos, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Articoli_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select degli articoli per la riga a quantità di un importo di magazzino: articoli attivi dell'azienda
-- interna corrente della sessione, al massimo 50, con la ricerca su nome e codice. La prima voce (Id a zeri)
-- è "(Selezionare)". L'articolo selezionato è sempre presente, anche se cancellato, fuori dalla ricerca o
-- oltre i primi 50.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Articoli_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				a.Id,
				[Text] = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(400)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblMagazziniArticoli a
			WHERE
				a.Id = @IdSelected
				AND a.Id <> @idSediciZeri
			UNION ALL
			SELECT
				t.Id,
				t.[Text],
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				(
					SELECT TOP (50)
						a.Id,
						[Text] = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(400))
					FROM
						dbo.tblMagazziniArticoli a
						INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdAzienda
					WHERE
						e.Id = @IdSessione
						AND a.Lock = 0
						AND a.Id <> @IdSelected
						AND
							(
							@Search IS NULL
							OR a.Nome LIKE '%' + @Search + '%'
							OR a.Codice LIKE '%' + @Search + '%'
							)
					ORDER BY a.Nome, a.Id
				) t
		) x
		ORDER BY Pos, [Text]
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Materiali_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei materiali EoW per la riga a quantità di un importo di magazzino (righe EoW del DDT). La
-- prima voce (Id a zeri) è "(Selezionare)". I materiali sono un'anagrafica di sistema, uguale per tutti.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Materiali_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idDueZeri CHAR(2) = REPLICATE('0', 2);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idDueZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idDueZeri AS CHAR(2)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idDueZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				m.Id,
				[Text] = CAST(m.Nome AS VARCHAR(400)),
				Selected = CAST(IIF(m.Id = @IdSelected, 1, 0) AS BIT),
				Pos = IIF(m.Nome = 'Altro', 2, 1)
			FROM dbo.tblRifiutiMateriali m
		) x
		ORDER BY Pos, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Verifica.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi magazzino > Azioni > Verifica importi: quali importi dell'azienda interna
-- corrente coinciderebbero con un DDT che avesse i valori indicati, e quale verrebbe applicato. La regola di
-- coincidenza e la classe dell'importo sono quelle della fatturazione (ufnImportiMagazzino_get_Coincidenti);
-- qui si restituiscono tutti gli importi che coincidono, non solo il primo.
--   @Data: data del DDT (decide la validità dei contratti); se manca, oggi.
--   @IdSedePartenza: sede interna da cui parte la merce. Destinatario: @IdDestinatarioParent è il soggetto,
--   @IdDestinatario dove arriva la merce; indicato solo il soggetto, la sede è il soggetto stesso; indicata
--   solo la sede, il soggetto si ricava. @IdEtichetta: un'etichetta del DDT (una sola). Un valore non
--   indicato vuol dire che il DDT non ha quel dato: non coincide con gli importi che lo indicano.
--   @IdArticolo oppure @IdMateriale (facoltativi): un articolo o un materiale del DDT. Non entrano nella
--   scelta dell'importo: servono a dire se l'importo ha una riga con il suo prezzo (Prezzo), e se manca
--   (SenzaRigaArticolo = 1: un DDT con quell'articolo non sarebbe fatturabile con quell'importo).
-- Righe nell'ordine di scelta. Esito: A applicato; B coincide ma non viene applicato (Motivo); S di un contratto
-- non valido alla data; X di un'offerta o di un contratto cancellato (mai applicato).
-- Conflitto = 1: stessa priorità e stesso tipo (di contratto o standard) dell'importo applicato, lui compreso:
-- tra questi la fatturazione sceglie senza un criterio.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Verifica
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@IdSedePartenza CHAR(16) = NULL,
	@IdDestinatarioParent CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSedePartenza = NULLIF(NULLIF(LTRIM(RTRIM(@IdSedePartenza)), ''), REPLICATE('0', 16));
		SET @IdDestinatarioParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatarioParent)), ''), REPLICATE('0', 16));
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), REPLICATE('0', 16));
		SET @IdArticolo = NULLIF(NULLIF(LTRIM(RTRIM(@IdArticolo)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), REPLICATE('0', 16));
		SET @Data = ISNULL(@Data, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli importi sono quelli dell'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Destinatario: soggetto e sede, come sul DDT
		IF @IdDestinatario IS NULL
			SET @IdDestinatario = @IdDestinatarioParent;
		ELSE IF @IdDestinatarioParent IS NULL
			SELECT @IdDestinatarioParent = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdDestinatario;

		WITH c AS (
			SELECT
				k.IdImporto,
				k.IdPriorita,
				k.IdOffertaContratto,
				k.Standard,
				k.Classe
			FROM dbo.ufnImportiMagazzino_get_Coincidenti(@idAzienda, @Data, @IdSedePartenza, @IdDestinatarioParent, @IdDestinatario) k
			-- L'importo che indica un'etichetta coincide solo se è quella del DDT
			WHERE
				k.IdEtichetta IS NULL
				OR k.IdEtichetta = @IdEtichetta
		),
		o AS (
			SELECT
				c.IdImporto,
				c.IdPriorita,
				c.IdOffertaContratto,
				c.Standard,
				c.Classe,
				N = ROW_NUMBER() OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto),
				-- Priorità e tipo del primo della classe: per i candidati, quelli dell'importo applicato
				PrimoPriorita = FIRST_VALUE(c.IdPriorita) OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto),
				PrimoStandard = FIRST_VALUE(c.Standard) OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto)
			FROM c
		),
		t AS (
			SELECT
				o.IdImporto,
				o.IdPriorita,
				o.IdOffertaContratto,
				o.Standard,
				o.Classe,
				o.N,
				Pari = CAST(IIF(o.Classe = 'V' AND ISNULL(o.IdPriorita, -1) = ISNULL(o.PrimoPriorita, -1) AND o.Standard = o.PrimoStandard, 1, 0) AS BIT),
				PrioritaPiuBassa = CAST(IIF(ISNULL(o.IdPriorita, -1) < ISNULL(o.PrimoPriorita, -1), 1, 0) AS BIT)
			FROM o
		)
		SELECT
			Id = t.IdImporto,
			i.Nome,
			Priorita = p.Nome,
			t.Standard,
			Cliente = cs.NomeCompleto,
			ContrattoTipo = oc.Tipo,
			ContrattoDataInizio = oc.DataInizio,
			ContrattoDataFine = oc.DataFine,
			Righe = (SELECT COUNT(*) FROM dbo.tblImportiRighe g WHERE g.IdImporto = t.IdImporto),
			Prezzo = pr.Importo,
			SenzaRigaArticolo = CAST(IIF((@IdArticolo IS NOT NULL OR @IdMateriale IS NOT NULL) AND pr.Id IS NULL, 1, 0) AS BIT),
			Esito = CAST(CASE
				WHEN t.Classe = 'V' AND t.N = 1 THEN 'A'
				WHEN t.Classe = 'V' THEN 'B'
				ELSE t.Classe
			END AS CHAR(1)),
			Conflitto = CAST(IIF(t.Pari = 1 AND SUM(CAST(t.Pari AS INT)) OVER () > 1, 1, 0) AS BIT),
			Motivo = CAST(CASE
				WHEN t.Classe = 'V' AND t.N = 1 THEN 'Importo applicato'
				WHEN t.Classe = 'V' AND t.PrioritaPiuBassa = 1 THEN 'Priorità più bassa dell''importo applicato'
				WHEN t.Classe = 'V' AND t.Pari = 1 THEN 'Stessa priorità e stesso tipo dell''importo applicato'
				WHEN t.Classe = 'V' THEN 'A parità di priorità prevale l''importo di un contratto'
				WHEN t.Classe = 'S' THEN 'Contratto non valido alla data: dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103) + ' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103)
				WHEN oc.Tipo = 'O' THEN 'Importo di un''offerta: non viene applicato'
				ELSE 'Contratto cancellato o senza validità: non viene applicato'
			END AS VARCHAR(100))
		FROM
			t
			INNER JOIN dbo.tblImporti i ON t.IdImporto = i.Id
			LEFT JOIN dbo.tblImportiPriorita p ON t.IdPriorita = p.Id
			LEFT JOIN dbo.tblOfferteContratti oc ON t.IdOffertaContratto = oc.Id
			LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
			LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
			OUTER APPLY (
				-- Riga a quantità dell'importo per l'articolo o il materiale indicato
				SELECT TOP (1) x.Id, x.Importo
				FROM
					dbo.tblImportiRighe x
					INNER JOIN dbo.tblImportiRigheMagazzino xm ON x.Id = xm.Id
				WHERE
					x.IdImporto = t.IdImporto
					AND x.IdTipo = 'MA'
					AND x.Importo IS NOT NULL
					AND ISNULL(x.MinimoFatturabile, 0) = 0
					AND (xm.IdArticolo = @IdArticolo OR xm.IdMateriale = @IdMateriale)
				ORDER BY ISNULL(x.Pos, 0), x.Id
			) pr
		ORDER BY
			CASE t.Classe WHEN 'V' THEN 0 WHEN 'S' THEN 1 ELSE 2 END,
			t.N
		OPTION (RECOMPILE);
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiMagazzino_get_Conflitti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi magazzino: importi attivi della stessa azienda in conflitto con l'importo @Id.
-- La scheda li mostra dopo il salvataggio; l'importo resta salvato, è un avviso.
-- Due importi sono in conflitto se possono coincidere con lo stesso DDT e la fatturazione non ha un
-- criterio per scegliere tra i due (li ordina per Id):
--   - variabili sovrapposte: per ogni variabile, uno dei due non la indica oppure indicano lo stesso valore.
--     L'etichetta non si confronta: un DDT può averne più di una;
--   - stessa priorità;
--   - stesso tipo: entrambi standard, oppure entrambi di un contratto attivo di un cliente, con periodi di
--     validità che si sovrappongono (anche di clienti diversi).
-- Un importo di un'offerta o di un contratto cancellato non viene mai applicato: nessun conflitto.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Conflitti
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			b.Id,
			b.Nome,
			Priorita = p.Nome,
			Standard = CAST(IIF(bc.IdImporto IS NULL, 1, 0) AS BIT),
			Cliente = cs.NomeCompleto,
			ContrattoTipo = bo.Tipo,
			ContrattoDataInizio = bo.DataInizio,
			ContrattoDataFine = bo.DataFine
		FROM
			dbo.tblImporti a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdAzienda
			INNER JOIN dbo.tblImportiMagazzino ar ON a.Id = ar.Id
			LEFT JOIN dbo.tblOfferteContrattiImporti ac ON a.Id = ac.IdImporto
			LEFT JOIN dbo.tblOfferteContratti ao ON ac.IdOffertaContratto = ao.Id
			-- Gli altri importi di magazzino dell'azienda
			INNER JOIN dbo.tblImportiMagazzino br ON ar.IdSede = br.IdSede
												AND ar.Id <> br.Id
			INNER JOIN dbo.tblImporti b ON br.Id = b.Id
			LEFT JOIN dbo.tblOfferteContrattiImporti bc ON b.Id = bc.IdImporto
			LEFT JOIN dbo.tblOfferteContratti bo ON bc.IdOffertaContratto = bo.Id
			LEFT JOIN dbo.tblImportiPriorita p ON b.IdPriorita = p.Id
			LEFT JOIN dbo.tblClientiFornitori cf ON bo.IdClienteFornitore = cf.Id
			LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione
			AND a.Lock <= 2
			AND b.Lock = 0
			AND ISNULL(a.IdPriorita, -1) = ISNULL(b.IdPriorita, -1)
			-- Gli articoli e i materiali delle righe non contano: l'importo si sceglie sul DDT prima di guardarli, quindi
			-- due listini dello stesso destinatario con la stessa priorità sono in conflitto anche con articoli diversi
			AND (ar.IdSedePartenza IS NULL OR br.IdSedePartenza IS NULL OR ar.IdSedePartenza = br.IdSedePartenza)
			AND (ar.IdDestinatarioParent IS NULL OR br.IdDestinatarioParent IS NULL OR ar.IdDestinatarioParent = br.IdDestinatarioParent)
			AND (ar.IdDestinatario IS NULL OR br.IdDestinatario IS NULL OR ar.IdDestinatario = br.IdDestinatario)
			AND
				(
					(ac.IdImporto IS NULL AND bc.IdImporto IS NULL)
					OR
					(
						ao.Lock = 0 AND ao.Tipo = 'C' AND ao.ClienteFornitoreTipo = 'C'
						AND bo.Lock = 0 AND bo.Tipo = 'C' AND bo.ClienteFornitoreTipo = 'C'
						AND ao.DataInizio <= bo.DataFine
						AND bo.DataInizio <= ao.DataFine
					)
				)
		ORDER BY b.Nome, b.Id
		OPTION (RECOMPILE);
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiRighe_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Aggiunge una riga a un importo (@Id NULL, in coda) o la modifica. Vale per gli importi di rifiuti, magazzino
-- e servizi: il tipo di riga deve essere del modulo dell'importo.
-- Riga con importo: il tipo dice per che cosa si moltiplica (una volta per documento, oppure per la quantità).
-- Riga di sola descrizione (@Importo NULL): in fattura dà una riga di testo, una per documento; aliquota IVA e
-- conto non contano.
-- Minimo fatturabile: l'importo della riga è il minimo da fatturare per documento; al massimo una per importo.
-- Aliquota IVA facoltativa: se manca, la fatturazione usa quella della scheda del cliente.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_upd
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(2) = NULL,
	@Importo DECIMAL(18, 4) = NULL,
	@MinimoFatturabile BIT = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdConto CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	-- Solo per gli importi di magazzino: articolo oppure materiale EoW della riga a quantità (tipo MA)
	@IdArticolo CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(UPPER(LTRIM(RTRIM(@IdTipo))), '');
		SET @MinimoFatturabile = ISNULL(@MinimoFatturabile, 0);
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');
		SET @IdArticolo = NULLIF(NULLIF(LTRIM(RTRIM(@IdArticolo)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Riga esistente: l'importo è quello della riga
		DECLARE @idAliquotaIvaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			SET @IdImporto = NULL;
			SELECT
				@IdImporto = g.IdImporto,
				@idAliquotaIvaAttuale = d.IdAliquotaIva,
				@idContoAttuale = d.IdConto
			FROM
				dbo.tblImportiRighe g
				LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
			WHERE g.Id = @Id;
		END

		-- L'importo deve esistere (in bozza o attivo), appartenere all'azienda interna corrente della sessione
		-- e il suo modulo deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @IdImporto
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		IF @Descrizione IS NULL OR LEN(@Descrizione) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il testo della riga in fattura (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END

		DECLARE @conImporto BIT = IIF(@Importo IS NULL, 0, 1);
		IF @conImporto = 1
		BEGIN
			IF @IdTipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblImportiRigheTipi WHERE Id = @IdTipo AND IdModulo = @idModulo)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare a che cosa si applica l''importo della riga';
				GOTO BRANCH_END;
			END
			IF @Importo < 0.0001 OR @Importo > 999999.9999
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo deve essere compreso tra 0,0001 e 999.999,9999';
				GOTO BRANCH_END;
			END
			-- Aliquota IVA: facoltativa, di sistema (IdSede NULL) o dell'azienda; quella già sulla riga resta valida
			IF @IdAliquotaIva IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblAliquoteIva
				WHERE
					Id = @IdAliquotaIva
					AND (IdSede IS NULL OR IdSede = @idAzienda)
					AND (Lock = 0 OR Id = @idAliquotaIvaAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''aliquota IVA indicata non esiste';
				GOTO BRANCH_END;
			END
			-- Conto: facoltativo, dell'azienda; quello già sulla riga resta valido
			IF @IdConto IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblFattureConti
				WHERE
					Id = @IdConto
					AND IdSede = @idAzienda
					AND (Lock = 0 OR Id = @idContoAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il conto indicato non esiste';
				GOTO BRANCH_END;
			END
			-- Importi di magazzino: l'importo è un listino. La riga a quantità (MA) senza minimo indica l'articolo
			-- oppure il materiale EoW a cui si applica il prezzo, obbligatorio (una riga generica nasconderebbe gli
			-- articoli nuovi non ancora prezzati) e una sola volta per importo; le altre righe non lo indicano
			IF @idModulo = 'MAG' AND @IdTipo = 'MA' AND @MinimoFatturabile = 0
			BEGIN
				IF (@IdArticolo IS NULL AND @IdMateriale IS NULL) OR (@IdArticolo IS NOT NULL AND @IdMateriale IS NOT NULL)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Indicare l''articolo oppure il materiale EoW a cui si applica l''importo della riga';
					GOTO BRANCH_END;
				END
				IF @IdArticolo IS NOT NULL AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblMagazziniArticoli a
					WHERE
						a.Id = @IdArticolo
						AND a.IdSede = @idAzienda
						AND (a.Lock = 0 OR EXISTS (SELECT 1 FROM dbo.tblImportiRigheMagazzino x WHERE x.Id = @Id AND x.IdArticolo = a.Id))
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'L''articolo indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @IdMateriale IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Il materiale indicato non esiste';
					GOTO BRANCH_END;
				END
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblImportiRighe g
						INNER JOIN dbo.tblImportiRigheMagazzino x ON g.Id = x.Id
					WHERE
						g.IdImporto = @IdImporto
						AND (@Id IS NULL OR g.Id <> @Id)
						AND (x.IdArticolo = @IdArticolo OR x.IdMateriale = @IdMateriale)
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'L''importo ha già una riga per questo ' + IIF(@IdArticolo IS NOT NULL, 'articolo', 'materiale');
					GOTO BRANCH_END;
				END
			END
			ELSE
			BEGIN
				SET @IdArticolo = NULL;
				SET @IdMateriale = NULL;
			END

			-- Al massimo una riga con il minimo fatturabile per importo
			IF @MinimoFatturabile = 1 AND EXISTS (
				SELECT 1
				FROM dbo.tblImportiRighe
				WHERE
					IdImporto = @IdImporto
					AND MinimoFatturabile = 1
					AND (@Id IS NULL OR Id <> @Id)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo ha già una riga con il minimo fatturabile';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Sola descrizione: una riga di testo per documento (il tipo "per documento" è il primo del modulo)
			SELECT TOP (1) @IdTipo = Id
			FROM dbo.tblImportiRigheTipi
			WHERE IdModulo = @idModulo
			ORDER BY Pos;

			SET @MinimoFatturabile = 0;
			SET @IdAliquotaIva = NULL;
			SET @IdConto = NULL;
			SET @IdArticolo = NULL;
			SET @IdMateriale = NULL;
		END

		-- Nuova riga: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
			BEGIN
				-- In coda alle righe dell'importo
				DECLARE @pos INT;
				SELECT @pos = ISNULL(MAX(Pos), 0) + 1
				FROM dbo.tblImportiRighe WITH (UPDLOCK, HOLDLOCK)
				WHERE IdImporto = @IdImporto;

				INSERT dbo.tblImportiRighe (Id, IdImporto, IdTipo, Importo, MinimoFatturabile, Lock, Pos)
				VALUES (@Id, @IdImporto, @IdTipo, @Importo, @MinimoFatturabile, 0, @pos);
			END
			ELSE
			BEGIN
				UPDATE dbo.tblImportiRighe
				SET
					IdTipo = @IdTipo,
					Importo = @Importo,
					MinimoFatturabile = @MinimoFatturabile
				WHERE Id = @Id;
			END

			DELETE dbo.tblImportiRigheDettagli
			WHERE Id = @Id;

			INSERT dbo.tblImportiRigheDettagli (Id, IdAliquotaIva, IdConto, Descrizione)
			VALUES (@Id, @IdAliquotaIva, @IdConto, @Descrizione);

			-- Articolo o materiale della riga a quantità di un importo di magazzino
			DELETE dbo.tblImportiRigheMagazzino
			WHERE Id = @Id;

			IF @IdArticolo IS NOT NULL OR @IdMateriale IS NOT NULL
				INSERT dbo.tblImportiRigheMagazzino (Id, IdArticolo, IdMateriale)
				VALUES (@Id, @IdArticolo, @IdMateriale);
		COMMIT TRANSACTION;

		SELECT Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspImportiRighe_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Righe di un importo (rifiuti, magazzino o servizi) dell'azienda interna corrente della sessione, nell'ordine
-- in cui finiranno in fattura. Una riga senza importo è di sola descrizione.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_get_List
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo deve appartenere all'azienda interna corrente della sessione e il suo modulo (quello dei
		-- documenti a cui si applica) deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @IdImporto
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.IdImporto,
			g.IdTipo,
			Tipo = t.Nome,
			g.Importo,
			MinimoFatturabile = ISNULL(g.MinimoFatturabile, 0),
			d.IdAliquotaIva,
			AliquotaIvaNome = a.Nome,
			d.IdConto,
			ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome,
			d.Descrizione,
			g.Pos,
			-- Solo per gli importi di magazzino: articolo o materiale EoW della riga a quantità
			x.IdArticolo,
			x.IdMateriale,
			Voce = ISNULL(ar.Nome + ISNULL(' (' + ar.Codice + ')', ''), 'EoW: ' + ma.Nome)
		FROM
			dbo.tblImportiRighe g
			LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
			LEFT JOIN dbo.tblImportiRigheMagazzino x ON g.Id = x.Id
			LEFT JOIN dbo.tblMagazziniArticoli ar ON x.IdArticolo = ar.Id
			LEFT JOIN dbo.tblRifiutiMateriali ma ON x.IdMateriale = ma.Id
			LEFT JOIN dbo.tblImportiRigheTipi t ON g.IdTipo = t.Id
			LEFT JOIN dbo.tblAliquoteIva a ON d.IdAliquotaIva = a.Id
			LEFT JOIN dbo.tblFattureConti c ON d.IdConto = c.Id
		WHERE g.IdImporto = @IdImporto
		ORDER BY ISNULL(g.Pos, 0), g.Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspMagazziniArticoli_del.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniArticoli c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblMagazziniArticoli WHERE Id = @Id);

		-- ── CASO 1: articolo attivo (Lock = 0) → soft delete ─────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE IdArticolo = @Id AND Lock <= 2)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un articolo con lotti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdArticolo = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un articolo con movimenti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			-- Modulo Offerte e contratti: un articolo indicato in una riga di un importo attivo
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblImportiRigheMagazzino m
					INNER JOIN dbo.tblImportiRighe g ON m.Id = g.Id
					INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
				WHERE
					m.IdArticolo = @Id
					AND i.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un articolo indicato in un importo non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblMagazziniArticoli
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Articolo non trovato o già eliminato';
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: articolo in bozza (Lock = 2) → hard delete ───────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblMagazziniArticoli
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'sql/procedures/uspFatture_get_Genera_Fatture_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: anteprima delle fatture che la
-- generazione creerebbe con gli stessi criteri ("Visualizza" sulla riga delle fatture previste della finestra
-- "Verifica"). Una riga per fattura: cliente, raggruppamento (la sede del produttore o il contratto, quando la
-- scheda del cliente chiede una fattura per sede o per contratto), documenti, pre-fatture convertite, imponibile.
-- La sede è quella del produttore per le registrazioni dei rifiuti, il destinatario per i DDT di magazzino.
-- Stessi documenti e stessi gruppi di uspFatture_ins_Genera (ufnFattureGenera_get_Documenti).
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_Fatture_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@IncludiPreFatture BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 1000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I DDT entrano solo con il modulo Magazzino attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
			SET @Magazzino = 0;

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			Id = t.IdClienteFornitore,
			Cliente = sc.NomeCompleto,
			Raggruppamento = CAST(CASE
				WHEN t.GruppoSede IS NOT NULL THEN 'Sede: ' + sp.NomeCompleto
				WHEN t.GruppoContratto IS NOT NULL THEN 'Contratto'
					+ ISNULL(' ' + NULLIF(oc.Protocollo, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
					+ ISNULL(' - ' + NULLIF(oc.Descrizione, ''), '')
			END AS VARCHAR(300)),
			t.Documenti,
			t.PreFatture,
			t.Imponibile,
			RowsCount = COUNT(*) OVER ()
		FROM
			(
				SELECT
					d.IdClienteFornitore,
					d.GruppoSede,
					d.GruppoContratto,
					Documenti = COUNT(*),
					PreFatture = COUNT(DISTINCT d.IdPreFattura),
					Imponibile = SUM(ISNULL(d.Imponibile, 0))
				FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino) d
				WHERE
					d.Fatturabile = 1
				GROUP BY d.IdClienteFornitore, d.GruppoSede, d.GruppoContratto
			) t
			LEFT JOIN dbo.tblClientiFornitori c ON t.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			LEFT JOIN dbo.tblSedi sp ON t.GruppoSede = sp.Id
			LEFT JOIN dbo.tblOfferteContratti oc ON t.GruppoContratto = oc.Id
		ORDER BY sc.NomeCompleto, t.IdClienteFornitore, t.GruppoSede, t.GruppoContratto
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFatture_get_Genera_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: elenco di dettaglio della verifica
-- ("Visualizza" sulle righe della finestra "Verifica"; i conteggi sono in uspFatture_get_Genera_Riepilogo).
-- Elenca i documenti (registrazioni dei rifiuti e DDT di magazzino) dell'azienda interna corrente della sessione con data
-- nell'intervallo, con il cliente, l'importo e l'imponibile che la generazione userebbe e l'esito:
-- Fatturabile = 1 entra in una fattura, altrimenti Avviso dice perché resta fuori. Stesse righe di
-- uspFatture_ins_Genera (ufnFattureGenera_get_Documenti).
--   @Rifiuti, @Magazzino: da quali documenti generare (registrazioni dei rifiuti, DDT di magazzino). I DDT
--        entrano solo con il modulo Magazzino attivo sul dominio; per un DDT Id è l'Id del movimento.
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente.
--   @IncludiPreFatture = 1: anche i documenti già in una pre-fattura, che verrà convertita in fattura con le
--        sue righe; l'imponibile della pre-fattura è riportato sul suo primo documento.
--   @Esito: solo i documenti con quell'esito (codici di ufnFattureGenera_get_Documenti.Esito); F = tutti quelli
--        che entrano in una fattura (F, S e P). NULL: tutti.
-- I documenti già in una fattura non compaiono; quelli annullati sì, con il loro avviso.
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Esito CHAR(1) = NULL,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@IncludiPreFatture BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Esito = NULLIF(UPPER(LTRIM(RTRIM(@Esito))), '');
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 1000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I DDT entrano solo con il modulo Magazzino attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
			SET @Magazzino = 0;

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			d.Id,
			d.IdModulo,
			Documento = CAST(IIF(d.IdModulo = 'MAG',
				'DDT' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)) + ISNULL('/' + dd.Sezionale, ''), '') + ISNULL(' - ' + sd.NomeCompleto, ''),
				'Registrazione' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)), '')
					+ ISNULL(' - EER ' + e.Nome + IIF(e.Pericoloso = 1, '*', ''), '')) AS VARCHAR(200)),
			d.[Data],
			d.Quantita,
			UnitaMisura = d.IdUnitaMisura,
			Cliente = sc.NomeCompleto,
			Importo = CAST(IIF(d.IdPreFattura IS NULL, i.Nome, 'Righe della pre-fattura') AS VARCHAR(50)),
			Contratto = CAST(IIF(d.IdPreFattura IS NULL AND d.IdOffertaContratto IS NOT NULL, 1, 0) AS BIT),
			PreFattura = CAST(IIF(d.IdPreFattura IS NULL, 0, 1) AS BIT),
			-- Pre-fattura: il suo imponibile una volta sola, sul primo dei suoi documenti
			Totale = d.Imponibile,
			d.Fatturabile,
			d.Esito,
			Avviso = CAST(CASE d.Esito
				WHEN 'P' THEN 'In pre-fattura del ' + ISNULL(CONVERT(VARCHAR(10), f.DataEmissione, 103), '') + ': viene convertita in fattura con le sue righe'
				WHEN 'S' THEN 'Contratto non valido alla data: applicato l''importo standard'
				WHEN 'A' THEN 'Registrazione annullata'
				WHEN 'N' THEN IIF(d.IdModulo = 'MAG', 'Indicato', 'Indicata') + ' come non fatturabile'
				WHEN 'I' THEN IIF(d.IdModulo = 'MAG' AND d.IdImporto IS NOT NULL,
					'L''importo "' + ISNULL(i.Nome, '') + '" non ha una riga per tutti gli articoli o i materiali del DDT',
					IIF(d.IdModulo = 'MAG', 'Nessun importo coincide, o il DDT non ha righe di articoli o materiali', 'Nessun importo coincide'))
				WHEN 'C' THEN 'Cliente non determinato: ' + IIF(d.IdModulo = 'MAG', 'il destinatario', 'il produttore') + ' non ha una scheda cliente'
				WHEN 'R' THEN 'L''importo non ha righe applicabili'
				WHEN 'V' THEN 'Aliquota IVA non indicata né sull''importo né sulla scheda del cliente'
			END AS VARCHAR(300)),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino) d
			LEFT JOIN dbo.tblRifiutiEer e ON d.IdEer = e.Id
			-- DDT: sezionale e destinatario (per un DDT d.Id è il movimento e d.IdProduttore il destinatario)
			LEFT JOIN dbo.tblMagazziniDdt dd ON d.IdModulo = 'MAG'
										  AND d.Id = dd.IdMovimento
			LEFT JOIN dbo.tblSedi sd ON d.IdModulo = 'MAG'
									 AND d.IdProduttore = sd.Id
			LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			LEFT JOIN dbo.tblImporti i ON d.IdImporto = i.Id
			LEFT JOIN dbo.tblFatture f ON d.IdPreFattura = f.Id
		WHERE
				(
				@Esito IS NULL
				OR (@Esito = 'F' AND d.Fatturabile = 1)
				OR (@Esito <> 'F' AND d.Esito = @Esito)
				)
		ORDER BY d.Fatturabile DESC, sc.NomeCompleto, d.[Data], d.Numero, d.Id
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFatture_get_Genera_Riepilogo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: riepilogo della verifica, mostrato nella
-- finestra "Verifica" prima di generare. Una riga con i conteggi di ciò che la generazione farebbe con gli stessi
-- criteri (stessi documenti e stessi gruppi di uspFatture_ins_Genera: ufnFattureGenera_get_Documenti), calcolati
-- su tutti i documenti, senza limite di righe.
--   Documenti: documenti del periodo non ancora fatturati (con @IncludiPreFatture anche quelli in pre-fattura).
--   Fatturabili, Fatture, Clienti, Imponibile: documenti che entrano in una fattura, fatture previste (una per
--        cliente e, secondo la scheda del cliente, per sede o per contratto), clienti e imponibile totale.
--   PreFatture, DocumentiPreFatture: pre-fatture che verrebbero convertite e loro documenti nel periodo.
--   ImportoStandard: fatturabili con l'importo standard perché il contratto non è valido alla data.
--   Annullati, NonFatturabili, SenzaImporto, SenzaCliente, SenzaRighe, SenzaIva: documenti che restano fuori,
--        per motivo (uno solo per documento, nell'ordine di ufnFattureGenera_get_Documenti.Esito).
--   GiaFatturati: documenti del periodo già in una fattura (solo informativo: non rientrano).
--   InPreFattura: documenti del periodo già in una pre-fattura, quando non si includono le pre-fatture.
--   DocumentiRifiuti, DocumentiMagazzino: i Documenti, divisi tra registrazioni dei rifiuti e DDT di magazzino.
-- @Rifiuti, @Magazzino: da quali documenti generare (registrazioni dei rifiuti, DDT di magazzino). I DDT entrano
-- solo con il modulo Magazzino attivo sul dominio.
-- Senza azienda nel contesto tutto a zero.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_Riepilogo
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@IncludiPreFatture BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I DDT entrano solo con il modulo Magazzino attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
			SET @Magazzino = 0;

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Documenti candidati, letti una volta sola
		DECLARE @doc TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdModulo CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdPreFattura CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Imponibile DECIMAL(18, 2) NULL,
			Fatturabile BIT NOT NULL,
			Esito CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		);
		INSERT @doc (Id, IdModulo, IdClienteFornitore, IdPreFattura, GruppoSede, GruppoContratto, Imponibile, Fatturabile, Esito)
		SELECT
			d.Id,
			d.IdModulo,
			d.IdClienteFornitore,
			d.IdPreFattura,
			d.GruppoSede,
			d.GruppoContratto,
			d.Imponibile,
			d.Fatturabile,
			d.Esito
		FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino) d
		OPTION (RECOMPILE);

		-- Documenti del periodo già in una fattura o in una pre-fattura (stessa platea dei candidati:
		-- registrazioni confermate di un'operazione fatturabile, non rettifiche, dei registri che la sessione vede)
		DECLARE @giaFatturati INT = 0;
		DECLARE @inPreFattura INT = 0;
		SELECT
			@giaFatturati = ISNULL(SUM(IIF(f.IdTipo = 'TD00', 0, 1)), 0),
			@inPreFattura = ISNULL(SUM(IIF(f.IdTipo = 'TD00', 1, 0)), 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			INNER JOIN dbo.tblFattureDocumenti fd ON r.Id = fd.Id
			INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
		WHERE
			@Rifiuti = 1
			AND r.Lock = 0
			AND o.IsFatturabile = 1
			AND v.IsRettifica = 0
			AND f.Lock IN (0, 2)
			AND sr.IdAziendaInterna = @idAzienda
			AND r.[Data] >= @DataDa
			AND r.[Data] <= @DataA
			AND (@IdClienteFornitore IS NULL OR f.IdClienteFornitore = @IdClienteFornitore)
		OPTION (RECOMPILE);

		-- Lo stesso per i DDT di magazzino (stessa platea dei candidati: DDT emessi e confermati di un movimento di
		-- scarico con una causale fatturabile, delle sedi che la sessione vede)
		IF @Magazzino = 1
			SELECT
				@giaFatturati += ISNULL(SUM(IIF(f.IdTipo = 'TD00', 0, 1)), 0),
				@inPreFattura += ISNULL(SUM(IIF(f.IdTipo = 'TD00', 1, 0)), 0)
			FROM
				dbo.ufnImportiMagazzino_get_Documenti(NULL, @idAzienda, @DataDa, @DataA) doc
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON doc.IdSedeDdt = x.Id
				INNER JOIN dbo.tblFattureDocumenti fd ON doc.Id = fd.Id
				INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
			WHERE
				doc.Lock = 0
				AND doc.IsFatturabile = 1
				AND f.Lock IN (0, 2)
				AND (@IdClienteFornitore IS NULL OR f.IdClienteFornitore = @IdClienteFornitore)
			OPTION (RECOMPILE);

		SELECT
			Documenti = COUNT(*),
			DocumentiRifiuti = ISNULL(SUM(IIF(d.IdModulo = 'RIF', 1, 0)), 0),
			DocumentiMagazzino = ISNULL(SUM(IIF(d.IdModulo = 'MAG', 1, 0)), 0),
			Fatturabili = ISNULL(SUM(IIF(d.Fatturabile = 1, 1, 0)), 0),
			Fatture = (
				SELECT COUNT(*)
				FROM (SELECT DISTINCT IdClienteFornitore, GruppoSede, GruppoContratto FROM @doc WHERE Fatturabile = 1) q
			),
			Clienti = COUNT(DISTINCT IIF(d.Fatturabile = 1, d.IdClienteFornitore, NULL)),
			Imponibile = ISNULL(SUM(IIF(d.Fatturabile = 1, ISNULL(d.Imponibile, 0), 0)), 0),
			PreFatture = COUNT(DISTINCT d.IdPreFattura),
			DocumentiPreFatture = ISNULL(SUM(IIF(d.Esito = 'P', 1, 0)), 0),
			ImportoStandard = ISNULL(SUM(IIF(d.Esito = 'S', 1, 0)), 0),
			Annullati = ISNULL(SUM(IIF(d.Esito = 'A', 1, 0)), 0),
			NonFatturabili = ISNULL(SUM(IIF(d.Esito = 'N', 1, 0)), 0),
			SenzaImporto = ISNULL(SUM(IIF(d.Esito = 'I', 1, 0)), 0),
			SenzaCliente = ISNULL(SUM(IIF(d.Esito = 'C', 1, 0)), 0),
			SenzaRighe = ISNULL(SUM(IIF(d.Esito = 'R', 1, 0)), 0),
			SenzaIva = ISNULL(SUM(IIF(d.Esito = 'V', 1, 0)), 0),
			GiaFatturati = @giaFatturati,
			-- Con le pre-fatture incluse quei documenti sono già tra i candidati
			InPreFattura = IIF(@IncludiPreFatture = 1, 0, @inPreFattura)
		FROM @doc d;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFatture_ins_Genera.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture clienti dai documenti fatturabili (registrazioni dei rifiuti e DDT di magazzino),
-- con gli importi del modulo Offerte e contratti (regole O5 e O6 di docs/regole/offerte-contratti.md).
--   @Id (con @IdModulo = 'RIF' o 'MAG'): un solo documento, registrazione dei rifiuti o DDT di magazzino
--        ("Genera la fattura" dalla scheda); l'azienda è quella del
--        documento. Se il documento non è fatturabile la SP lo rifiuta.
--   Senza @Id: i documenti dell'azienda interna corrente della sessione con data tra @DataDa e @DataA,
--        eventualmente riconducibili al solo cliente @IdClienteFornitore (Fatture clienti > Nuovo > Tramite
--        procedura automatica). @Rifiuti e @Magazzino dicono da quali documenti generare (registrazioni dei
--        rifiuti, DDT di magazzino).
-- Entrano solo i documenti fatturabili, raggruppati come li mostra la verifica (ufnFattureGenera_get_Documenti).
-- Una fattura per cliente; secondo il raggruppamento della scheda del cliente (tblClientiFornitori.
-- IdRaggruppamento) una per sede del produttore (S) o una per contratto (T): solo in quest'ultimo caso la
-- fattura riporta ordine, data dell'ordine, CIG e CUP del contratto.
-- Fattura: tipo TD01 (TD00, pre-fattura senza numero, con @PreFattura = 1), stato Generata, attiva; data di
-- emissione e di registrazione @DataEmissione (oggi se non indicata); condizioni di pagamento, banca, IBAN,
-- valuta e split payment dalla scheda del cliente; numero successivo dell'anno senza sezionale, assegnato con
-- lo stesso blocco di uspFatture_upd. Righe: quelle dell'importo applicato a ogni documento, nell'ordine dei
-- documenti (data, numero); ritenuta d'acconto della scheda del cliente. Rate: uspFattureRate_ins_Genera.
-- Pre-fatture (@IncludiPreFatture = 1): i documenti già in una pre-fattura rientrano e la pre-fattura viene
-- convertita PER INTERO: le sue righe (non ricalcolate dagli importi, con aliquota, conto e ritenuta che hanno)
-- vanno nella fattura del suo cliente insieme agli altri documenti, al posto del suo primo documento, e tutti i
-- suoi documenti, anche quelli fuori dal periodo, passano alla nuova fattura. Con @RimuoviPreFatture = 1 la
-- pre-fattura viene poi cancellata (Lock 4), altrimenti resta in elenco senza più documenti collegati.
-- Ogni documento resta legato alla fattura (tblFattureDocumenti, con importo e contratto applicati) e non
-- viene fatturato due volte: un documento fatturato nel frattempo da un'altra sessione fa saltare la sua fattura.
-- Una transazione per fattura. Restituisce Fatture, Documenti e IdFattura (l'ultima generata).
CREATE OR ALTER PROCEDURE dbo.uspFatture_ins_Genera
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@DataEmissione DATE = NULL,
	@PreFattura BIT = 0,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@IncludiPreFatture BIT = 0,
	@RimuoviPreFatture BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(NULLIF(LTRIM(RTRIM(@Id)), ''), REPLICATE('0', 16));
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @DataEmissione = ISNULL(@DataEmissione, CAST(GETDATE() AS DATE));
		SET @PreFattura = ISNULL(@PreFattura, 0);
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @RimuoviPreFatture = ISNULL(@RimuoviPreFatture, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND ISNULL(@IdModulo, '') NOT IN ('RIF', 'MAG')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF o MAG';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND (@DataDa IS NULL OR @DataA IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END
		-- Convertire le pre-fatture in altre pre-fatture non ha senso
		IF @PreFattura = 1 AND @IncludiPreFatture = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per includere le pre-fatture togliere la spunta "Genera come pre-fatture"';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari per generare le fatture';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		IF @Id IS NULL
		BEGIN
			SELECT @idAzienda = IdAzienda
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;

			IF @idAzienda IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''azienda';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Un solo documento, del suo modulo (registrazione dei rifiuti o DDT di magazzino), senza pre-fatture
			SET @Rifiuti = IIF(@IdModulo = 'RIF', 1, 0);
			SET @Magazzino = IIF(@IdModulo = 'MAG', 1, 0);
			SET @IncludiPreFatture = 0;
		END

		-- Procedura automatica: i DDT entrano solo con il modulo Magazzino attivo sul dominio
		IF @Id IS NULL AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
			SET @Magazzino = 0;

		-- Documenti da fatturare, con il raggruppamento della scheda del cliente
		DECLARE @doc TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdModulo CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,
			[Data] DATE NULL,
			Numero INT NULL,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdImporto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdOffertaContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdPreFattura CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			-- Primo documento della sua pre-fattura: porta le righe della pre-fattura e decide il gruppo
			PrimoDellaPreFattura BIT NOT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Fatturabile BIT NOT NULL
		);
		INSERT @doc (Id, IdModulo, [Data], Numero, IdAzienda, IdImporto, IdOffertaContratto, IdClienteFornitore, IdPreFattura, PrimoDellaPreFattura, GruppoSede, GruppoContratto, Fatturabile)
		SELECT
			d.Id,
			d.IdModulo,
			d.[Data],
			d.Numero,
			d.IdAzienda,
			d.IdImporto,
			d.IdOffertaContratto,
			ISNULL(d.IdClienteFornitore, REPLICATE('0', 16)),
			d.IdPreFattura,
			d.PrimoDellaPreFattura,
			d.GruppoSede,
			d.GruppoContratto,
			d.Fatturabile
		FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino) d
		WHERE
			(@Id IS NOT NULL OR d.Fatturabile = 1)
		OPTION (RECOMPILE);

		IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @doc WHERE Fatturabile = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il documento non è fatturabile: usare "Verifica importo e cliente" per vedere il motivo';
			GOTO BRANCH_END;
		END

		-- Righe di fattura di ogni documento, calcolate ora una volta per tutte: quelle dell'importo applicato
		-- oppure, per il primo documento di una pre-fattura, le righe della pre-fattura così come sono
		DECLARE @righe TABLE (
			N INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			IdDocumento CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdRiga CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(1000) NULL,
			SolaDescrizione BIT NOT NULL,
			Quantita DECIMAL(18, 4) NULL,
			IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			Importo DECIMAL(18, 4) NULL,
			IdAliquotaIva CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdConto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			-- NULL: la ritenuta è quella della scheda del cliente
			RitenutaAcconto INT NULL
		);
		INSERT @righe (IdDocumento, Descrizione, SolaDescrizione, Quantita, IdUnitaMisura, Importo, IdAliquotaIva, IdConto, RitenutaAcconto)
		SELECT
			t.IdDocumento,
			t.Descrizione,
			t.SolaDescrizione,
			t.Quantita,
			t.IdUnitaMisura,
			t.Importo,
			t.IdAliquotaIva,
			t.IdConto,
			t.RitenutaAcconto
		FROM
			(
				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = ISNULL(g.Pos, 0),
					Ordine = g.Id,
					g.Descrizione,
					g.SolaDescrizione,
					g.Quantita,
					g.IdUnitaMisura,
					g.Importo,
					g.IdAliquotaIva,
					g.IdConto,
					RitenutaAcconto = CAST(NULL AS INT)
				FROM
					@doc d
					CROSS APPLY dbo.ufnImportiRifiuti_get_RigheImporto(d.Id, d.IdImporto, d.IdClienteFornitore) g
				WHERE
					d.Fatturabile = 1
					AND d.IdPreFattura IS NULL
					AND d.IdModulo = 'RIF'

				UNION ALL

				-- DDT di magazzino: le righe dell'importo applicato, prima quelle a quantità nell'ordine del DDT, poi le altre
				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = g.Gruppo * 100000000 + g.PosDdt * 10000 + ISNULL(g.Pos, 0),
					Ordine = g.Id,
					g.Descrizione,
					g.SolaDescrizione,
					g.Quantita,
					g.IdUnitaMisura,
					g.Importo,
					g.IdAliquotaIva,
					g.IdConto,
					RitenutaAcconto = CAST(NULL AS INT)
				FROM
					@doc d
					CROSS APPLY dbo.ufnImportiMagazzino_get_RigheFattura(d.Id, d.IdClienteFornitore) g
				WHERE
					d.Fatturabile = 1
					AND d.IdPreFattura IS NULL
					AND d.IdModulo = 'MAG'

				UNION ALL

				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = ISNULL(r.Pos, 0),
					Ordine = r.Id,
					r.Descrizione,
					SolaDescrizione = CAST(IIF(i.Id IS NULL, 1, 0) AS BIT),
					i.Quantita,
					i.IdUnitaMisura,
					i.Importo,
					i.IdAliquotaIva,
					i.IdConto,
					RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0)
				FROM
					@doc d
					INNER JOIN dbo.tblFattureRighe r ON d.IdPreFattura = r.IdFattura
					LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				WHERE
					d.Fatturabile = 1
					AND d.PrimoDellaPreFattura = 1
			) t
		ORDER BY t.[Data], t.Numero, t.IdDocumento, t.Pos, t.Ordine;

		-- Una fattura per ogni gruppo: cliente e, secondo il raggruppamento, sede del produttore o contratto
		DECLARE @gruppi TABLE (
			N INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);
		INSERT @gruppi (IdAzienda, IdClienteFornitore, GruppoSede, GruppoContratto)
		SELECT
			t.IdAzienda,
			t.IdClienteFornitore,
			t.GruppoSede,
			t.GruppoContratto
		FROM
			(
				SELECT DISTINCT IdAzienda, IdClienteFornitore, GruppoSede, GruppoContratto
				FROM @doc
				WHERE Fatturabile = 1
			) t
			LEFT JOIN dbo.tblClientiFornitori c ON t.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		ORDER BY s.NomeCompleto, t.IdClienteFornitore, t.GruppoSede, t.GruppoContratto;

		DECLARE @fatture INT = 0;
		DECLARE @documenti INT = 0;
		DECLARE @idUltima CHAR(16) = NULL;
		DECLARE @n INT = 1;
		DECLARE @gruppiTotale INT = (SELECT COUNT(*) FROM @gruppi);
		DECLARE @gAzienda CHAR(16), @gCliente CHAR(16), @gSede CHAR(16), @gContratto CHAR(16);
		DECLARE @idFattura CHAR(16), @idRiga CHAR(16), @r INT, @numero INT;
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@DataEmissione), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @gDoc TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		DECLARE @gPre TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

		WHILE @n <= @gruppiTotale
		BEGIN
			SELECT
				@gAzienda = IdAzienda,
				@gCliente = IdClienteFornitore,
				@gSede = GruppoSede,
				@gContratto = GruppoContratto
			FROM @gruppi
			WHERE N = @n;

			DELETE @gDoc;
			INSERT @gDoc (Id)
			SELECT Id
			FROM @doc
			WHERE
				Fatturabile = 1
				AND IdAzienda = @gAzienda
				AND IdClienteFornitore = @gCliente
				AND ISNULL(GruppoSede, '') = ISNULL(@gSede, '')
				AND ISNULL(GruppoContratto, '') = ISNULL(@gContratto, '');

			-- Pre-fatture del gruppo, da convertire
			DELETE @gPre;
			INSERT @gPre (Id)
			SELECT DISTINCT IdPreFattura
			FROM @doc
			WHERE
				Id IN (SELECT Id FROM @gDoc)
				AND IdPreFattura IS NOT NULL;

			-- Id della fattura e delle sue righe: uspId_get FUORI dalla transazione
			SET @idFattura = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idFattura OUTPUT;

			SET @r = (SELECT MIN(N) FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
			WHILE @r IS NOT NULL
			BEGIN
				SET @idRiga = NULL;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRiga OUTPUT;
				UPDATE @righe SET IdRiga = @idRiga WHERE N = @r;
				SET @r = (SELECT MIN(N) FROM @righe WHERE N > @r AND IdDocumento IN (SELECT Id FROM @gDoc));
			END

			BEGIN TRANSACTION;
				-- Un documento fatturato nel frattempo da un'altra sessione (in una fattura che non è una delle
				-- pre-fatture da convertire), o una pre-fattura nel frattempo cancellata o diventata fattura:
				-- questa fattura non si genera
				IF EXISTS (
						SELECT 1
						FROM
							dbo.tblFattureDocumenti fd WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
						WHERE
							fd.Id IN (SELECT Id FROM @gDoc)
							AND f.Lock IN (0, 2)
							AND f.Id NOT IN (SELECT Id FROM @gPre)
					)
					OR EXISTS (
						SELECT 1
						FROM
							@gPre p
							LEFT JOIN dbo.tblFatture f WITH (UPDLOCK, HOLDLOCK) ON p.Id = f.Id
																			  AND f.Lock IN (0, 2)
																			  AND f.IdTipo = 'TD00'
						WHERE f.Id IS NULL
					)
				BEGIN
					ROLLBACK TRANSACTION;

					-- Gli Id presi per la fattura e per le sue righe non servono più
					DELETE dbo.tblIdLog
					WHERE Id = @idFattura OR Id IN (SELECT IdRiga FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
					DELETE dbo.tblId
					WHERE Id = @idFattura OR Id IN (SELECT IdRiga FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
				END
				ELSE
				BEGIN
					-- Numero: successivo al più alto tra le fatture cliente attive dell'azienda nell'anno della data
					-- di emissione, senza sezionale (stessa lettura con blocco di uspFatture_upd). La pre-fattura
					-- non ha numero
					SET @numero = NULL;
					IF @PreFattura = 0
						SELECT @numero = ISNULL(MAX(Numero), 0) + 1
						FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
						WHERE
							IdSede = @gAzienda
							AND Tipo = 'C'
							AND Lock = 0
							AND ISNULL(Sezionale, '') = ''
							AND DataEmissione >= @annoInizio
							AND DataEmissione < @annoFine;

					INSERT dbo.tblFatture (
						Id, IdSede, IdClienteFornitore, IdTipo, IdStato, IdModalita, IdRata, IdRataInizio, IdValuta, IdBancaCassa,
						Tipo, Numero, DataRegistrazione, DataEmissione, Iban, RataGiorniInizio, Ordine, DataOrdine,
						SplitPayment, Bollo, CodiceCig, CodiceCup, SolaLettura, Lock)
					SELECT
						@idFattura, @gAzienda, c.Id, IIF(@PreFattura = 1, 'TD00', 'TD01'), 'G', c.IdModalita, c.IdRata, ISNULL(c.IdRataInizio, 'DF'), ISNULL(c.IdValuta, 'EUR'), c.IdBancaCassa,
						'C', @numero, @DataEmissione, @DataEmissione, c.Iban, ISNULL(c.RataGiorniInizio, 0), oc.Ordine, oc.DataOrdine,
						ISNULL(c.SplitPayment, 0), 0, oc.CodiceCig, oc.CodiceCup, 0, 0
					FROM
						dbo.tblClientiFornitori c
						LEFT JOIN dbo.tblOfferteContratti oc ON oc.Id = @gContratto
					WHERE c.Id = @gCliente;

					INSERT dbo.tblFattureRighe (Id, IdFattura, Descrizione, Pos)
					SELECT
						g.IdRiga,
						@idFattura,
						g.Descrizione,
						ROW_NUMBER() OVER (ORDER BY g.N)
					FROM @righe g
					WHERE g.IdDocumento IN (SELECT Id FROM @gDoc);

					INSERT dbo.tblFattureRigheImporti (Id, IdAliquotaIva, IdConto, IdUnitaMisura, Quantita, Importo, RitenutaAcconto)
					SELECT
						g.IdRiga,
						g.IdAliquotaIva,
						g.IdConto,
						g.IdUnitaMisura,
						g.Quantita,
						g.Importo,
						ISNULL(g.RitenutaAcconto, ISNULL(c.RitenutaAcconto, 0))
					FROM
						@righe g
						INNER JOIN dbo.tblClientiFornitori c ON c.Id = @gCliente
					WHERE
						g.IdDocumento IN (SELECT Id FROM @gDoc)
						AND g.SolaDescrizione = 0;

					-- Pre-fatture convertite: tutti i loro documenti, anche quelli fuori dal periodo, passano alla
					-- nuova fattura (le righe della pre-fattura non si possono dividere per documento); importo e
					-- contratto applicati restano quelli già registrati
					UPDATE dbo.tblFattureDocumenti
					SET IdFattura = @idFattura
					WHERE IdFattura IN (SELECT Id FROM @gPre);

					IF @RimuoviPreFatture = 1
						UPDATE dbo.tblFatture
						SET Lock = 4
						WHERE Id IN (SELECT Id FROM @gPre);

					-- Legame degli altri documenti con la fattura, con l'importo e il contratto applicati; cliente
					-- indicato e spunta restano quelli già presenti
					UPDATE fd
					SET
						IdFattura = @idFattura,
						IdImporto = d.IdImporto,
						IdOffertaContratto = d.IdOffertaContratto
					FROM
						dbo.tblFattureDocumenti fd
						INNER JOIN @doc d ON fd.Id = d.Id
					WHERE
						d.Id IN (SELECT Id FROM @gDoc)
						AND d.IdPreFattura IS NULL;

					INSERT dbo.tblFattureDocumenti (Id, IdModulo, IdFattura, IdImporto, IdOffertaContratto, NonFatturabile)
					SELECT d.Id, d.IdModulo, @idFattura, d.IdImporto, d.IdOffertaContratto, 0
					FROM @doc d
					WHERE
						d.Id IN (SELECT Id FROM @gDoc)
						AND NOT EXISTS (SELECT 1 FROM dbo.tblFattureDocumenti x WHERE x.Id = d.Id);

					COMMIT TRANSACTION;

					SET @fatture += 1;
					SET @documenti += (SELECT COUNT(*) FROM @gDoc);
					SET @idUltima = @idFattura;

					-- Rate dalle condizioni di pagamento della fattura. Una fattura senza importo da pagare non
					-- ha rate: quell'errore applicativo non ferma la generazione
					BEGIN TRY
						EXEC dbo.uspFattureRate_ins_Genera @IdFattura = @idFattura, @IdSessione = @IdSessione, @Interno = 1;
					END TRY
					BEGIN CATCH
						IF ERROR_NUMBER() <> 50001
							THROW;
					END CATCH
				END

			SET @n += 1;
		END

		SELECT
			Fatture = @fatture,
			Documenti = @documenti,
			IdFattura = @idUltima;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFattureDocumenti_get.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione di un documento (blocco "Cliente a cui fatturare", comune alle schede di registrazioni dei
-- rifiuti, DDT di magazzino e servizi): cliente indicato sul documento, spunta "Non fatturabile", fattura in
-- cui è finito e l'anteprima di ciò che la generazione automatica userebbe ("Verifica importo e cliente":
-- cliente, importo, contratto, totale e avvisi). Le righe dell'anteprima: uspFattureDocumenti_get_Righe.
-- @IdModulo: RIF registrazione dei rifiuti, MAG movimento di magazzino con il suo DDT (SRV non ancora gestito:
-- nessuna riga). Per il DDT il confronto è per riga: importo, priorità e contratto si vedono solo se sono gli
-- stessi per tutte le righe.
-- Sempre una riga al massimo; nessuna riga (e nessun errore) se il blocco non va mostrato: modulo Offerte e
-- contratti non attivo sul dominio, documento non accessibile, operazione non fatturabile, rettifica. Così la
-- scheda del documento non dipende da questo modulo.
--   Modificabile: permesso di modifica sul documento, documento confermato e non ancora fatturato.
--   Fatturabile: la generazione automatica lo fatturerebbe (nessun avviso bloccante).
--   Avvisi: testi separati da '|'.
-- L'azienda è quella del documento (per i rifiuti, del registro), non quella del contesto della sessione.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Solo registrazioni dei rifiuti, con il modulo Offerte e contratti attivo sul dominio e almeno la
		-- lettura delle registrazioni
		DECLARE @permesso TINYINT = dbo.ufnFunzioni_get_PermessoBySessione('RRG', @IdSessione);
		IF ISNULL(@IdModulo, '') = 'RIF'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND @permesso >= 1
		BEGIN
			SELECT
				a.Id,
				IdModulo = CAST('RIF' AS CHAR(3)),
				Modificabile = CAST(IIF(@permesso >= 2 AND a.Lock = 0 AND a.IdFattura IS NULL, 1, 0) AS BIT),
				IdClienteIndicato = a.IdClienteIndicato,
				ClienteIndicato = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
				a.NonFatturabile,
				a.IdFattura,
				Fattura = IIF(a.IdFattura IS NULL, NULL, IIF(f.IdTipo = 'TD00', 'Pre-fattura', 'Fattura'))
					+ ISNULL(' ' + CAST(f.Numero AS VARCHAR(10)) + ISNULL('/' + f.Sezionale, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103), ''),
				-- Anteprima
				a.IdClienteFornitore,
				Cliente = sc.NomeCompleto + ISNULL(' ' + sc.IndirizzoCompleto, ''),
				a.ClienteOrigine,
				ClienteOrigineDescrizione = CASE a.ClienteOrigine
					WHEN 'D' THEN 'indicato sulla registrazione'
					WHEN 'C' THEN 'dal contratto dell''importo'
					WHEN 'P' THEN 'produttore del rifiuto (importo standard)'
				END,
				a.IdImporto,
				Importo = i.Nome,
				Priorita = p.Nome,
				Contratto = CASE
					WHEN a.IdImporto IS NULL THEN NULL
					WHEN a.IdOffertaContratto IS NULL THEN 'Nessuno (importo standard)'
					ELSE 'Contratto' + ISNULL(' ' + so.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				END,
				Totale = t.Totale,
				Fatturabile = CAST(IIF(
					a.Lock = 0 AND a.IsAnnullata = 0 AND a.NonFatturabile = 0 AND a.IdFattura IS NULL
					AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0, 1, 0) AS BIT),
				Avvisi = CAST(STUFF(
					IIF(a.Lock <> 0, '|La registrazione non è ancora salvata: salvarla prima di fatturarla', '')
					+ IIF(a.IdFattura IS NOT NULL, '|La registrazione è già stata fatturata', '')
					+ IIF(a.NonFatturabile = 1, '|La registrazione è indicata come non fatturabile', '')
					+ IIF(a.IsAnnullata = 1, '|La registrazione è annullata: non viene fatturata', '')
					+ IIF(a.IdImporto IS NULL, '|Nessun importo coincide con la registrazione: non viene fatturata', '')
					+ IIF(a.IdImportoScartato IS NOT NULL, '|L''importo "' + ISNULL(isc.Nome, '') + '" coincide con la registrazione, ma il suo contratto non è valido alla data della registrazione'
						+ IIF(a.IdImporto IS NOT NULL AND a.IdOffertaContratto IS NULL, ': è stato applicato l''importo standard', ''), '')
					+ IIF(a.IdClienteFornitore IS NULL, '|Cliente non determinato: il produttore non ha una scheda cliente. Indicare il cliente sulla registrazione', '')
					+ IIF(a.IdClienteFornitore IS NOT NULL AND ISNULL(t.SenzaIva, 0) > 0, '|Aliquota IVA non indicata né sulle righe dell''importo né sulla scheda del cliente', '')
					+ IIF(a.IdImporto IS NOT NULL AND ISNULL(t.Righe, 0) = 0, '|L''importo non ha righe applicabili a questa registrazione', '')
					+ IIF(a.IdImporto IS NOT NULL AND q.RigheQuantita > 0 AND ISNULL(t.RigheQuantita, 0) = 0, '|L''importo non ha righe per l''unità di misura della registrazione (' + ISNULL(a.IdUnitaMisura, 'non indicata') + ')', '')
					, 1, 1, '') AS VARCHAR(2000))
			FROM
				dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
				LEFT JOIN dbo.tblClientiFornitori ci ON a.IdClienteIndicato = ci.Id
				LEFT JOIN dbo.tblSedi si ON ci.IdSede = si.Id
				LEFT JOIN dbo.tblClientiFornitori cc ON a.IdClienteFornitore = cc.Id
				LEFT JOIN dbo.tblSedi sc ON cc.IdSede = sc.Id
				LEFT JOIN dbo.tblFatture f ON a.IdFattura = f.Id
				LEFT JOIN dbo.tblImporti i ON a.IdImporto = i.Id
				LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
				LEFT JOIN dbo.tblImporti isc ON a.IdImportoScartato = isc.Id
				LEFT JOIN dbo.tblOfferteContratti oc ON a.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori co ON oc.IdClienteFornitore = co.Id
				LEFT JOIN dbo.tblSedi so ON co.IdSede = so.Id
				OUTER APPLY (
					-- Righe che entrano in fattura: totale, numero, e quante sono a quantità (KG, T, L)
					SELECT
						Totale = SUM(ISNULL(g.Imponibile, 0)),
						Righe = COUNT(*),
						SenzaIva = SUM(IIF(g.SolaDescrizione = 0 AND g.IdAliquotaIva IS NULL, 1, 0)),
						RigheQuantita = SUM(IIF(g.SolaDescrizione = 0 AND g.MinimoFatturabile = 0 AND g.IdTipo <> 'RM', 1, 0))
					FROM dbo.ufnImportiRifiuti_get_ApplicazioneRighe(@Id) g
				) t
				OUTER APPLY (
					-- Righe a quantità dell'importo, comprese quelle che non valgono per l'unità della registrazione
					SELECT RigheQuantita = COUNT(*)
					FROM dbo.tblImportiRighe g
					WHERE
						g.IdImporto = a.IdImporto
						AND g.Importo IS NOT NULL
						AND ISNULL(g.MinimoFatturabile, 0) = 0
						AND g.IdTipo <> 'RM'
				) q
			WHERE
				a.IsFatturabile = 1
				AND a.IsRettifica = 0
			OPTION (RECOMPILE);
		END

		-- DDT di magazzino (Id = movimento), con il modulo Offerte e contratti attivo sul dominio e almeno la
		-- lettura dei movimenti. L'importo è uno solo per DDT e deve avere una riga per ogni suo articolo o materiale
		DECLARE @permessoMag TINYINT = dbo.ufnFunzioni_get_PermessoBySessione('MAG', @IdSessione);
		IF ISNULL(@IdModulo, '') = 'MAG'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND @permessoMag >= 1
		BEGIN
			SELECT
				a.Id,
				IdModulo = CAST('MAG' AS CHAR(3)),
				Modificabile = CAST(IIF(@permessoMag >= 2 AND a.Lock = 0 AND a.IdFattura IS NULL, 1, 0) AS BIT),
				IdClienteIndicato = a.IdClienteIndicato,
				ClienteIndicato = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
				a.NonFatturabile,
				a.IdFattura,
				Fattura = IIF(a.IdFattura IS NULL, NULL, IIF(f.IdTipo = 'TD00', 'Pre-fattura', 'Fattura'))
					+ ISNULL(' ' + CAST(f.Numero AS VARCHAR(10)) + ISNULL('/' + f.Sezionale, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103), ''),
				-- Anteprima
				a.IdClienteFornitore,
				Cliente = sc.NomeCompleto + ISNULL(' ' + sc.IndirizzoCompleto, ''),
				a.ClienteOrigine,
				ClienteOrigineDescrizione = CASE a.ClienteOrigine
					WHEN 'D' THEN 'indicato sul DDT'
					WHEN 'C' THEN 'dal contratto dell''importo'
					WHEN 'P' THEN 'destinatario del DDT (importo standard)'
				END,
				a.IdImporto,
				Importo = i.Nome,
				Priorita = p.Nome,
				Contratto = CASE
					WHEN a.IdImporto IS NULL THEN NULL
					WHEN a.IdOffertaContratto IS NULL THEN 'Nessuno (importo standard)'
					ELSE 'Contratto' + ISNULL(' ' + so.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				END,
				Totale = t.Totale,
				Fatturabile = CAST(IIF(
					a.Lock = 0 AND a.NonFatturabile = 0 AND a.IdFattura IS NULL
					AND a.Righe > 0 AND a.IdImporto IS NOT NULL AND a.RigheSenzaImporto = 0
					AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0, 1, 0) AS BIT),
				Avvisi = CAST(STUFF(
					IIF(a.Lock <> 0, '|Il DDT non è ancora salvato: salvarlo prima di fatturarlo', '')
					+ IIF(a.IdFattura IS NOT NULL, '|Il DDT è già stato fatturato', '')
					+ IIF(a.NonFatturabile = 1, '|Il DDT è indicato come non fatturabile', '')
					+ IIF(a.Righe = 0, '|Il DDT non ha righe di articoli o di materiali: non viene fatturato', '')
					+ IIF(a.Righe > 0 AND a.IdImporto IS NULL, '|Nessun importo coincide con il DDT: non viene fatturato', '')
					+ IIF(a.IdImporto IS NOT NULL AND a.RigheSenzaImporto > 0, '|L''importo "' + ISNULL(i.Nome, '') + '" non ha una riga per ' + ISNULL(n.Voci, '')
						+ ': il DDT non viene fatturato', '')
					+ IIF(a.IdImportoScartato IS NOT NULL, '|L''importo "' + ISNULL(isc.Nome, '') + '" coincide con il DDT, ma il suo contratto non è valido alla data del DDT'
						+ IIF(a.IdImporto IS NOT NULL AND a.IdOffertaContratto IS NULL, ': è stato applicato l''importo standard', ''), '')
					+ IIF(a.IdClienteFornitore IS NULL, '|Cliente non determinato: il destinatario non ha una scheda cliente. Indicare il cliente sul DDT', '')
					+ IIF(a.IdClienteFornitore IS NOT NULL AND ISNULL(t.SenzaIva, 0) > 0, '|Aliquota IVA non indicata né sulle righe dell''importo né sulla scheda del cliente', '')
					, 1, 1, '') AS VARCHAR(2000))
			FROM
				dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
				LEFT JOIN dbo.tblClientiFornitori ci ON a.IdClienteIndicato = ci.Id
				LEFT JOIN dbo.tblSedi si ON ci.IdSede = si.Id
				LEFT JOIN dbo.tblClientiFornitori cc ON a.IdClienteFornitore = cc.Id
				LEFT JOIN dbo.tblSedi sc ON cc.IdSede = sc.Id
				LEFT JOIN dbo.tblFatture f ON a.IdFattura = f.Id
				LEFT JOIN dbo.tblImporti i ON a.IdImporto = i.Id
				LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
				LEFT JOIN dbo.tblImporti isc ON a.IdImportoScartato = isc.Id
				LEFT JOIN dbo.tblOfferteContratti oc ON a.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori co ON oc.IdClienteFornitore = co.Id
				LEFT JOIN dbo.tblSedi so ON co.IdSede = so.Id
				OUTER APPLY (
					-- Righe che entrano in fattura
					SELECT
						Totale = SUM(ISNULL(g.Imponibile, 0)),
						Righe = COUNT(*),
						SenzaIva = SUM(IIF(g.SolaDescrizione = 0 AND g.IdAliquotaIva IS NULL, 1, 0))
					FROM dbo.ufnImportiMagazzino_get_RigheFattura(@Id, a.IdClienteFornitore) g
				) t
				OUTER APPLY (
					-- Articoli e materiali del DDT che l'importo applicato non prezza, per l'avviso
					SELECT Voci = STRING_AGG(CAST('"' + ISNULL(r.Voce, '') + '"' AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY ISNULL(r.Pos, 0), r.IdRiga)
					FROM dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, NULL, NULL, NULL, 0) r
					WHERE r.IdRigaImporto IS NULL
				) n
			WHERE a.IsFatturabile = 1
			OPTION (RECOMPILE);
		END

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFattureDocumenti_get_Righe.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- "Verifica importo e cliente": righe di fattura che la generazione automatica creerebbe per il documento, con
-- l'importo che gli viene applicato (ufnImportiRifiuti_get_ApplicazioneRighe). Stessi controlli di accesso di
-- uspFattureDocumenti_get: senza accesso, o per un modulo non gestito, nessuna riga e nessun errore.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Righe
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF ISNULL(@IdModulo, '') = 'RIF'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND dbo.ufnFunzioni_get_PermessoBySessione('RRG', @IdSessione) >= 1
		BEGIN
			SELECT
				g.Id,
				g.Pos,
				g.Descrizione,
				g.SolaDescrizione,
				g.MinimoFatturabile,
				g.Quantita,
				UnitaMisura = g.IdUnitaMisura,
				g.Importo,
				g.Imponibile,
				AliquotaIvaNome = v.Nome,
				ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome
			FROM
				dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
				CROSS APPLY dbo.ufnImportiRifiuti_get_ApplicazioneRighe(a.Id) g
				LEFT JOIN dbo.tblAliquoteIva v ON g.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblFattureConti c ON g.IdConto = c.Id
			WHERE
				a.IsFatturabile = 1
				AND a.IsRettifica = 0
			ORDER BY ISNULL(g.Pos, 0), g.Id
			OPTION (RECOMPILE);
		END


		-- DDT di magazzino: le righe dell'importo applicato, prima quelle a quantità nell'ordine del DDT, poi le altre
		IF ISNULL(@IdModulo, '') = 'MAG'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND dbo.ufnFunzioni_get_PermessoBySessione('MAG', @IdSessione) >= 1
		BEGIN
			SELECT
				g.Id,
				Pos = CAST(ROW_NUMBER() OVER (ORDER BY g.Gruppo, g.PosDdt, g.IdRigaDdt, ISNULL(g.Pos, 0), g.Id) AS INT),
				g.Descrizione,
				g.SolaDescrizione,
				g.MinimoFatturabile,
				g.Quantita,
				UnitaMisura = g.IdUnitaMisura,
				g.Importo,
				g.Imponibile,
				AliquotaIvaNome = v.Nome,
				ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome
			FROM
				dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
				CROSS APPLY dbo.ufnImportiMagazzino_get_RigheFattura(a.Id, a.IdClienteFornitore) g
				LEFT JOIN dbo.tblAliquoteIva v ON g.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblFattureConti c ON g.IdConto = c.Id
			WHERE a.IsFatturabile = 1
			ORDER BY g.Gruppo, g.PosDdt, g.IdRigaDdt, ISNULL(g.Pos, 0), g.Id
			OPTION (RECOMPILE);
		END

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFattureDocumenti_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva sul documento (registrazione dei rifiuti; DDT e servizi non ancora gestiti) il cliente a cui fatturarlo
-- e la spunta "Non fatturabile". Si salvano da soli, senza il "Salva" della scheda: valgono anche per una
-- registrazione già inviata al RENTRI, che non si può più modificare, perché non fanno parte del registro.
--   @IdClienteFornitore NULL: nessun cliente indicato (lo decide l'importo applicato).
-- Serve il permesso di modifica sul documento; il documento deve essere confermato e non ancora fatturato.
-- Senza cliente e senza spunta la riga di tblFattureDocumenti viene tolta.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_upd
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@NonFatturabile BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @NonFatturabile = ISNULL(@NonFatturabile, 0);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IdModulo, '') NOT IN ('RIF', 'MAG')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF o MAG';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sul documento (registrazioni dei rifiuti o gestione del magazzino) e modulo Offerte e
		-- contratti attivo sul dominio
		DECLARE @idFunzione CHAR(3) = IIF(@IdModulo = 'MAG', 'MAG', 'RRG');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il documento: accessibile dalla sessione e fatturabile (ufnFattureDocumenti_get_Documento)
		DECLARE @idAzienda CHAR(16);
		DECLARE @lock INT;
		DECLARE @idFattura CHAR(16);
		DECLARE @idClienteAttuale CHAR(16);
		SELECT
			@idAzienda = a.IdAzienda,
			@lock = a.Lock,
			@idFattura = a.IdFattura,
			@idClienteAttuale = a.IdClienteIndicato
		FROM
			dbo.ufnFattureDocumenti_get_Documento(@Id, @IdModulo, @IdSessione) a
		WHERE a.IsFatturabile = 1;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il documento non è fatturabile';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Salvare il documento prima di indicare il cliente';
			GOTO BRANCH_END;
		END
		IF @idFattura IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il documento è già stato fatturato: cliente e spunta non si possono più modificare';
			GOTO BRANCH_END;
		END

		-- Cliente: una scheda cliente attiva dell'azienda del documento; quella già indicata resta valida
		IF @IdClienteFornitore IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'C'
				AND (Lock = 0 OR Id = @idClienteAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il cliente indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @IdClienteFornitore IS NULL AND @NonFatturabile = 0
			BEGIN
				-- Nulla da ricordare: la riga resta solo se porta ancora il legame con una fattura cancellata
				DELETE dbo.tblFattureDocumenti
				WHERE
					Id = @Id
					AND IdFattura IS NULL;

				UPDATE dbo.tblFattureDocumenti
				SET
					IdClienteFornitore = NULL,
					NonFatturabile = 0
				WHERE Id = @Id;
			END
			ELSE
			BEGIN
				UPDATE dbo.tblFattureDocumenti WITH (UPDLOCK, HOLDLOCK)
				SET
					IdClienteFornitore = @IdClienteFornitore,
					NonFatturabile = @NonFatturabile
				WHERE Id = @Id;

				IF @@ROWCOUNT = 0
					INSERT dbo.tblFattureDocumenti (Id, IdModulo, IdClienteFornitore, NonFatturabile)
					VALUES (@Id, @IdModulo, @IdClienteFornitore, @NonFatturabile);
			END
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFattureDocumenti_del_Fattura.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- "Togli la fattura": scollega il documento (registrazione dei rifiuti; DDT e servizi non ancora gestiti) dalla
-- fattura in cui è stato fatturato. La fattura NON viene cancellata né modificata: le sue righe restano come
-- sono. Il documento torna fatturabile, quindi una nuova generazione lo fatturerebbe di nuovo.
-- Cliente indicato e spunta "Non fatturabile" restano; importo e contratto applicati alla generazione vengono
-- azzerati. Serve il permesso di modifica sul documento. Un documento non fatturato non è un errore.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_del_Fattura
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IdModulo, '') NOT IN ('RIF', 'MAG')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF o MAG';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sul documento (registrazioni dei rifiuti o gestione del magazzino) e modulo Offerte e
		-- contratti attivo sul dominio
		DECLARE @idFunzione CHAR(3) = IIF(@IdModulo = 'MAG', 'MAG', 'RRG');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il documento deve essere accessibile dalla sessione (ufnFattureDocumenti_get_Documento)
		IF NOT EXISTS (SELECT 1 FROM dbo.ufnFattureDocumenti_get_Documento(@Id, @IdModulo, @IdSessione))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblFattureDocumenti
			SET
				IdFattura = NULL,
				IdImporto = NULL,
				IdOffertaContratto = NULL
			WHERE Id = @Id;

			-- Nulla da ricordare: né cliente indicato né spunta
			DELETE dbo.tblFattureDocumenti
			WHERE
				Id = @Id
				AND IdClienteFornitore IS NULL
				AND ISNULL(NonFatturabile, 0) = 0;
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspFattureDocumenti_get_Clienti_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Clienti tra cui scegliere quello a cui fatturare un documento (link "Seleziona" del blocco "Cliente a cui
-- fatturare"): schede cliente attive dell'azienda del documento (per i rifiuti, quella del registro: non
-- quella del contesto della sessione), al massimo 50, filtrabili per nome, partita IVA o codice fiscale.
-- Si legge con il permesso sul documento, senza quello sulle anagrafiche dei clienti.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Clienti_List
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IdModulo, '') NOT IN ('RIF', 'MAG')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF o MAG';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sul documento (registrazioni dei rifiuti o gestione del magazzino) e modulo Offerte e
		-- contratti attivo sul dominio
		DECLARE @idFunzione CHAR(3) = IIF(@IdModulo = 'MAG', 'MAG', 'RRG');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Azienda del documento, se accessibile dalla sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = a.IdAzienda
		FROM dbo.ufnFattureDocumenti_get_Documento(@Id, @IdModulo, @IdSessione) a;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			c.Id,
			[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
			Selected = CAST(0 AS BIT)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.IdAziendaInterna = @idAzienda
			AND c.Tipo = 'C'
			AND c.Lock = 0
			AND ISNULL(s.Disabilitata, 0) = 0
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
				OR s.PartitaIva LIKE '%' + @Search + '%'
				OR s.CodiceFiscale LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto, c.Id
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'sql/procedures/uspSedi_del_SediEsterne.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediEsterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANS',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI, senza protezione anti-doppio-submit sul pulsante) — la
			-- si tratta come cancellazione già avvenuta con successo, non come errore: lo stato
			-- desiderato ("questa sede non esiste") è già raggiunto.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede condivisa da altre aziende non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeOsepe ao
				INNER JOIN dbo.tblAree a ON ao.Id = a.Id
				WHERE
					ao.IdOsepe = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''autorizzazione rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
			-- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
			-- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne)
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Anagrafica estesa: un soggetto con una scheda cliente o fornitore attiva
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede presente tra i clienti o i fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Offerte e contratti: una sede indicata tra le variabili di un importo attivo
			IF EXISTS (
					SELECT 1
					FROM dbo.tblImportiRifiuti r
					INNER JOIN dbo.tblImporti i ON r.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (r.IdProduttoreParent, r.IdProduttore, r.IdTrasportatore, r.IdDestinatario, r.IdIntermediario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiMagazzino m
					INNER JOIN dbo.tblImporti i ON m.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (m.IdDestinatarioParent, m.IdDestinatario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiServizi v
					INNER JOIN dbo.tblImporti i ON v.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (v.IdRichiedenteParent, v.IdRichiedente, v.IdEsecutore)
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede indicata in un importo non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Anagrafica estesa: un soggetto con una scheda amministratore attiva, o
			-- amministrato da un amministratore attivo
			IF EXISTS (SELECT 1 FROM dbo.tblAmministratori WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede presente tra gli amministratori non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblAmministratoriSedi x
					INNER JOIN dbo.tblAmministratori a ON x.Id = a.Id
				WHERE
					x.IdSede = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede amministrata da un amministratore non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				-- Unità locale: se la sede cancellata è una sede figlia con il flag, lo eredita
				-- il soggetto, così il gruppo non resta mai senza un'unità locale attiva
				UPDATE p
				SET p.UnitaLocale = 1
				FROM dbo.tblSedi p
				INNER JOIN dbo.tblSedi s ON s.IdParent = p.Id
				WHERE
					s.Id = @Id
					AND s.UnitaLocale = 1
					AND p.Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				-- Modulo Magazzino: DDT dove questa sede esterna compare come mittente,
				-- destinatario, destinazione o trasportatore. Ramo di fatto irraggiungibile in
				-- pratica (blocco sopra su Lock=0), mantenuto per difesa dalla FK.
				DELETE dbo.tblMagazziniDdt
				WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id;

				-- Anagrafica estesa: schede cliente/fornitore del soggetto (una bozza di norma non
				-- ne ha), per difesa dalla FK NO_ACTION
				DELETE dbo.tblClientiFornitori
				WHERE IdSede = @Id;

				-- Anagrafica estesa: schede amministratore del soggetto con i loro amministrati, e
				-- il soggetto stesso tra gli amministrati di altre schede (stessa difesa dalla FK)
				DELETE dbo.tblAmministratoriSedi
				WHERE
					IdSede = @Id
					OR Id IN (SELECT Id FROM dbo.tblAmministratori WHERE IdSede = @Id);
				DELETE dbo.tblAmministratori
				WHERE IdSede = @Id;

				-- Tabelle 1:1 sulla sede (FK NO_ACTION): una bozza di norma non ne ha
				DELETE dbo.tblSediDatiEstesi
				WHERE Id = @Id;
				DELETE dbo.tblSediRecapiti
				WHERE Id = @Id;
				DELETE dbo.tblSediIndirizzi
				WHERE Id = @Id;

				DELETE dbo.tblAreeOsepe
				WHERE IdOsepe = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL. In
				-- pratica non popolata per una sede esterna (blocco sopra su Lock=0 comunque già la
				-- impedisce), mantenuta per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				DELETE dbo.tblSediEsterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;



PRINT 'sql/procedures/uspSedi_del_SediInterne.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediInterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'AZI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI) — trattata come cancellazione già avvenuta con successo,
			-- non come errore.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			-- Titolarità: Admin dello stesso Dominio della sede, oppure Admin di un Dominio Master.
			-- Il bypass Master è intenzionale (confermato dall'utente): un Master-admin deve poter
			-- cancellare/modificare aziende interne di qualsiasi dominio, non solo del proprio.
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
				INNER JOIN dbo.tblUtenti a ON i.IdDominio = a.IdDominio
				INNER JOIN dbo.tblSessioni e ON a.Id = e.IdUtente
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
					AND a.IdRuolo = 'AD'
					AND a.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
				WHERE
					e.Id = @IdSessione
					AND ut.IdRuolo = 'AD'
					AND ut.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblSediEsterne e INNER JOIN dbo.tblSedi s ON e.Id = s.Id
			WHERE
				e.IdSedeInterna = @Id
				AND s.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''azienda con soggetti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblOggetti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con oggetti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblPersone
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con persone associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblCalendari
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con calendari associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti/Righe hanno
			-- IdSede = sede operativa (può essere una sede figlia diversa dall'Azienda)
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con articoli di magazzino associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con lotti di magazzino associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con movimenti di magazzino associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdSede = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con righe di magazzino associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdSede = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con righe EoW di magazzino associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdSede = @Id OR IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Moduli Anagrafica estesa e Fatturazione: schede clienti/fornitori, banche e casse,
			-- aliquote IVA proprie appartengono all'azienda interna
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdAziendaInterna = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con clienti o fornitori associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblAmministratori WHERE IdAziendaInterna = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con amministratori associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con banche o casse associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con aliquote IVA associate non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con fatture associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblFattureConti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con conti di fatturazione associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Offerte e contratti: importi e offerte o contratti dell'azienda, e sedi indicate tra le
			-- variabili di un importo attivo
			IF EXISTS (SELECT 1 FROM dbo.tblImporti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con importi associati non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblOfferteContratti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con offerte o contratti associati non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (
					SELECT 1
					FROM dbo.tblImportiRifiuti r
					INNER JOIN dbo.tblImporti i ON r.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (r.IdProduttoreParent, r.IdProduttore, r.IdTrasportatore, r.IdDestinatario, r.IdIntermediario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiMagazzino m
					INNER JOIN dbo.tblImporti i ON m.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (m.IdSedePartenza, m.IdDestinatarioParent, m.IdDestinatario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiServizi v
					INNER JOIN dbo.tblImporti i ON v.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (v.IdRichiedenteParent, v.IdRichiedente, v.IdEsecutore)
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede indicata in un importo non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Gestione EoW: stesso controllo del magazzino tradizionale, su lotti/allocazioni EoW
			-- proprie della sede (IdSede è sempre la Sede Interna, non quella esterna condivisa)
			IF EXISTS (SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con lotti EoW associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con allocazioni EoW associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con magazzini EoW associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con registri c/s rifiuti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEtichette
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con etichette associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblTipi
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con tipi di scadenze/servizi associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeSediInterne ai
				INNER JOIN dbo.tblAree a ON ai.Id = a.Id
				WHERE
					ai.IdSede = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Dichiarazione MUD: azienda dichiarante (IdSede), sede legale e unità locale
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiMud
			WHERE
				(IdSede = @Id OR IdSedeLegale = @Id OR IdSedeUnitaLocale = @Id)
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con dichiarazioni MUD associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con autorizzazioni rifiuti associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiLimiti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con limiti rifiuti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRentriRegistri rr
				INNER JOIN dbo.tblRifiutiRegistri r ON rr.Id = r.Id
				WHERE r.IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con registri RENTRI associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				-- Unità locale: se la sede cancellata è una sede figlia con il flag, lo eredita
				-- l'azienda, così il gruppo non resta mai senza un'unità locale attiva
				UPDATE p
				SET p.UnitaLocale = 1
				FROM dbo.tblSedi p
				INNER JOIN dbo.tblSedi s ON s.IdParent = p.Id
				WHERE
					s.Id = @Id
					AND s.UnitaLocale = 1
					AND p.Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Dichiarazione MUD: una dichiarazione non si elimina mai insieme alla sede, quindi qui
			-- blocca in qualunque stato (la FK NO_ACTION fermerebbe comunque la cancellazione fisica)
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiMud
			WHERE IdSede = @Id OR IdSedeLegale = @Id OR IdSedeUnitaLocale = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con dichiarazioni MUD associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblUtentiSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblAreeSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblCalendari
				WHERE IdSede = @Id;
				DELETE dbo.tblEtichette
				WHERE IdSede = @Id;

				-- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE
				-- CASCADE). Ramo di fatto irraggiungibile in pratica (i blocchi sopra su Lock=0
				-- impediscono di arrivare in bozza con dati di magazzino già associati),
				-- mantenuto per difesa dalla FK.
				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
				INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
				WHERE r.IdSede = @Id OR r.IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
				INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
				WHERE re.IdSede = @Id;

				DELETE dbo.tblMagazziniDdt
				WHERE
					IdSede = @Id
					OR IdMittente = @Id
					OR IdDestinatario = @Id
					OR IdDestinazione = @Id
					OR IdTrasportatore = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimentiRighe
				WHERE
					IdSede = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimentiRigheEoW
				WHERE
					IdSede = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimenti
				WHERE IdSede = @Id;

				DELETE dbo.tblMagazziniLotti
				WHERE IdSede = @Id;

				DELETE dbo.tblMagazziniArticoli
				WHERE IdSede = @Id;

				-- Anagrafica estesa e Fatturazione: in bozza l'azienda non dovrebbe averne, mantenuto
				-- per difesa dalle FK (prima le schede, che referenziano banche/casse e aliquote)
				-- Fatture dell'azienda con righe e rate, poi i conti (prima delle schede e delle banche,
				-- che le fatture referenziano)
				DELETE dbo.tblFattureRigheImporti
				WHERE Id IN (SELECT r.Id FROM dbo.tblFattureRighe r INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id WHERE f.IdSede = @Id);
				DELETE dbo.tblFattureRighe
				WHERE IdFattura IN (SELECT Id FROM dbo.tblFatture WHERE IdSede = @Id);
				DELETE dbo.tblFattureRatePagamenti
				WHERE IdRata IN (SELECT r.Id FROM dbo.tblFattureRate r INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id WHERE f.IdSede = @Id);
				DELETE dbo.tblFattureRate
				WHERE IdFattura IN (SELECT Id FROM dbo.tblFatture WHERE IdSede = @Id);
				UPDATE dbo.tblFatture
				SET IdFatturaRiferimento = NULL
				WHERE IdSede = @Id;
				DELETE dbo.tblFatture
				WHERE IdSede = @Id;
				DELETE dbo.tblPagamenti
				WHERE
					IdSede = @Id
					OR IdBancaCassa IN (SELECT Id FROM dbo.tblBancheCasse WHERE IdSede = @Id);
				DELETE dbo.tblFattureConti
				WHERE IdSede = @Id;
				DELETE dbo.tblFattureDatiFiscali
				WHERE Id = @Id;
				DELETE dbo.tblClientiFornitori
				WHERE IdAziendaInterna = @Id;

				DELETE dbo.tblAmministratoriSedi
				WHERE Id IN (SELECT Id FROM dbo.tblAmministratori WHERE IdAziendaInterna = @Id);
				DELETE dbo.tblAmministratori
				WHERE IdAziendaInterna = @Id;

				DELETE dbo.tblBancheCasse
				WHERE IdSede = @Id;

				DELETE dbo.tblAliquoteIva
				WHERE IdSede = @Id;

				-- Gestione EoW: lotti/allocazioni EoW di proprietà esclusiva della sede (IdSede sempre
				-- Sede Interna) e le loro righe di collegamento M:N, nell'ordine figlio->padre richiesto
				-- dalle FK NO_ACTION (stesso ordine/logica di uspSYS_del_SedeInternaCascade).
				DELETE lrr
				FROM dbo.tblEoWLottiRifiutiRegistrazioni lrr
				INNER JOIN dbo.tblEoWLotti l ON lrr.IdLotto = l.Id
				WHERE l.IdSede = @Id;

				DELETE la
				FROM dbo.tblEoWLottiAllocazioni la
				LEFT JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
				LEFT JOIN dbo.tblEoWAllocazioni al ON la.IdAllocazione = al.Id
				WHERE
					l.IdSede = @Id
					OR al.IdSede = @Id;

				DELETE dbo.tblEoWLotti
				WHERE IdSede = @Id;

				DELETE dbo.tblEoWAllocazioni
				WHERE IdSede = @Id;

				-- tblEoWLotti.IdMagazzino (FK NO_ACTION) va rimosso prima: i Lotti di questa sede sono
				-- già stati cancellati sopra, un eventuale Lotto esterno che referenziasse un Magazzino
				-- di questa sede è di fatto irraggiungibile in pratica (bozza non linkabile da UI prima
				-- della finalizzazione), mantenuto per difesa dalla FK.
				DELETE dbo.tblEoWMagazzini
				WHERE IdSede = @Id;

				DELETE dbo.tblRifiutiAutorizzazioni
				WHERE IdSede = @Id;

				-- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
				-- bloccherebbe altrimenti la cancellazione del registro sottostante.
				DELETE dbo.tblRifiutiLimitiEer
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimitiEtichette
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimitiOperazioni
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimiti
				WHERE IdSede = @Id;

				-- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL,
				-- nessun ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante
				-- fallisce per FK. Ramo di fatto irraggiungibile in pratica (il blocco sopra su
				-- Lock=0 impedisce di arrivare in bozza con registri RENTRI già associati).
				DELETE dbo.tblRentriRegistri
				WHERE Id IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = @Id);

				DELETE dbo.tblRifiutiRegistri
				WHERE IdSede = @Id;
				DELETE dbo.tblTipi
				WHERE IdSede = @Id;
				DELETE dbo.tblOggetti
				WHERE IdSede = @Id;
				DELETE dbo.tblPersone
				WHERE IdSede = @Id;
				DELETE dbo.tblSediEsterne
				WHERE IdSedeInterna = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL
				-- (nessuna colonna da azzerare) - si cancella la riga di associazione, mai
				-- tblRentriCredenziali stessa. Ramo di fatto irraggiungibile in pratica (blocco
				-- sopra su Lock=0), mantenuto per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				-- Tabelle 1:1 sulla sede (FK NO_ACTION): una bozza di norma non ne ha
				DELETE dbo.tblSediDatiEstesi
				WHERE Id = @Id;
				DELETE dbo.tblSediRecapiti
				WHERE Id = @Id;
				DELETE dbo.tblSediIndirizzi
				WHERE Id = @Id;

				DELETE dbo.tblSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;



PRINT 'sql/procedures/uspSYS_del_SedeEsternaCascade.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeEsternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'E')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede esterna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + eventuali sotto-sedi collegate tramite tblSedi.IdParent (es. altre
        -- sedi/filiali dello stesso cliente/fornitore esterno), a qualunque profondità. A
        -- differenza di una sede interna, da una sede esterna NON si scende mai tramite
        -- IdAziendaInterna (punta sempre in alto verso la sede interna che la gestisce, mai verso
        -- un'altra sede da cancellare) né tramite tblSediEsterne.IdSedeInterna (stesso concetto).
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT s.Id
            FROM dbo.tblSedi s
            INNER JOIN #Sedi c ON s.IdParent = c.Id
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = s.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). Stessa struttura
        -- generica di uspSYS_del_SedeInternaCascade: tutte queste tabelle referenziano tblSedi.Id
        -- indipendentemente dal tipo (interna/esterna), anche se in pratica per una sede esterna
        -- oggi solo Autorizzazioni e Movimenti risultano popolati (verificato). Gestione EoW esclusa:
        -- i Magazzini EoW sono di sede interna (confermato dall'utente), una sede esterna non ne ha
        -- di propri - può però avere un proprio Registro/Registrazioni referenziati da movimenti EoW
        -- di un magazzino interno, gestiti più sotto.
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa: schede cliente/fornitore sul soggetto
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori WHERE IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture delle schede cliente/fornitore del soggetto
        SELECT Id INTO #Fatture FROM dbo.tblFatture WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti* non è mai popolato per una sede esterna (i Limiti si possono creare
        -- solo su sedi interne, confermato dall'utente): a differenza di uspSYS_del_SedeInternaCascade,
        -- qui non serve raccoglierlo/cancellarlo.

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe sono giunzioni a chiave composita verso risorse condivise
        -- a livello di Dominio (tblAree), non di proprietà della sede: si cancellano solo le righe
        -- di giunzione, mai tblAree stessa.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che coprono le loro
        -- rate, raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche rate di
        -- altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti che alla
        -- fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT DISTINCT rp.IdPagamento AS Id INTO #PagamentiCandidati
        FROM dbo.tblFattureRatePagamenti rp
        WHERE rp.IdRata IN (SELECT Id FROM #FattureRate);

        -- Offerte e contratti: offerte e contratti delle schede cliente del soggetto
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, etichette, tipi e
            -- sedi cancellati più sotto. I documenti fatturabili (registrazioni, servizi) hanno lo
            -- stesso Id del documento. Gli importi dei contratti cancellati restano all'azienda
            -- interna, senza contratto
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            -- Importi che citano una sede, un'etichetta o un tipo della cascata: perdono solo la variabile
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEsecutore = NULL WHERE IdEsecutore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: questa sede esterna non ha lotti/allocazioni EoW propri (che referenziano
            -- solo Sede Interna), ma le sue Registrazioni possono essere referenziate da
            -- tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK composta con
            -- IdLotto) - non azzerabile come il vecchio tblEoWMovimenti.IdRegistrazione (nullable),
            -- va rimossa la riga di collegamento; il Lotto di una sede interna resta intatto.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            -- In pratica un Registro RENTRI appartiene sempre a una sede interna, ma la SP resta
            -- generica per coerenza con la raccolta #RifiutiRegistri già fatta sopra.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata (stessa logica
            -- ibrida di uspSYS_del_SedeInternaCascade: UPDATE=NULL dove la colonna è nullable,
            -- DELETE della riga di giunzione dove è NOT NULL).
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
            -- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
            -- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne). Il DDT viene rimosso,
            -- il movimento di magazzino della sede interna resta.
            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi);

            -- Anagrafica estesa: schede cliente/fornitore sul soggetto
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);

            -- Anagrafica estesa: schede amministratore del soggetto con i loro amministrati, e il
            -- soggetto tolto dagli amministrati delle altre schede
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree non toccata)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare). In pratica associata solo a sedi interne, ma la SP resta generica
            -- per lo stesso motivo della raccolta #RifiutiRegistri sopra.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: il vincolo
            -- auto-referenziato IdParent è verificato a fine istruzione (non riga per riga), quindi
            -- non si blocca da solo anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;

PRINT 'sql/procedures/uspSYS_del_SedeInternaCascade.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: lotti/allocazioni/magazzini specifici EoW di proprietà della sede (solo sedi
        -- interne, IdSede diretto su tutte e tre le tabelle) - vedi project_eow_module_design in
        -- memoria persistente.
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWAllocazioni FROM dbo.tblEoWAllocazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti hanno IdSede = sede
        -- operativa (può essere una sede figlia diversa dall'Azienda) - vedi project_magazzino
        -- in memoria persistente.
        SELECT Id INTO #MagArticoli FROM dbo.tblMagazziniArticoli WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagLotti FROM dbo.tblMagazziniLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagMovimenti FROM dbo.tblMagazziniMovimenti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa e Fatturazione: schede dell'azienda (o sul soggetto, se nella cascata),
        -- banche/casse e aliquote IVA proprie dell'azienda
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Schede amministratore dell'azienda (o su un soggetto della cascata)
        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture dell'azienda (o di una scheda della cascata) e conti dell'azienda
        SELECT Id INTO #Fatture FROM dbo.tblFatture
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);
        SELECT Id INTO #FattureConti FROM dbo.tblFattureConti WHERE IdSede IN (SELECT Id FROM #Sedi);        SELECT Id INTO #BancheCasse FROM dbo.tblBancheCasse WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #AliquoteIva FROM dbo.tblAliquoteIva WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Dichiarazioni MUD dell'azienda o che citano una sede della cascata
        SELECT Id INTO #RifiutiMud FROM dbo.tblRifiutiMud
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdSedeLegale IN (SELECT Id FROM #Sedi) OR IdSedeUnitaLocale IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che potrebbero essere
        -- cancellati (quelli dell'azienda o delle sue banche e casse, e quelli che coprono rate di
        -- queste fatture), raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche
        -- rate di altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti
        -- che alla fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #PagamentiCandidati FROM (
            SELECT Id FROM dbo.tblPagamenti
            WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi)
            UNION
            SELECT rp.IdPagamento FROM dbo.tblFattureRatePagamenti rp
            WHERE rp.IdRata IN (SELECT Id FROM #FattureRate)
        ) x;

        -- Offerte e contratti: importi (con le righe) e offerte o contratti dell'azienda, o di una
        -- scheda cliente della cascata
        SELECT Id INTO #Importi FROM dbo.tblImporti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #ImportiRighe FROM dbo.tblImportiRighe WHERE IdImporto IN (SELECT Id FROM #Importi);
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, conti, aliquote,
            -- etichette, tipi e sedi cancellati più sotto. I documenti fatturabili (registrazioni,
            -- movimenti di magazzino, servizi) hanno lo stesso Id del documento
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #MagMovimenti)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdImporto IN (SELECT Id FROM #Importi)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti
            WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti) OR IdImporto IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblImportiRigheDettagli WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRighe WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRifiuti WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiMagazzino WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiServizi WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImporti WHERE Id IN (SELECT Id FROM #Importi);
            -- Importi di ALTRE aziende che citano una sede, un'etichetta, un tipo, un conto o
            -- un'aliquota della cascata (non previsto dalle regole): perdono solo il collegamento
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdSedePartenza = NULL WHERE IdSedePartenza IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEsecutore = NULL WHERE IdEsecutore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino di ALTRE aziende su un articolo della cascata (non previsto): perdono l'articolo
            DELETE FROM dbo.tblImportiRigheMagazzino WHERE IdArticolo IN (SELECT Id FROM #MagArticoli);
            UPDATE dbo.tblImportiRigheDettagli SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            UPDATE dbo.tblImportiRigheDettagli SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE CASCADE).
            -- Va fatta prima della Gestione EoW: le righe EoW di scarico referenziano tblEoWLotti.
            -- Relazioni carico/scarico in entrambi i versi (righe della sede, dei suoi movimenti o
            -- dei suoi lotti): FK NO_ACTION su Id e IdParent verso tblMagazziniMovimentiRighe.
            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
            INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
            WHERE r.IdSede IN (SELECT Id FROM #Sedi) OR r.IdMovimento IN (SELECT Id FROM #MagMovimenti) OR r.IdLotto IN (SELECT Id FROM #MagLotti);

            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
            INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
            WHERE
                re.IdSede IN (SELECT Id FROM #Sedi)
                OR re.IdMovimento IN (SELECT Id FROM #MagMovimenti)
                OR re.IdLotto IN (SELECT Id FROM #EoWLotti)
                OR rel.IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdSede IN (SELECT Id FROM #Sedi)
                OR IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi)
                OR IdMovimento IN (SELECT Id FROM #MagMovimenti);

            DELETE FROM dbo.tblMagazziniMovimentiRighe
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniMovimentiRigheEoW
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniMovimenti WHERE Id IN (SELECT Id FROM #MagMovimenti);
            DELETE FROM dbo.tblMagazziniLotti WHERE Id IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniArticoli WHERE Id IN (SELECT Id FROM #MagArticoli);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni sottostanti, per rispettare
            -- la FK di tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK
            -- composta con IdLotto - non azzerabile, la riga di collegamento va sempre rimossa,
            -- anche quando referenzia una Registrazione di questa sede legata a un Lotto di un'altra:
            -- stesso motivo dell'OR su #RifiutiRegistrazioni). I lotti/allocazioni EoW di questa sede
            -- vengono invece cancellati per intero (non azzerati) perché sono risorse di proprietà
            -- esclusiva della sede stessa, non condivise con altre sedi.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni
            WHERE IdLotto        IN (SELECT Id FROM #EoWLotti)
               OR IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWLottiAllocazioni
            WHERE IdLotto      IN (SELECT Id FROM #EoWLotti)
               OR IdAllocazione IN (SELECT Id FROM #EoWAllocazioni);
            DELETE FROM dbo.tblEoWLotti       WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWAllocazioni WHERE Id IN (SELECT Id FROM #EoWAllocazioni);

            -- tblEoWLotti.IdMagazzino (nullable, nessun vincolo strutturale che lo leghi allo stesso
            -- IdSede del Lotto) può referenziare un Magazzino di questa sede anche da un Lotto esterno
            -- alla cascata - i Lotti di questa sede sono già stati cancellati sopra, quindi qui restano
            -- solo eventuali riferimenti esterni: azzerati, non cancellati (stessa logica "UPDATE=NULL
            -- dove possibile" delle risorse condivise più sotto).
            DECLARE @eoWLottiScollegati INT;
            UPDATE dbo.tblEoWLotti SET IdMagazzino = NULL WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
            SET @eoWLottiScollegati = @@ROWCOUNT;
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            -- Dichiarazioni MUD: registri della dichiarazione (FK su tblRifiutiMud e su
            -- tblRifiutiRegistri), poi la dichiarazione
            DELETE FROM dbo.tblRifiutiMudRegistri
            WHERE Id IN (SELECT Id FROM #RifiutiMud) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiMud WHERE Id IN (SELECT Id FROM #RifiutiMud);

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Anagrafica estesa e Fatturazione: prima le schede, che referenziano banche/casse e
            -- aliquote; le schede di ALTRE aziende che usano un'aliquota o una banca di questa
            -- (non previsto dalle regole) perdono solo il collegamento
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);
            UPDATE dbo.tblClientiFornitori SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            UPDATE dbo.tblClientiFornitori SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            -- Conti: le righe di ALTRE aziende che li usano (non previsto dalle regole) perdono solo il
            -- collegamento, come per banche/casse e aliquote
            UPDATE dbo.tblFattureRigheImporti SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureConti WHERE Id IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureDatiFiscali WHERE Id IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblFattureRigheImporti SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            UPDATE dbo.tblFatture SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblFattureRatePagamenti
            WHERE IdPagamento IN (SELECT Id FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi));
            DELETE FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi);            DELETE FROM dbo.tblBancheCasse WHERE Id IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblAliquoteIva WHERE Id IN (SELECT Id FROM #AliquoteIva);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #MagArticoli
                UNION SELECT Id FROM #MagLotti
                UNION SELECT Id FROM #MagMovimenti
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #FattureConti
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #Importi
                UNION SELECT Id FROM #ImportiRighe
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #BancheCasse
                UNION SELECT Id FROM #AliquoteIva
                UNION SELECT Id FROM #RifiutiMud
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWAllocazioni
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Allocazioni EoW rimosse: ', (SELECT COUNT(*) FROM #EoWAllocazioni), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ' (Lotti esterni scollegati: ', @eoWLottiScollegati, ')', ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;
