/*
Deploy produzione 2026-10-07 - Fatturazione > Fatture clienti e fornitori

Da eseguire DOPO deploy_produzione_2026-10-07_anagrafica_amministratori.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I (QUOTED_IDENTIFIER ON: tblClientiFornitori ha un indice filtrato).

1. Struttura: tblFattureTipi con i codici della fattura elettronica (TD00...TD24; tblFattureTipiDocumenti
   viene eliminata, nessuna tabella la usava), tblFattureConti, tblFatture, tblFattureRighe,
   tblFattureRigheImporti, tblPagamenti, tblFattureRate, tblFattureRatePagamenti con FK e indici.
   Funzione FTT "Fatture" nel modulo FAT; pagine e menu Fatture clienti, Fatture fornitori, Conti
   (Banche e casse e Aliquote IVA scendono in fondo al menu Fatturazione). Tutto creato solo se manca.
2. ufnFatture_get_Totali: totali della fattura calcolati dalle righe.
3. uspFattureConti_*: conti dell'azienda (funzione FTC).
4. uspFatture_*: testata, numerazione per anno e sezionale, elenco, cancellazione e ripristino,
   condizioni della scheda del cliente o fornitore, fattura di riferimento della nota di credito.
5. uspFattureRighe_*: righe (anche di sola descrizione) e loro posizione.
6. uspFattureRate_*: rate, generate dalle condizioni di pagamento o inserite a mano.
7. SP esistenti: uspClientiFornitori_del, uspBancheCasse_del, uspAliquoteIva_del (blocchi per le
   fatture), uspBancheCasse_get_SelectList, uspAliquoteIva_get_SelectList (leggibili con FTT),
   uspSedi_del_SediInterne (azienda con fatture o conti), uspSYS_del_SedeInternaCascade,
   uspSYS_del_SedeEsternaCascade (SP di sviluppo).

Va deployato insieme all'app: le pagine Fatturazione > Fatture clienti, Fatture fornitori e Conti usano
le nuove SP.

Dopo il deploy: la funzione FTT va assegnata agli utenti in Impostazioni > Utenti (gli amministratori
del dominio l'hanno gia'); eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'Tabelle, funzione FTT, pagine e menu';
GO
-- Fatturazione > Fatture clienti e fornitori: tabelle (fatture, righe, importi, conti, rate, pagamenti),
-- tipi di documento, funzione FTT, pagine e voci di menu.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già tabelle e registrazione.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Tipi di documento: tblFattureTipi passa dal codice interno (F, N, P) al codice della fattura
-- elettronica (TD01...), che prima stava in tblFattureTipiDocumenti. Nessuna tabella le usava ancora.
IF OBJECT_ID('dbo.tblFattureTipiDocumenti') IS NOT NULL
	DROP TABLE dbo.tblFattureTipiDocumenti;

IF OBJECT_ID('dbo.tblFattureTipi') IS NOT NULL AND COL_LENGTH('dbo.tblFattureTipi', 'Id') = 1
	DROP TABLE dbo.tblFattureTipi;
GO
IF OBJECT_ID('dbo.tblFattureTipi') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureTipi (
		Id CHAR(4) NOT NULL,
		Nome VARCHAR(50) NULL,
		CONSTRAINT PK_tblFattureTipi PRIMARY KEY CLUSTERED (Id)
	);
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD00') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD00', 'Pre-fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD01') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD01', 'Fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD02') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD02', 'Fattura acconto/anticipo');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD04') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD04', 'Nota accredito');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD17') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD17', 'Autofattura per acquisto di servizi');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD18') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD18', 'Autofattura per acquisto beni');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD19') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD19', 'Autofattura per acquisto beni art. 17');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD24') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD24', 'Fattura differita');
GO
-- Conti dell'azienda interna (IdSede = azienda), per classificare gli importi delle righe
IF OBJECT_ID('dbo.tblFattureConti') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureConti (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NULL,
		Nome VARCHAR(50) NULL,
		Codice VARCHAR(10) NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblFattureConti PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureConti WITH CHECK ADD CONSTRAINT FK_tblFattureConti_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
END
GO
-- Fattura: IdSede = azienda interna che la emette (Tipo C, cliente) o la riceve (Tipo F, fornitore);
-- IdClienteFornitore = scheda del cliente o del fornitore. Lock 0 attiva, 2 bozza, 4 cancellata.
-- IdFatturaRiferimento = fattura stornata da una nota di credito; Causale = causale del documento.
IF OBJECT_ID('dbo.tblFatture') IS NULL
BEGIN
	CREATE TABLE dbo.tblFatture (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NULL,
		IdClienteFornitore CHAR(16) NULL,
		IdTipo CHAR(4) NULL,
		IdStato CHAR(1) NULL,
		IdModalita CHAR(4) NULL,
		IdRata CHAR(3) NULL,
		IdRataInizio CHAR(2) NULL,
		IdValuta CHAR(3) NULL,
		IdBancaCassa CHAR(16) NULL,
		IdFatturaRiferimento CHAR(16) NULL,
		Tipo CHAR(1) NULL,
		Numero INT NULL,
		Sezionale CHAR(1) NULL,
		NumeroFornitore VARCHAR(30) NULL,
		DataRegistrazione DATE NULL,
		DataEmissione DATE NULL,
		Causale VARCHAR(200) NULL,
		Iban VARCHAR(34) NULL,
		RataGiorniInizio INT NULL,
		Ordine VARCHAR(30) NULL,
		DataOrdine DATE NULL,
		SplitPayment BIT NULL,
		Bollo DECIMAL(9, 2) NULL,
		CodiceCig VARCHAR(10) NULL,
		CodiceCup VARCHAR(15) NULL,
		SolaLettura BIT NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblFatture PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblClientiFornitori FOREIGN KEY (IdClienteFornitore) REFERENCES dbo.tblClientiFornitori (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFattureTipi FOREIGN KEY (IdTipo) REFERENCES dbo.tblFattureTipi (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFattureStati FOREIGN KEY (IdStato) REFERENCES dbo.tblFattureStati (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiModalita FOREIGN KEY (IdModalita) REFERENCES dbo.tblPagamentiModalita (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiRate FOREIGN KEY (IdRata) REFERENCES dbo.tblPagamentiRate (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiRateInizi FOREIGN KEY (IdRataInizio) REFERENCES dbo.tblPagamentiRateInizi (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiValute FOREIGN KEY (IdValuta) REFERENCES dbo.tblPagamentiValute (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblBancheCasse FOREIGN KEY (IdBancaCassa) REFERENCES dbo.tblBancheCasse (Id);
END
GO
-- Il tipo di documento può essere rimasto senza FK se tblFattureTipi è stata ricreata più sopra
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblFatture_tblFattureTipi')
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFattureTipi FOREIGN KEY (IdTipo) REFERENCES dbo.tblFattureTipi (Id);
GO
-- Riga della fattura: descrizione e posizione. Una riga senza importi è di sola descrizione.
-- Righe e rate non hanno un Lock proprio: seguono la fattura
IF OBJECT_ID('dbo.tblFattureRighe') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRighe (
		Id CHAR(16) NOT NULL,
		IdFattura CHAR(16) NULL,
		Descrizione VARCHAR(1000) NULL,
		Pos INT NULL,
		CONSTRAINT PK_tblFattureRighe PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureRighe WITH CHECK ADD CONSTRAINT FK_tblFattureRighe_tblFatture FOREIGN KEY (IdFattura) REFERENCES dbo.tblFatture (Id);
END
GO
-- Importi della riga (Id = riga): Importo è il prezzo unitario, il totale della riga è Quantita x Importo
IF OBJECT_ID('dbo.tblFattureRigheImporti') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRigheImporti (
		Id CHAR(16) NOT NULL,
		IdAliquotaIva CHAR(16) NULL,
		IdConto CHAR(16) NULL,
		IdUnitaMisura CHAR(2) NULL,
		Quantita DECIMAL(18, 4) NULL,
		Importo DECIMAL(18, 4) NULL,
		RitenutaAcconto INT NULL,
		CONSTRAINT PK_tblFattureRigheImporti PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblFattureRighe FOREIGN KEY (Id) REFERENCES dbo.tblFattureRighe (Id);
	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblAliquoteIva FOREIGN KEY (IdAliquotaIva) REFERENCES dbo.tblAliquoteIva (Id);
	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblFattureConti FOREIGN KEY (IdConto) REFERENCES dbo.tblFattureConti (Id);
	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblUnitaMisura FOREIGN KEY (IdUnitaMisura) REFERENCES dbo.tblUnitaMisura (Id);
END
GO
-- Pagamento dell'azienda interna IdSede: Tipo E entrata (incasso da un cliente), U uscita (pagamento a
-- un fornitore). Può saldare una o più rate: quanto va a ciascuna è in tblFattureRatePagamenti.Importo
IF OBJECT_ID('dbo.tblPagamenti') IS NULL
BEGIN
	CREATE TABLE dbo.tblPagamenti (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NULL,
		IdBancaCassa CHAR(16) NULL,
		IdModalita CHAR(4) NULL,
		Tipo CHAR(1) NULL,
		Causale VARCHAR(100) NULL,
		DataRegistrazione DATE NULL,
		DataContabile DATE NULL,
		Importo DECIMAL(18, 2) NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblPagamenti PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblBancheCasse FOREIGN KEY (IdBancaCassa) REFERENCES dbo.tblBancheCasse (Id);
	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblPagamentiModalita FOREIGN KEY (IdModalita) REFERENCES dbo.tblPagamentiModalita (Id);
END
GO
-- Rata (scadenza) della fattura
IF OBJECT_ID('dbo.tblFattureRate') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRate (
		Id CHAR(16) NOT NULL,
		IdFattura CHAR(16) NULL,
		Importo DECIMAL(18, 2) NULL,
		Abbuono DECIMAL(18, 2) NULL,
		DataScadenza DATE NULL,
		CONSTRAINT PK_tblFattureRate PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureRate WITH CHECK ADD CONSTRAINT FK_tblFattureRate_tblFatture FOREIGN KEY (IdFattura) REFERENCES dbo.tblFatture (Id);
END
GO
IF OBJECT_ID('dbo.tblFattureRatePagamenti') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRatePagamenti (
		IdRata CHAR(16) NOT NULL,
		IdPagamento CHAR(16) NOT NULL,
		Importo DECIMAL(18, 2) NULL,
		CONSTRAINT PK_tblFattureRatePagamenti PRIMARY KEY CLUSTERED (IdRata, IdPagamento)
	);

	ALTER TABLE dbo.tblFattureRatePagamenti WITH CHECK ADD CONSTRAINT FK_tblFattureRatePagamenti_tblFattureRate FOREIGN KEY (IdRata) REFERENCES dbo.tblFattureRate (Id);
	ALTER TABLE dbo.tblFattureRatePagamenti WITH CHECK ADD CONSTRAINT FK_tblFattureRatePagamenti_tblPagamenti FOREIGN KEY (IdPagamento) REFERENCES dbo.tblPagamenti (Id);
END
GO
-- Allineamento delle tabelle create con una versione precedente di questo script (sviluppo): colonne
-- aggiunte, importi a DECIMAL(18, 2), Lock tolto da righe e rate
IF COL_LENGTH('dbo.tblFatture', 'IdFatturaRiferimento') IS NULL
	ALTER TABLE dbo.tblFatture ADD IdFatturaRiferimento CHAR(16) NULL;
IF COL_LENGTH('dbo.tblFatture', 'Causale') IS NULL
	ALTER TABLE dbo.tblFatture ADD Causale VARCHAR(200) NULL;
IF COL_LENGTH('dbo.tblFatture', 'Note') IS NOT NULL
	ALTER TABLE dbo.tblFatture DROP COLUMN Note;
IF COL_LENGTH('dbo.tblFattureRighe', 'Lock') IS NOT NULL
	ALTER TABLE dbo.tblFattureRighe DROP COLUMN Lock;
IF COL_LENGTH('dbo.tblFattureRate', 'Lock') IS NOT NULL
	ALTER TABLE dbo.tblFattureRate DROP COLUMN Lock;
IF COL_LENGTH('dbo.tblFattureRate', 'Note') IS NOT NULL
	ALTER TABLE dbo.tblFattureRate DROP COLUMN Note;
IF COL_LENGTH('dbo.tblPagamenti', 'IdSede') IS NULL
	ALTER TABLE dbo.tblPagamenti ADD IdSede CHAR(16) NULL;
IF COL_LENGTH('dbo.tblPagamenti', 'Tipo') IS NULL
	ALTER TABLE dbo.tblPagamenti ADD Tipo CHAR(1) NULL;
IF COL_LENGTH('dbo.tblFattureRatePagamenti', 'Importo') IS NULL
	ALTER TABLE dbo.tblFattureRatePagamenti ADD Importo DECIMAL(18, 2) NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblFattureRate') AND name IN ('Importo', 'Abbuono') AND precision <> 18)
BEGIN
	ALTER TABLE dbo.tblFattureRate ALTER COLUMN Importo DECIMAL(18, 2) NULL;
	ALTER TABLE dbo.tblFattureRate ALTER COLUMN Abbuono DECIMAL(18, 2) NULL;
END
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblPagamenti') AND name = 'Importo' AND precision <> 18)
	ALTER TABLE dbo.tblPagamenti ALTER COLUMN Importo DECIMAL(18, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblFatture_tblFatture')
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFatture FOREIGN KEY (IdFatturaRiferimento) REFERENCES dbo.tblFatture (Id);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblPagamenti_tblSedi')
	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
GO
-- Indici di ricerca: elenco delle fatture per azienda, tipo e data; fatture di un cliente o fornitore;
-- righe e rate di una fattura
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFatture_IdSede_Tipo_DataEmissione' AND object_id = OBJECT_ID('dbo.tblFatture'))
	CREATE NONCLUSTERED INDEX IX_tblFatture_IdSede_Tipo_DataEmissione ON dbo.tblFatture (IdSede, Tipo, DataEmissione);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFatture_IdClienteFornitore' AND object_id = OBJECT_ID('dbo.tblFatture'))
	CREATE NONCLUSTERED INDEX IX_tblFatture_IdClienteFornitore ON dbo.tblFatture (IdClienteFornitore);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFattureRighe_IdFattura' AND object_id = OBJECT_ID('dbo.tblFattureRighe'))
	CREATE NONCLUSTERED INDEX IX_tblFattureRighe_IdFattura ON dbo.tblFattureRighe (IdFattura);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFattureRate_IdFattura' AND object_id = OBJECT_ID('dbo.tblFattureRate'))
	CREATE NONCLUSTERED INDEX IX_tblFattureRate_IdFattura ON dbo.tblFattureRate (IdFattura);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFattureConti_IdSede' AND object_id = OBJECT_ID('dbo.tblFattureConti'))
	CREATE NONCLUSTERED INDEX IX_tblFattureConti_IdSede ON dbo.tblFattureConti (IdSede);
GO
-- Funzione FTT "Fatture" nel modulo Fatturazione (FAT): un solo permesso per fatture clienti e fornitori.
-- I conti sono configurazione (funzione FTC, come banche e casse e aliquote IVA)
IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'FTT')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('FTT', 'Fatture', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'FAT' AND IdFunzione = 'FTT')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('FAT', 'FTT');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTE')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTE', 'FTT', 'Fatture clienti', 'fatture-clienti', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTF')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTF', 'FTT', 'Fatture fornitori', 'fatture-fornitori', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTK')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTK', 'FTC', 'Conti', 'conti', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Conti, Banche e casse, Aliquote IVA
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ3')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ3', 'AJ0', NULL, 'FTE', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ4')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ4', 'AJ0', NULL, 'FTF', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ5', 'AJ0', NULL, 'FTK', 2);

UPDATE dbo.tblMenu SET Pos = 3 WHERE Id = 'AJ1' AND Pos <> 3;
UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AJ2' AND Pos <> 4;
GO

PRINT 'ufnFatture_get_Totali';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Totali di una fattura, calcolati dalle righe e mai memorizzati. Importo della riga = prezzo unitario:
-- imponibile della riga = Quantita x Importo, arrotondato al centesimo. L'IVA si calcola sull'imponibile
-- complessivo di ciascuna aliquota (come nel riepilogo della fattura elettronica), la ritenuta d'acconto allo
-- stesso modo sull'imponibile complessivo di ciascuna percentuale: l'arrotondamento al centesimo si fa una
-- volta sola, non riga per riga. Totale = imponibile + IVA + bollo. Netto a pagare = totale - ritenuta e, con lo split
-- payment, - IVA (la versa il cliente all'erario).
CREATE OR ALTER FUNCTION dbo.ufnFatture_get_Totali (@IdFattura CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH righe AS (
		SELECT
			i.IdAliquotaIva,
			Imponibile = CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2)),
			RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0)
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
		WHERE r.IdFattura = @IdFattura),
	aliquote AS (
		SELECT
			Imponibile = SUM(g.Imponibile),
			Iva = CAST(ROUND(SUM(g.Imponibile) * ISNULL(MAX(a.Valore), 0) / 100, 2) AS DECIMAL(18, 2))
		FROM
			righe g
			LEFT JOIN dbo.tblAliquoteIva a ON g.IdAliquotaIva = a.Id
		GROUP BY g.IdAliquotaIva
	),
	totali AS (
		SELECT
			Imponibile = ISNULL((SELECT SUM(Imponibile) FROM aliquote), 0),
			Iva = ISNULL((SELECT SUM(Iva) FROM aliquote), 0),
			Ritenuta = ISNULL((SELECT SUM(x.Ritenuta) FROM (SELECT Ritenuta = CAST(ROUND(SUM(Imponibile) * RitenutaAcconto / 100.0, 2) AS DECIMAL(18, 2)) FROM righe GROUP BY RitenutaAcconto) x), 0)
	)
	SELECT
		Imponibile = CAST(t.Imponibile AS DECIMAL(18, 2)),
		Iva = CAST(t.Iva AS DECIMAL(18, 2)),
		Ritenuta = CAST(t.Ritenuta AS DECIMAL(18, 2)),
		Bollo = CAST(ISNULL(f.Bollo, 0) AS DECIMAL(18, 2)),
		Totale = CAST(t.Imponibile + t.Iva + ISNULL(f.Bollo, 0) AS DECIMAL(18, 2)),
		NettoAPagare = CAST(t.Imponibile + t.Iva + ISNULL(f.Bollo, 0) - t.Ritenuta - IIF(ISNULL(f.SplitPayment, 0) = 1, t.Iva, 0) AS DECIMAL(18, 2))
	FROM
		dbo.tblFatture f
		CROSS JOIN totali t
	WHERE f.Id = @IdFattura);
GO

PRINT 'uspFatture_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_del
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFatture WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità): scope azienda interna corrente della sessione
		DECLARE @lock INT;
		DECLARE @solaLettura BIT;
		SELECT
			@lock = f.Lock,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione;

		IF @lock IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: fattura attiva (Lock = 0) → soft delete ──────────────────
		-- Righe e rate restano sulla fattura cancellata, per il ripristino
		IF @lock = 0
		BEGIN
			IF @solaLettura = 1
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una fattura in sola lettura non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdFatturaRiferimento = @Id AND Lock IN (0, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una fattura a cui si riferisce una nota di credito non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRate r
					INNER JOIN dbo.tblFattureRatePagamenti p ON r.Id = p.IdRata
				WHERE r.IdFattura = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una fattura con rate già pagate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblFatture
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Fattura non trovata o già eliminata';
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

		-- ── CASO 2: fattura in bozza (Lock = 2) → hard delete con righe e rate ─
		ELSE IF @lock = 2
		BEGIN
			DECLARE @figli TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

			BEGIN TRANSACTION;
				INSERT @figli (Id)
				SELECT Id
				FROM dbo.tblFattureRighe
				WHERE IdFattura = @Id
				UNION
				SELECT Id
				FROM dbo.tblFattureRate
				WHERE IdFattura = @Id;

				DELETE i
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
				WHERE r.IdFattura = @Id;
				DELETE dbo.tblFattureRighe
				WHERE IdFattura = @Id;
				DELETE p
				FROM
					dbo.tblFattureRatePagamenti p
					INNER JOIN dbo.tblFattureRate r ON p.IdRata = r.Id
				WHERE r.IdFattura = @Id;
				DELETE dbo.tblFattureRate
				WHERE IdFattura = @Id;
				DELETE dbo.tblFatture
				WHERE Id = @Id;

				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR Id IN (SELECT Id FROM @figli);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR Id IN (SELECT Id FROM @figli);
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

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

PRINT 'uspFatture_del_Undo';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Dopo la cancellazione il numero può essere stato riassegnato a un'altra fattura dello stesso
		-- anno e sezionale: il ripristino creerebbe due fatture con lo stesso numero
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblFatture i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblFatture a ON i.IdSede = a.IdSede
										   AND i.Tipo = a.Tipo
										   AND i.Numero = a.Numero
										   AND ISNULL(i.Sezionale, '') = ISNULL(a.Sezionale, '')
										   AND YEAR(IIF(i.Tipo = 'C', i.DataEmissione, i.DataRegistrazione)) = YEAR(IIF(a.Tipo = 'C', a.DataEmissione, a.DataRegistrazione))
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: il numero della fattura è già stato assegnato a un''altra fattura';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblFatture i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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

PRINT 'uspFatture_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_get
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFatture f
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			WHERE
				f.Id = @Id
				AND e.Id = @IdSessione
				AND f.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END

		-- I totali si calcolano dalle righe (ufnFatture_get_Totali), non sono memorizzati
		SELECT
			f.Id,
			f.IdSede,
			f.IdClienteFornitore,
			f.IdTipo,
			f.IdStato,
			f.IdModalita,
			f.IdRata,
			f.IdRataInizio,
			f.IdValuta,
			f.IdBancaCassa,
			f.IdFatturaRiferimento,
			f.Tipo,
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataRegistrazione,
			f.DataEmissione,
			f.Iban,
			RataGiorniInizio = ISNULL(f.RataGiorniInizio, 0),
			f.Ordine,
			f.DataOrdine,
			SplitPayment = ISNULL(f.SplitPayment, 0),
			Bollo = ISNULL(f.Bollo, 0),
			f.CodiceCig,
			f.CodiceCup,
			f.Causale,
			SolaLettura = ISNULL(f.SolaLettura, 0),
			f.Lock,
			NomeCompleto = s.NomeCompleto,
			t.Imponibile,
			t.Iva,
			t.Ritenuta,
			t.Totale,
			t.NettoAPagare
		FROM
			dbo.tblFatture f
			LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
		WHERE f.Id = @Id;

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

PRINT 'uspFatture_get_ClientiFornitori_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Clienti (@Tipo = C) o fornitori (@Tipo = F) dell'azienda del contesto per la select della fattura:
-- Id è la scheda del cliente o del fornitore, non il soggetto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_ClientiFornitori_SelectList
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
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
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- scheda selezionata: sempre presente, anche se cancellata, disabilitata o fuori da @Search

			SELECT
				c.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblClientiFornitori c
				INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND c.Id = @IdSelected
				AND c.Tipo = @Tipo

			UNION ALL -- altre schede attive dell'azienda, filtrabili per @Search

			SELECT
				c.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblClientiFornitori c
				INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND c.Tipo = @Tipo
				AND c.Lock = 0
				AND ISNULL(s.Disabilitata, 0) = 0
				AND c.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
					OR s.PartitaIva LIKE '%' + @Search + '%'
					OR s.CodiceFiscale LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 50 Id, [Text], Selected
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

PRINT 'uspFatture_get_Condizioni';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Condizioni commerciali della scheda di un cliente o fornitore, da proporre sulla fattura quando lo
-- si sceglie: pagamento, banca, IBAN, split payment, e aliquota IVA e ritenuta per le righe.
-- Si legge con il permesso sulle fatture (FTT), senza quello sulle anagrafiche (ANC / ANF).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Condizioni
	@IdClienteFornitore CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: schede dell'azienda interna corrente della sessione; nessuna riga se la scheda non c'è
		SELECT
			c.Id,
			c.IdModalita,
			c.IdRata,
			c.IdRataInizio,
			c.IdBancaCassa,
			c.IdAliquotaIva,
			c.IdValuta,
			SplitPayment = ISNULL(c.SplitPayment, 0),
			c.Iban,
			RataGiorniInizio = ISNULL(c.RataGiorniInizio, 0),
			RitenutaAcconto = ISNULL(c.RitenutaAcconto, 0)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @IdClienteFornitore
			AND e.Id = @IdSessione
			AND c.Lock = 0;

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

PRINT 'uspFatture_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdStato CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');
		SET @IdTipo = NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4));
		SET @IdStato = NULLIF(NULLIF(LTRIM(RTRIM(@IdStato)), ''), '0');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga.
		-- @Numero cerca nel numero della fattura e, per i fornitori, nel numero del loro documento.
		-- Stato della riga: avviso se la fattura non ha righe con importi o se ha rate la cui somma è diversa
		-- dal netto a pagare (una fattura senza rate non è segnalata)
		SELECT
			f.Id,
			StatoValore = CASE WHEN t.Totale = 0 OR (z.Numero > 0 AND z.Importo <> t.NettoAPagare) THEN 1 ELSE 0 END,
			StatoDescrizione =
				CASE
					WHEN t.Totale = 0 THEN 'Fattura senza importi'
					WHEN z.Numero > 0 AND z.Importo <> t.NettoAPagare THEN 'Le rate non corrispondono al netto a pagare'
					ELSE 'OK'
				END,
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataEmissione,
			f.DataRegistrazione,
			f.IdTipo,
			TipoNome = p.Nome,
			f.IdStato,
			StatoNome = a.Nome,
			s.NomeCompleto,
			t.Imponibile,
			t.Iva,
			t.Totale,
			t.NettoAPagare,
			SolaLettura = ISNULL(f.SolaLettura, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
			LEFT JOIN dbo.tblFattureStati a ON f.IdStato = a.Id
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
			OUTER APPLY (SELECT Numero = COUNT(*), Importo = ISNULL(SUM(q.Importo), 0) FROM dbo.tblFattureRate q WHERE q.IdFattura = f.Id) z
		WHERE
			e.Id = @IdSessione
			AND f.Tipo = @Tipo
			AND f.Lock = 0
			AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND
				(
				@Numero IS NULL
				OR CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '') LIKE @Numero + '%'
				OR f.NumeroFornitore LIKE '%' + @Numero + '%'
				)
			AND (@DataDa IS NULL OR f.DataEmissione >= @DataDa)
			AND (@DataA IS NULL OR f.DataEmissione <= @DataA)
			AND (@IdTipo IS NULL OR f.IdTipo = @IdTipo)
			AND (@IdStato IS NULL OR f.IdStato = @IdStato)
		ORDER BY
			f.DataEmissione DESC,
			f.Numero DESC,
			f.Id
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

PRINT 'uspFatture_get_ProssimoNumero';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Numero che la fattura riceverebbe al salvataggio con il tipo di documento, il sezionale e le date
-- scelti nella scheda (anche se non ancora salvati). È solo un suggerimento: il numero definitivo lo
-- assegna uspFatture_upd, con la stessa regola. 0 = nessun numero (pre-fattura).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_ProssimoNumero
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(4) = NULL,
	@Sezionale CHAR(1) = NULL,
	@DataEmissione DATE = NULL,
	@DataRegistrazione DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4)));
		SET @Sezionale = NULLIF(UPPER(LTRIM(RTRIM(@Sezionale))), '');

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @tipo CHAR(1);
		SELECT
			@idAzienda = f.IdSede,
			@tipo = f.Tipo
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END

		-- Stessa regola di uspFatture_upd: progressivo per azienda, tipo (clienti / fornitori), anno e
		-- sezionale tra le fatture attive. L'anno è quello della data di emissione per le fatture cliente,
		-- della data di registrazione per le fatture fornitore; senza data vale oggi
		DECLARE @dataNumero DATE = ISNULL(IIF(@tipo = 'C', @DataEmissione, @DataRegistrazione), CAST(GETDATE() AS DATE));
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@dataNumero), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @numero INT = 0;

		-- La pre-fattura non ha numero
		IF ISNULL(@IdTipo, '') <> 'TD00'
		BEGIN
			SELECT @numero = ISNULL(MAX(Numero), 0) + 1
			FROM dbo.tblFatture
			WHERE
				IdSede = @idAzienda
				AND Tipo = @tipo
				AND Lock = 0
				AND Id <> @Id
				AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
				AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) >= @annoInizio
				AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) < @annoFine;
		END

		SELECT Numero = @numero;

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

PRINT 'uspFatture_get_Riferimenti_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture a cui può riferirsi una nota di credito: quelle attive e numerate (non pre-fatture né altre
-- note di credito) dello stesso cliente o fornitore, dalla più recente. @IdFattura è la nota di credito
-- in modifica, esclusa dall'elenco.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Riferimenti_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), @idSediciZeri);
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: fatture dell'azienda interna corrente della sessione
		SELECT TOP 200 Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0,
				DataEmissione = CAST(NULL AS DATE),
				Numero = CAST(NULL AS INT)

			UNION ALL

			SELECT
				f.Id,
				[Text] = CAST('n. ' + ISNULL(f.NumeroFornitore, CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '')) + ' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103) + ' - ' + FORMAT(t.Totale, 'N2', 'it-IT') AS VARCHAR(200)),
				Selected = CAST(IIF(f.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				f.DataEmissione,
				f.Numero
			FROM
				dbo.tblFatture f
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
			WHERE
				e.Id = @IdSessione
				AND f.IdClienteFornitore = @IdClienteFornitore
				AND f.Id <> ISNULL(@IdFattura, @idSediciZeri)
				AND f.IdTipo NOT IN ('TD00', 'TD04')
				AND f.Lock = 0
		) x
		ORDER BY
			Pos,
			DataEmissione DESC,
			Numero DESC;

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

PRINT 'uspFatture_get_Stati_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stati della fattura (G Generata, S Spedita). Con @Tutti = 1 (filtro dell'elenco) c'è la prima voce "(Tutti)".
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Stati_SelectList
	@IdSelected CHAR(1) = NULL,
	@Tutti BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Tutti = ISNULL(@Tutti, 0);

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0' AS CHAR(1)),
				[Text] = CAST('(Tutti)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0', 1, 0) AS BIT),
				Pos = 0
			WHERE @Tutti = 1

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblFattureStati
		) t
		ORDER BY Pos, Id;

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

PRINT 'uspFatture_get_Tipi_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Tipi di documento per la fattura: le autofatture (TD17, TD18, TD19) solo tra le fatture fornitori
-- (@Tipo = F), la pre-fattura (TD00) solo tra le fatture clienti (@Tipo = C). Con @Tutti = 1 (filtro
-- dell'elenco) c'è la prima voce "(Tutti)".
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Tipi_SelectList
	@Tipo CHAR(1) = NULL,
	@IdSelected CHAR(4) = NULL,
	@Tutti BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Tutti = ISNULL(@Tutti, 0);

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0000' AS CHAR(4)),
				[Text] = CAST('(Tutti)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0000', 1, 0) AS BIT),
				Pos = 0
			WHERE @Tutti = 1

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblFattureTipi
			WHERE
				(@Tipo = 'F' OR Id NOT IN ('TD17', 'TD18', 'TD19'))
				AND (@Tipo = 'C' OR Id <> 'TD00')
		) t
		ORDER BY Pos, Id;

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

PRINT 'uspFatture_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_ins
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La fattura appartiene all'azienda interna corrente della sessione
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

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza: il cliente o il fornitore si sceglie nella scheda e porta con sé le condizioni di pagamento.
		-- Valori predefiniti: fattura (TD01), stato Generata, valuta euro, rate dalla data fattura (DF),
		-- data di registrazione di oggi; per una fattura cliente anche la data di emissione
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);
		BEGIN TRANSACTION;
			INSERT dbo.tblFatture (Id, IdSede, Tipo, IdTipo, IdStato, IdValuta, IdRataInizio, DataRegistrazione, DataEmissione, RataGiorniInizio, SplitPayment, Bollo, SolaLettura, Lock)
			VALUES (@returnId, @idAzienda, @Tipo, 'TD01', 'G', 'EUR', 'DF', @oggi, IIF(@Tipo = 'C', @oggi, NULL), 0, 0, 0, 0, 2);
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

PRINT 'uspFatture_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva la testata della fattura. Con @Conferma = 1 (Salva) la bozza diventa attiva e, se manca,
-- riceve il numero; con @Conferma = 0 la testata viene salvata lasciando la fattura nello stato in cui
-- è (serve prima di generare le rate, che si calcolano sui dati salvati).
CREATE OR ALTER PROCEDURE dbo.uspFatture_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdStato CHAR(1) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdRata CHAR(3) = NULL,
	@IdRataInizio CHAR(2) = NULL,
	@IdValuta CHAR(3) = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdFatturaRiferimento CHAR(16) = NULL,
	@Numero INT = NULL,
	@Sezionale VARCHAR(5) = NULL,
	@NumeroFornitore VARCHAR(50) = NULL,
	@DataRegistrazione DATE = NULL,
	@DataEmissione DATE = NULL,
	@Iban VARCHAR(50) = NULL,
	@RataGiorniInizio INT = NULL,
	@Ordine VARCHAR(50) = NULL,
	@DataOrdine DATE = NULL,
	@SplitPayment BIT = 0,
	@Bollo DECIMAL(9, 2) = NULL,
	@CodiceCig VARCHAR(20) = NULL,
	@CodiceCup VARCHAR(20) = NULL,
	@Causale VARCHAR(250) = NULL,
	@SolaLettura BIT = 0,
	@Conferma BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @IdTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4)));
		SET @IdStato = ISNULL(UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdStato)), ''), '0')), 'G');
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @IdRata = NULLIF(NULLIF(LTRIM(RTRIM(@IdRata)), ''), REPLICATE('0', 3));
		SET @IdRataInizio = NULLIF(NULLIF(LTRIM(RTRIM(@IdRataInizio)), ''), REPLICATE('0', 2));
		SET @IdValuta = NULLIF(NULLIF(LTRIM(RTRIM(@IdValuta)), ''), REPLICATE('0', 3));
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdFatturaRiferimento = NULLIF(NULLIF(LTRIM(RTRIM(@IdFatturaRiferimento)), ''), REPLICATE('0', 16));
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @Numero = NULLIF(@Numero, 0);
		SET @Sezionale = NULLIF(UPPER(LTRIM(RTRIM(@Sezionale))), '');
		SET @NumeroFornitore = NULLIF(LTRIM(RTRIM(@NumeroFornitore)), '');
		-- IBAN, CIG e CUP: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceCig = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCig)), ' ', '')), '');
		SET @CodiceCup = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCup)), ' ', '')), '');
		SET @Ordine = NULLIF(LTRIM(RTRIM(@Ordine)), '');
		SET @RataGiorniInizio = ISNULL(@RataGiorniInizio, 0);
		SET @SplitPayment = ISNULL(@SplitPayment, 0);
		SET @Bollo = ISNULL(@Bollo, 0);
		SET @SolaLettura = ISNULL(@SolaLettura, 0);
		SET @Conferma = ISNULL(@Conferma, 1);

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @tipo CHAR(1);
		DECLARE @lock INT;
		DECLARE @solaLetturaAttuale BIT;
		DECLARE @idClienteFornitoreAttuale CHAR(16);
		SELECT
			@idAzienda = f.IdSede,
			@tipo = f.Tipo,
			@lock = f.Lock,
			@solaLetturaAttuale = ISNULL(f.SolaLettura, 0),
			@idClienteFornitoreAttuale = f.IdClienteFornitore
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END

		-- Sola lettura: protezione dalle modifiche involontarie. Per modificare la fattura va prima tolta la spunta
		IF @solaLetturaAttuale = 1 AND @SolaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura';
			GOTO BRANCH_END;
		END

		-- Cliente o fornitore: scheda attiva dell'azienda e del tipo della fattura. La scheda già sulla
		-- fattura resta valida anche se nel frattempo è stata cancellata
		IF @IdClienteFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Selezionare il cliente', 'Selezionare il fornitore');
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = @tipo
				AND (Lock = 0 OR Id = @idClienteFornitoreAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Il cliente indicato non esiste', 'Il fornitore indicato non esiste');
			GOTO BRANCH_END;
		END

		-- Tipo di documento: le autofatture (TD17, TD18, TD19) si registrano tra le fatture fornitori,
		-- la pre-fattura (TD00) si emette solo per un cliente
		IF @IdTipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = @IdTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo di documento';
			GOTO BRANCH_END;
		END
		IF @tipo = 'C' AND @IdTipo IN ('TD17', 'TD18', 'TD19')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''autofattura si registra tra le fatture fornitori';
			GOTO BRANCH_END;
		END
		IF @tipo = 'F' AND @IdTipo = 'TD00'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La pre-fattura si emette solo per un cliente';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureStati WHERE Id = @IdStato)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lo stato indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Fattura di riferimento: solo per la nota di credito (TD04), facoltativa. È la fattura stornata:
		-- attiva, numerata (non una pre-fattura né un'altra nota di credito) e dello stesso cliente o fornitore
		IF @IdTipo <> 'TD04'
			SET @IdFatturaRiferimento = NULL;
		IF @IdFatturaRiferimento IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblFatture
			WHERE
				Id = @IdFatturaRiferimento
				AND Id <> @Id
				AND IdSede = @idAzienda
				AND Tipo = @tipo
				AND IdClienteFornitore = @IdClienteFornitore
				AND IdTipo NOT IN ('TD00', 'TD04')
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'La fattura di riferimento non esiste tra le fatture del cliente', 'La fattura di riferimento non esiste tra le fatture del fornitore');
			GOTO BRANCH_END;
		END
		IF LEN(@Causale) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale non può superare i 200 caratteri';
			GOTO BRANCH_END;
		END

		-- Date. Fattura cliente: data di emissione obbligatoria, la registrazione coincide se non indicata.
		-- Fattura fornitore: data e numero del documento ricevuto obbligatori, registrazione oggi se non indicata
		IF @DataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Indicare la data della fattura', 'Indicare la data della fattura del fornitore');
			GOTO BRANCH_END;
		END
		IF @tipo = 'C'
			SET @DataRegistrazione = ISNULL(@DataRegistrazione, @DataEmissione);
		ELSE
			SET @DataRegistrazione = ISNULL(@DataRegistrazione, CAST(GETDATE() AS DATE));

		IF @tipo = 'F' AND @DataRegistrazione < @DataEmissione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di registrazione non può precedere la data della fattura del fornitore';
			GOTO BRANCH_END;
		END
		IF @tipo = 'F' AND @NumeroFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il numero della fattura del fornitore';
			GOTO BRANCH_END;
		END
		IF @tipo = 'C'
			SET @NumeroFornitore = NULL;
		IF LEN(@NumeroFornitore) > 30
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero della fattura del fornitore non può superare i 30 caratteri';
			GOTO BRANCH_END;
		END
		IF @DataOrdine IS NOT NULL AND @DataOrdine > @DataEmissione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data dell''ordine non può seguire la data della fattura';
			GOTO BRANCH_END;
		END
		IF LEN(@Ordine) > 30
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il riferimento dell''ordine non può superare i 30 caratteri';
			GOTO BRANCH_END;
		END

		-- Sezionale: una lettera, facoltativo (nella scheda si sceglie da una select)
		IF @Sezionale IS NOT NULL AND (LEN(@Sezionale) > 1 OR @Sezionale NOT LIKE '[A-Z]')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il sezionale è una sola lettera';
			GOTO BRANCH_END;
		END
		IF @Numero < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero della fattura non può essere negativo';
			GOTO BRANCH_END;
		END

		-- Condizioni di pagamento, come sulla scheda del cliente o del fornitore
		IF @IdModalita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la modalità di pagamento';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdRata IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = @IdRata)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La rateizzazione indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdRataInizio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la decorrenza delle rate (campo Da)';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRateInizi WHERE Id = @IdRataInizio)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La decorrenza delle rate indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdValuta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la valuta';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = @IdValuta)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La valuta indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @RataGiorniInizio < 0 OR @RataGiorniInizio > 31
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il giorno del mese deve essere compreso tra 0 e 31';
			GOTO BRANCH_END;
		END

		-- Banca/cassa: solo dell'azienda della fattura
		IF @IdBancaCassa IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id = @IdBancaCassa
				AND IdSede = @idAzienda
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Il formato dell'IBAN è controllato dall'applicazione (Strings.cs): qui si protegge solo la lunghezza
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		-- RiBa (MP12) su una fattura cliente: serve l'IBAN della banca d'appoggio del cliente
		IF @tipo = 'C' AND @IdModalita = 'MP12' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il pagamento RiBa indicare l''IBAN del cliente';
			GOTO BRANCH_END;
		END
		IF @Bollo < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il bollo non può essere negativo';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCig) > 10
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice CIG non può superare i 10 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCup) > 15
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice CUP non può superare i 15 caratteri';
			GOTO BRANCH_END;
		END

		-- Numerazione: progressiva per azienda, tipo (clienti / fornitori), anno e sezionale. L'anno è
		-- quello della data di emissione per le fatture cliente, della data di registrazione (protocollo)
		-- per le fatture fornitore. La pre-fattura non ha numero: lo riceve quando diventa fattura.
		-- Una bozza salvata senza conferma non impegna un numero
		DECLARE @dataNumero DATE = IIF(@tipo = 'C', @DataEmissione, @DataRegistrazione);
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@dataNumero), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @numerata BIT = IIF(@IdTipo <> 'TD00' AND (@Conferma = 1 OR @lock = 0), 1, 0);

		IF @numerata = 0
			SET @Numero = NULL;

		BEGIN TRANSACTION;
			IF @numerata = 1 AND @Numero IS NULL
			BEGIN
				SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) >= @annoInizio
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) < @annoFine;
			END
			ELSE IF @numerata = 1 AND EXISTS (
				SELECT 1
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND Numero = @Numero
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) >= @annoInizio
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) < @annoFine
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Esiste già una fattura con questo numero nello stesso anno';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblFatture
			SET
				Lock = IIF(@Conferma = 1, 0, Lock),
				IdClienteFornitore = @IdClienteFornitore,
				IdTipo = @IdTipo,
				IdStato = @IdStato,
				IdModalita = @IdModalita,
				IdRata = @IdRata,
				IdRataInizio = @IdRataInizio,
				IdValuta = @IdValuta,
				IdBancaCassa = @IdBancaCassa,
				IdFatturaRiferimento = @IdFatturaRiferimento,
				Numero = @Numero,
				Sezionale = @Sezionale,
				NumeroFornitore = @NumeroFornitore,
				DataRegistrazione = @DataRegistrazione,
				DataEmissione = @DataEmissione,
				Iban = @Iban,
				RataGiorniInizio = @RataGiorniInizio,
				Ordine = @Ordine,
				DataOrdine = @DataOrdine,
				SplitPayment = @SplitPayment,
				Bollo = @Bollo,
				CodiceCig = @CodiceCig,
				CodiceCup = @CodiceCup,
				Causale = @Causale,
				SolaLettura = @SolaLettura
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Fattura non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		IF @Conferma = 1
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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

PRINT 'uspFattureConti_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_del
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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureConti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblFattureConti WHERE Id = @Id);

		-- ── CASO 1: conto attivo (Lock = 0) → soft delete ────────────────────
		IF @lock = 0
		BEGIN
			-- Un conto usato nelle righe di una fattura non cancellata resta
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
					INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				WHERE
					i.IdConto = @Id
					AND f.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato nelle righe di una fattura non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblFattureConti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Conto non trovato o già eliminato';
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

		-- ── CASO 2: conto in bozza (Lock = 2) → hard delete ──────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblFattureConti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il conto è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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

PRINT 'uspFattureConti_del_Undo';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Dopo la cancellazione può essere stato inserito un conto con lo stesso nome o codice
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureConti i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblFattureConti a ON i.IdSede = a.IdSede
												AND (i.Nome = a.Nome OR i.Codice = a.Codice)
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: esiste già un conto con lo stesso nome o codice';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblFattureConti i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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

PRINT 'uspFattureConti_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_get
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
				AND c.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il conto non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			c.Id,
			c.IdSede,
			c.Nome,
			c.Codice,
			c.Lock
		FROM dbo.tblFattureConti c
		WHERE c.Id = @Id;

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

PRINT 'uspFattureConti_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT
			c.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			c.Nome,
			c.Codice,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblFattureConti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR c.Codice LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
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

PRINT 'uspFattureConti_get_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_get_SelectList
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
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: la select serve alle righe delle fatture (FTT) oltre che
		-- alla configurazione (FTC); basta la lettura su una delle due
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: conti dell'azienda interna corrente della sessione
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				c.Id,
				[Text] = CAST(ISNULL(c.Codice + ' - ', '') + c.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(c.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND c.Lock = 0
		) t
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

PRINT 'uspFattureConti_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il conto appartiene all'azienda interna corrente della sessione
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

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblFattureConti (Id, IdSede, Lock)
			VALUES (@returnId, @idAzienda, 2);
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

PRINT 'uspFattureConti_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Codice VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Codice = NULLIF(UPPER(LTRIM(RTRIM(@Codice))), '');

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
			SET @returnMessage = 'Indicare il nome del conto (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END
		IF LEN(@Codice) > 10
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice non può superare i 10 caratteri';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblFattureConti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Nome e codice unici tra i conti attivi dell'azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblFattureConti
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un conto con questo nome';
			GOTO BRANCH_END;
		END
		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblFattureConti
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Codice = @Codice
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un conto con questo codice';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblFattureConti
			SET
				Lock = 0,
				Nome = @Nome,
				Codice = @Codice
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Conto non trovato o già eliminato';
				GOTO BRANCH_END;
			END
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

PRINT 'uspFattureRate_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_del
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita è trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRate WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- La fattura della rata deve esistere (in bozza o attiva, non eliminata), appartenere
		-- all'azienda interna corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFattureRate r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1 FROM dbo.tblFattureRatePagamenti WHERE IdRata = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una rata con pagamenti non può essere tolta';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblFattureRate
			WHERE Id = @Id;
			DELETE dbo.tblIdLog
			WHERE Id = @Id;
			DELETE dbo.tblId
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		END

		SELECT @returnValue AS ReturnValue;

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

PRINT 'uspFattureRate_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_List
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFattura non può essere vuoto';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: fattura dell'azienda interna corrente della sessione. Pagato = quote dei pagamenti attivi attribuite
		-- alla rata. Stato: saldata (pagato + abbuono coprono l'importo), scaduta, da pagare
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT
			r.Id,
			StatoValore = CASE
				WHEN x.Pagato + ISNULL(r.Abbuono, 0) >= r.Importo THEN 0
				WHEN r.DataScadenza < @oggi THEN 2
				ELSE 1
			END,
			StatoDescrizione = CASE
				WHEN x.Pagato + ISNULL(r.Abbuono, 0) >= r.Importo THEN 'Saldata'
				WHEN r.DataScadenza < @oggi THEN 'Scaduta'
				ELSE 'Da pagare'
			END,
			r.DataScadenza,
			Importo = CAST(r.Importo AS DECIMAL(18, 2)),
			Abbuono = CAST(ISNULL(r.Abbuono, 0) AS DECIMAL(18, 2)),
			Pagato = CAST(x.Pagato AS DECIMAL(18, 2))
		FROM
			dbo.tblFattureRate r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			CROSS APPLY
				(
					SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
					FROM
						dbo.tblFattureRatePagamenti rp
						INNER JOIN dbo.tblPagamenti p ON rp.IdPagamento = p.Id
					WHERE
						rp.IdRata = r.Id
						AND p.Lock = 0
				) x
		WHERE
			r.IdFattura = @IdFattura
			AND e.Id = @IdSessione
		ORDER BY
			r.DataScadenza,
			r.Id;

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

PRINT 'uspFattureRate_ins_Genera';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Genera le rate della fattura dalle condizioni di pagamento salvate sulla testata, sostituendo quelle
-- presenti. Numero di rate e mesi della prima vengono dalla rateizzazione (tblPagamentiRate: Numero,
-- PrimaMesi; le successive a un mese l'una dall'altra); senza rateizzazione una sola rata alla data
-- della fattura. Decorrenza DF: scadenza = data della fattura + mesi. Decorrenza FM: fine del mese
-- di (data della fattura + mesi) e, con il giorno del mese indicato, quel giorno del mese successivo.
-- Importo: netto a pagare diviso in parti uguali, con il resto degli arrotondamenti sull'ultima rata.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_ins_Genera
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFattura non può essere vuoto';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		DECLARE @dataEmissione DATE;
		DECLARE @idRataInizio CHAR(2);
		DECLARE @giorno INT;
		DECLARE @numero INT;
		DECLARE @primaMesi INT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0),
			@dataEmissione = f.DataEmissione,
			@idRataInizio = ISNULL(f.IdRataInizio, 'DF'),
			@giorno = ISNULL(f.RataGiorniInizio, 0),
			@numero = ISNULL(r.Numero, 1),
			@primaMesi = ISNULL(r.PrimaMesi, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblPagamentiRate r ON f.IdRata = r.Id
		WHERE
			f.Id = @IdFattura
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END
		IF @dataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data della fattura prima di generare le rate';
			GOTO BRANCH_END;
		END
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFattureRatePagamenti p ON r.Id = p.IdRata
			WHERE r.IdFattura = @IdFattura)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le rate hanno già dei pagamenti: non si possono rigenerare';
			GOTO BRANCH_END;
		END

		DECLARE @netto DECIMAL(18, 2);
		SELECT @netto = NettoAPagare
		FROM dbo.ufnFatture_get_Totali(@IdFattura);

		IF ISNULL(@netto, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura non ha un importo da pagare: inserire prima le righe';
			GOTO BRANCH_END;
		END
		IF @numero < 1 SET @numero = 1;

		-- Scadenze e importi; gli Id (uspId_get) FUORI dalla transazione
		DECLARE @rate TABLE (
			N INT NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			DataScadenza DATE NOT NULL,
			Importo DECIMAL(18, 2) NOT NULL
		);
		DECLARE @quota DECIMAL(18, 2) = ROUND(@netto / @numero, 2, 1);
		DECLARE @n INT = 1;
		DECLARE @scadenza DATE;
		DECLARE @fineMese DATE;
		DECLARE @id CHAR(16);

		WHILE @n <= @numero
		BEGIN
			SET @scadenza = DATEADD(MONTH, @primaMesi + @n - 1, @dataEmissione);
			IF @idRataInizio = 'FM'
			BEGIN
				SET @scadenza = EOMONTH(@scadenza);
				IF @giorno > 0
				BEGIN
					-- Giorno del mese successivo, non oltre la sua fine (31 in un mese di 30 giorni)
					SET @fineMese = EOMONTH(DATEADD(DAY, 1, @scadenza));
					SET @scadenza = DATEADD(DAY, IIF(@giorno > DAY(@fineMese), DAY(@fineMese), @giorno), @scadenza);
				END
			END

			SET @id = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @id OUTPUT;

			INSERT @rate (N, Id, DataScadenza, Importo)
			VALUES (@n, @id, @scadenza, IIF(@n = @numero, @netto - @quota * (@numero - 1), @quota));

			SET @n += 1;
		END

		DECLARE @vecchie TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

		BEGIN TRANSACTION;
			INSERT @vecchie (Id)
			SELECT Id
			FROM dbo.tblFattureRate WITH (UPDLOCK, HOLDLOCK)
			WHERE IdFattura = @IdFattura;

			DELETE dbo.tblFattureRate
			WHERE IdFattura = @IdFattura;
			DELETE dbo.tblIdLog
			WHERE Id IN (SELECT Id FROM @vecchie);
			DELETE dbo.tblId
			WHERE Id IN (SELECT Id FROM @vecchie);

			INSERT dbo.tblFattureRate (Id, IdFattura, Importo, Abbuono, DataScadenza)
			SELECT Id, @IdFattura, Importo, 0, DataScadenza
			FROM @rate;
		COMMIT TRANSACTION;

		SELECT ReturnValue = @numero;

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

PRINT 'uspFattureRate_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva una rata (scadenza) della fattura: con @Id vuoto la aggiunge a @IdFattura, altrimenti la
-- modifica. Le rate si salvano subito, anche sulla fattura in bozza. Restituisce l'Id della rata.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_upd
	@Id CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@DataScadenza DATE = NULL,
	@Importo DECIMAL(18, 2) = NULL,
	@Abbuono DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Abbuono = ISNULL(@Abbuono, 0);

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Rata esistente: la fattura è quella della rata
		IF @Id IS NOT NULL
		BEGIN
			SET @IdFattura = NULL;
			SELECT @IdFattura = IdFattura
			FROM dbo.tblFattureRate
			WHERE Id = @Id;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @IdFattura
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		IF @DataScadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data di scadenza della rata';
			GOTO BRANCH_END;
		END
		IF @Importo IS NULL OR @Importo <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo della rata deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Abbuono < 0 OR @Abbuono > @Importo
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''abbuono deve essere compreso tra zero e l''importo della rata';
			GOTO BRANCH_END;
		END

		-- Rata con pagamenti: l'importo, tolto l'abbuono, non può scendere sotto quanto già pagato
		IF @Id IS NOT NULL
		BEGIN
			DECLARE @pagato DECIMAL(18, 2);
			SELECT @pagato = ISNULL(SUM(rp.Importo), 0)
			FROM
				dbo.tblFattureRatePagamenti rp
				INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
			WHERE
				rp.IdRata = @Id
				AND g.Lock = 0;

			IF @Importo - @Abbuono < @pagato
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo della rata, tolto l''abbuono, non può essere inferiore a quanto già pagato (' + FORMAT(@pagato, 'N2', 'it-IT') + ')';
				GOTO BRANCH_END;
			END
		END

		-- Nuova rata: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
				INSERT dbo.tblFattureRate (Id, IdFattura, Importo, Abbuono, DataScadenza)
				VALUES (@Id, @IdFattura, @Importo, @Abbuono, @DataScadenza);
			ELSE
				UPDATE dbo.tblFattureRate
				SET
					Importo = @Importo,
					Abbuono = @Abbuono,
					DataScadenza = @DataScadenza
				WHERE Id = @Id;
		COMMIT TRANSACTION;

		SELECT Id = @Id;

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

PRINT 'uspFattureRighe_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_del
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita è trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRighe WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- La fattura della riga deve esistere (in bozza o attiva, non eliminata), appartenere
		-- all'azienda interna corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblFattureRigheImporti
			WHERE Id = @Id;
			DELETE dbo.tblFattureRighe
			WHERE Id = @Id;
			DELETE dbo.tblIdLog
			WHERE Id = @Id;
			DELETE dbo.tblId
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		END

		SELECT @returnValue AS ReturnValue;

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

PRINT 'uspFattureRighe_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_get_List
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFattura non può essere vuoto';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: fattura dell'azienda interna corrente della sessione. Una riga senza importi è di sola
		-- descrizione (ConImporti = 0). Imponibile = Quantita x Importo, arrotondato al centesimo
		SELECT
			r.Id,
			r.Pos,
			r.Descrizione,
			ConImporti = CAST(IIF(i.Id IS NULL, 0, 1) AS BIT),
			i.Quantita,
			i.Importo,
			i.IdUnitaMisura,
			UnitaMisuraCodice = u.Codice,
			i.IdAliquotaIva,
			AliquotaIvaNome = a.Nome,
			i.IdConto,
			ContoNome = c.Nome,
			i.RitenutaAcconto,
			Imponibile = CAST(ROUND(i.Quantita * i.Importo, 2) AS DECIMAL(18, 2))
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
			LEFT JOIN dbo.tblUnitaMisura u ON i.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblAliquoteIva a ON i.IdAliquotaIva = a.Id
			LEFT JOIN dbo.tblFattureConti c ON i.IdConto = c.Id
		WHERE
			r.IdFattura = @IdFattura
			AND e.Id = @IdSessione
		ORDER BY
			ISNULL(r.Pos, 0),
			r.Id;

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

PRINT 'uspFattureRighe_get_UnitaMisura_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Unità di misura per le righe della fattura: tutte, con la prima voce "(Nessuna)".
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_get_UnitaMisura_SelectList
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('00' AS CHAR(2)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '00', 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblUnitaMisura
		) t
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

PRINT 'uspFattureRighe_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva una riga della fattura: con @Id vuoto la aggiunge in coda a @IdFattura, altrimenti la modifica.
-- Una riga senza quantità né importo è di sola descrizione (nessuna riga in tblFattureRigheImporti).
-- Le righe si salvano subito, anche sulla fattura in bozza. Restituisce l'Id della riga.
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_upd
	@Id CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@Quantita DECIMAL(18, 4) = NULL,
	@Importo DECIMAL(18, 4) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdConto CHAR(16) = NULL,
	@RitenutaAcconto INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');
		SET @IdUnitaMisura = NULLIF(NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), ''), REPLICATE('0', 2));
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Riga esistente: la fattura è quella della riga
		DECLARE @idAliquotaIvaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			SET @IdFattura = NULL;
			SELECT
				@IdFattura = r.IdFattura,
				@idAliquotaIvaAttuale = i.IdAliquotaIva,
				@idContoAttuale = i.IdConto
			FROM
				dbo.tblFattureRighe r
				LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
			WHERE r.Id = @Id;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @IdFattura
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		IF @Descrizione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la descrizione della riga';
			GOTO BRANCH_END;
		END

		-- Riga con importi: importo (prezzo unitario) e aliquota IVA obbligatori; quantità 1 se non indicata.
		-- L'importo può essere negativo (sconti, storni)
		DECLARE @conImporti BIT = IIF(@Quantita IS NULL AND @Importo IS NULL, 0, 1);
		IF @conImporti = 1
		BEGIN
			SET @Quantita = ISNULL(@Quantita, 1);
			SET @RitenutaAcconto = ISNULL(@RitenutaAcconto, 0);

			IF @Importo IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare l''importo unitario della riga';
				GOTO BRANCH_END;
			END
			IF @Quantita <= 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità deve essere maggiore di zero';
				GOTO BRANCH_END;
			END
			IF @IdAliquotaIva IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''aliquota IVA della riga';
				GOTO BRANCH_END;
			END
			-- Aliquota IVA: di sistema (IdSede NULL) o dell'azienda; quella già sulla riga resta valida
			IF NOT EXISTS (
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
			IF @IdUnitaMisura IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblUnitaMisura WHERE Id = @IdUnitaMisura)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''unità di misura indicata non esiste';
				GOTO BRANCH_END;
			END
			IF @RitenutaAcconto < 0 OR @RitenutaAcconto > 100
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La ritenuta d''acconto deve essere compresa tra 0 e 100';
				GOTO BRANCH_END;
			END
		END

		-- Nuova riga: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
			BEGIN
				-- In coda alle righe della fattura
				DECLARE @pos INT;
				SELECT @pos = ISNULL(MAX(Pos), 0) + 1
				FROM dbo.tblFattureRighe WITH (UPDLOCK, HOLDLOCK)
				WHERE IdFattura = @IdFattura;

				INSERT dbo.tblFattureRighe (Id, IdFattura, Descrizione, Pos)
				VALUES (@Id, @IdFattura, @Descrizione, @pos);
			END
			ELSE
			BEGIN
				UPDATE dbo.tblFattureRighe
				SET Descrizione = @Descrizione
				WHERE Id = @Id;
			END

			DELETE dbo.tblFattureRigheImporti
			WHERE Id = @Id;

			IF @conImporti = 1
				INSERT dbo.tblFattureRigheImporti (Id, IdAliquotaIva, IdConto, IdUnitaMisura, Quantita, Importo, RitenutaAcconto)
				VALUES (@Id, @IdAliquotaIva, @IdConto, @IdUnitaMisura, @Quantita, @Importo, @RitenutaAcconto);
		COMMIT TRANSACTION;

		SELECT Id = @Id;

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

PRINT 'uspFattureRighe_upd_Pos';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sposta su (@Direzione = -1) o giù (@Direzione = 1) una riga della fattura. Prima dello scambio le
-- righe vengono rinumerate 1..n nell'ordine corrente, così i buchi lasciati dalle righe tolte non
-- contano. Sulla prima riga "su" e sull'ultima "giù" non fanno nulla.
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_upd_Pos
	@Id CHAR(16) = NULL,
	@Direzione SMALLINT = NULL,
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
		IF @Direzione IS NULL OR @Direzione NOT IN (-1, 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Direzione deve essere -1 (su) o 1 (giù)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La fattura della riga deve esistere (in bozza o attiva, non eliminata), appartenere
		-- all'azienda interna corrente della sessione e non essere in sola lettura
		DECLARE @idFattura CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idFattura = f.Id,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		DECLARE @righe TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			PosAttuale INT NULL,
			PosNuova INT NOT NULL
		);

		BEGIN TRANSACTION;
			-- Stesso ordinamento di uspFattureRighe_get_List
			INSERT @righe (Id, PosAttuale, PosNuova)
			SELECT
				Id,
				Pos,
				ROW_NUMBER() OVER (ORDER BY ISNULL(Pos, 0), Id)
			FROM dbo.tblFattureRighe WITH (UPDLOCK, HOLDLOCK)
			WHERE IdFattura = @idFattura;

			DECLARE @pos INT, @posAltra INT;
			SELECT @pos = PosNuova
			FROM @righe
			WHERE Id = @Id;
			SET @posAltra = @pos + @Direzione;

			IF EXISTS (SELECT 1 FROM @righe WHERE PosNuova = @posAltra)
			BEGIN
				UPDATE @righe
				SET PosNuova = IIF(Id = @Id, @posAltra, @pos)
				WHERE PosNuova IN (@pos, @posAltra);
			END

			UPDATE r
			SET Pos = t.PosNuova
			FROM
				dbo.tblFattureRighe r
				INNER JOIN @righe t ON r.Id = t.Id
			WHERE ISNULL(t.PosAttuale, -1) <> t.PosNuova;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

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

PRINT 'uspClientiFornitori_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_del
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

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità): scope azienda interna corrente della sessione
		DECLARE @tipo CHAR(1);
		DECLARE @lock INT;
		SELECT
			@tipo = c.Tipo,
			@lock = c.Lock
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @tipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: scheda attiva (Lock = 0) → soft delete ───────────────────
		IF @lock = 0
		BEGIN
			-- Una scheda con fatture non cancellate resta
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdClienteFornitore = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = IIF(@tipo = 'C', 'Un cliente con fatture non può essere cancellato', 'Un fornitore con fatture non può essere cancellato');
				GOTO BRANCH_END;
			END
			BEGIN TRANSACTION;
				UPDATE dbo.tblClientiFornitori
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato o già eliminato', 'Fornitore non trovato o già eliminato');
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

		-- ── CASO 2: scheda in bozza (Lock = 2) → hard delete ─────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblClientiFornitori
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La scheda è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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

PRINT 'uspBancheCasse_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_del
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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblBancheCasse c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblBancheCasse WHERE Id = @Id);

		-- ── CASO 1: banca o cassa attiva (Lock = 0) → soft delete ────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdBancaCassa = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una banca o cassa associata a clienti o fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdBancaCassa = @Id AND Lock IN (0, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una banca o cassa indicata in una fattura non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblPagamenti WHERE IdBancaCassa = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una banca o cassa con pagamenti registrati non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblBancheCasse
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Banca o cassa non trovata o già eliminata';
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

		-- ── CASO 2: banca o cassa in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblBancheCasse
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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

PRINT 'uspAliquoteIva_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_del
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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Le aliquote di sistema (IdSede NULL) non si cancellano mai, da nessun utente
		IF EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id AND IdSede IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''aliquota di sistema non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAliquoteIva c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblAliquoteIva WHERE Id = @Id);

		-- ── CASO 1: aliquota attiva (Lock = 0) → soft delete ──────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdAliquotaIva = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''aliquota associata a clienti o fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
					INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				WHERE
					i.IdAliquotaIva = @Id
					AND f.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''aliquota usata nelle righe di una fattura non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblAliquoteIva
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Aliquota non trovata o già eliminata';
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

		-- ── CASO 2: aliquota in bozza (Lock = 2) → hard delete ────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblAliquoteIva
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''aliquota è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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

PRINT 'uspBancheCasse_get_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get_SelectList
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
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: la select serve alla scheda cliente (ANC) e fornitore (ANF)
		-- oltre che alla configurazione (FTC); basta la lettura su una delle tre
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		-- Le fatture (FTT) usano la stessa select
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTT',
				@Permesso = @permesso OUTPUT;
		END		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: banche e casse dell'azienda interna corrente della sessione
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				b.Id,
				[Text] = CAST(b.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(b.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblBancheCasse b
				INNER JOIN dbo.tblSessioni e ON b.IdSede = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND b.Lock = 0
		) t
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

PRINT 'uspAliquoteIva_get_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_SelectList
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
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: la select serve alla scheda cliente (ANC) e fornitore (ANF)
		-- oltre che alla configurazione (FTC); basta la lettura su una delle tre
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		-- Le fatture (FTT) usano la stessa select
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTT',
				@Permesso = @permesso OUTPUT;
		END		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Aliquote di sistema (IdSede NULL) più quelle dell'azienda interna corrente della sessione,
		-- dalla più alta alla più bassa
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0,
				Valore = CAST(NULL AS DECIMAL(9, 2))

			UNION ALL

			SELECT
				a.Id,
				[Text] = CAST(a.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(a.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				a.Valore
			FROM dbo.tblAliquoteIva a
			WHERE
				(a.IdSede IS NULL OR a.IdSede = @idAzienda)
				AND a.Lock = 0
		) t
		ORDER BY Pos, Valore DESC, [Text];

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

PRINT 'uspSedi_del_SediInterne';
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
GO

PRINT 'uspSYS_del_SedeInternaCascade';
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

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

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
GO

PRINT 'uspSYS_del_SedeEsternaCascade';
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

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

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
GO
