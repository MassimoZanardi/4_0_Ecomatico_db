/*
Deploy produzione 2026-11-04 - Formulario unico degli spurghisti (art. 230, comma 5) e Vi.Vi.FIR: fasi 2-5
(operazioni P e Q, indirizzi di intervento, esclusione dal RENTRI, credenziali e aziende Vi.Vi.FIR, vidimazione,
stampa)

Rieseguibile. Eseguire con sqlcmd -f 65001 -I -b (oppure da SSMS) sul DB 4_0_ecomatico, DOPO
1_0_vivifir\tools\deploy_produzione_2026-11-04_creazione.sql (le SP delle credenziali scrivono in
[1_0_vivifir]..tblCredenziali). Poi pubblicare l'app e l'hub 1_0_ViviFirApi.

0. Controllo: 4_0_ecomatico e 1_0_vivifir devono avere la collation Latin1_General_CI_AS, altrimenti lo script si
   ferma senza modificare nulla. In SSMS, dopo il messaggio "Script interrotto" possono comparire errori di
   compilazione degli oggetti successivi: non eseguono nulla.
1. tools\formulario_unico_struttura.sql: colonna tblRifiutiOperazioni.IsFormularioUnico, operazioni P e Q (create se
   mancano), P e Q con IsFormulario = 1, tabella tblRifiutiMovimentiSediProduzione, P configurata come F e Q come T,
   modulo VVF (Vi.Vi.FIR, richiede Rifiuti), colonna tblRifiutiMovimenti.ViviFirVidimato.
   Il modulo NON viene attivato su nessun dominio: si attiva da Impostazioni > Domini.
2. tools\vivifir_credenziali_struttura.sql: tblViviFirCredenziali, tblViviFirCredenzialiAziende, funzione VVC
   (amministratori), area di menu Vivifir con le voci Credenziali e Aziende.
3. Vista viewViviFirFormulari: dati di stampa, letta dall'hub con [1_0_vivifir]..uspFormulario_get_Stampa.
4. SP nuove: uspRifiutiFormulari_get_SediProduzione_List, _get_ViviFirVidimazione, _upd_ViviFirNumero,
   _get_ViviFirStampa; uspViviFirAziende_* (7) e uspViviFirCredenziali_* (8).
5. SP modificate: uspRifiutiFormulari_del, _del_Undo, _get, _get_List, _ins, _upd; uspRifiutiLimiti_get_Operazioni_List;
   uspRifiutiMovimenti_ins_DaAcquisizioneFormulario; uspRifiutiOperazioni_get_SelectList; uspRifiutiRegistrazioni_del,
   _get, _get_List, _get_Report, _upd; uspSedi_del, _del_SediEsterne, _del_SediInterne; uspSYS_del_RegistroCascade,
   _RifiutiMovimentiCascade, _SedeEsternaCascade, _SedeInternaCascade (solo uso tecnico).
   uspRifiutiRegistrazioni_upd conserva anche il numero del formulario assegnato dal RENTRI (F2.9 di
   rentri-formulari.md).
Regole in docs/regole/formulario-unico.md (repo app).
*/
-- ===== 0. Controllo della collation
IF CAST(DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS NVARCHAR(128)) <> N'Latin1_General_CI_AS'
	OR DB_ID('1_0_vivifir') IS NULL
	OR CAST(DATABASEPROPERTYEX('1_0_vivifir', 'Collation') AS NVARCHAR(128)) <> N'Latin1_General_CI_AS'
BEGIN
	RAISERROR('Script interrotto: 4_0_ecomatico e 1_0_vivifir devono esistere con la collation Latin1_General_CI_AS (eseguire prima lo script di 1_0_vivifir)', 16, 1);
	SET NOEXEC ON;
END
GO

-- ===== tools\formulario_unico_struttura.sql
-- Formulario unico per l'attività di pulizia manutentiva delle reti fognarie (art. 230, comma 5, D.Lgs. 152/2006),
-- vidimato su Vi.Vi.FIR e non sul RENTRI. Al RENTRI va solo la registrazione di carico (operazione P, codice RE).
-- 1) colonna tblRifiutiOperazioni.IsFormularioUnico e le due operazioni del formulario unico, create se mancano, le sole con
--    IsFormularioUnico = 1: P "Carico di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)"
--    (carico, codice RE: il rifiuto va al deposito temporaneo dello spurghista, riquadro 5.1 del modello) e Q "Trasporto
--    di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)" (carico e scarico, codice T*aT: il
--    rifiuto va direttamente all'impianto, riquadro 5.2);
-- 2) P e Q con IsFormulario = 1: Rifiuti > Formulari le propone e il formulario condivide il movimento con la
--    registrazione, come per lo scarico S (tblRifiutiFormulari, tblRifiutiFormulariTrasportiTerresti);
-- 3) tabella tblRifiutiMovimentiSediProduzione: indirizzi di intervento del formulario (al massimo 10, come le righe
--    del modello Albo-2022-A), con la quantità stimata, e indice per sede (controlli sulla cancellazione delle sedi);
-- 4) P configurata come F (l'altro carico RE) e Q come T (l'altro T*aT): stessi tipi di registro
--    (tblRifiutiOperazioniRegistriTipi) e stesse operazioni di scarico che ne prelevano la quantità (tblRifiutiOperazioniRelazioni:
--    R e S per la P, nessuna per la Q);
-- 5) modulo VVF (Vi.Vi.FIR), che richiede il modulo Rifiuti: senza VVF sul dominio P e Q non si propongono;
-- 6) colonna tblRifiutiMovimenti.ViviFirVidimato (numero vidimato su Vi.Vi.FIR).
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF COL_LENGTH('dbo.tblRifiutiOperazioni', 'IsFormularioUnico') IS NULL
	ALTER TABLE dbo.tblRifiutiOperazioni ADD IsFormularioUnico BIT NULL;
GO
IF NOT EXISTS (SELECT 1
FROM dbo.tblRifiutiOperazioni
WHERE Id = 'P')
	INSERT dbo.tblRifiutiOperazioni
		(Id, Operazione, Codice, Nome, IsRentri, ProduttoreSede, TrasportatoreSede, DestinatarioSede, IntermediarioSede, Pos,
		OperazioneAuto, IsFormulario, IsIntegrazioneFir, IsProduttore, IsTrasportatore, IsDestinatario, IsIntermediario,
		IsAttivitaRs, IsEsito, IsAttivitaProvenienza, IsMateriale, IsStoccaggioIstantaneo, IsRentriAccettazione, IsFatturabile,
		IsFormularioUnico)
	VALUES
		('P', 'C', 'RE', 'Carico di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)', 1, 1, 1, 0, 0, 11,
		NULL, 1, 1, 1, 1, 1, 0,
		0, 0, 1, 0, 0, 0, 0,
		1);

IF NOT EXISTS (SELECT 1
FROM dbo.tblRifiutiOperazioni
WHERE Id = 'Q')
	INSERT dbo.tblRifiutiOperazioni
		(Id, Operazione, Codice, Nome, IsRentri, ProduttoreSede, TrasportatoreSede, DestinatarioSede, IntermediarioSede, Pos,
		OperazioneAuto, IsFormulario, IsIntegrazioneFir, IsProduttore, IsTrasportatore, IsDestinatario, IsIntermediario,
		IsAttivitaRs, IsEsito, IsAttivitaProvenienza, IsMateriale, IsStoccaggioIstantaneo, IsRentriAccettazione, IsFatturabile,
		IsFormularioUnico)
	VALUES
		('Q', 'X', 'T*aT', 'Trasporto di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)', 1, 0, 1, 0, 0, 12,
		NULL, 1, 1, 1, 1, 1, 0,
		1, 1, 0, 0, 0, 0, 0,
		1);
GO
UPDATE dbo.tblRifiutiOperazioni
SET IsFormularioUnico = IIF(Id IN ('P', 'Q'), 1, 0)
WHERE ISNULL(IsFormularioUnico, 2) <> IIF(Id IN ('P', 'Q'), 1, 0);

UPDATE dbo.tblRifiutiOperazioni
SET IsFormulario = 1
WHERE
	Id IN ('P', 'Q')
	AND ISNULL(IsFormulario, 0) = 0;
GO
IF OBJECT_ID('dbo.tblRifiutiMovimentiSediProduzione', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblRifiutiMovimentiSediProduzione (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdSede CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		Quantita DECIMAL(18, 2) NULL,
		Pos TINYINT NULL,
		CONSTRAINT PK_tblRifiutiMovimentiSediProduzione PRIMARY KEY CLUSTERED (Id ASC, IdSede ASC)
	);

	ALTER TABLE dbo.tblRifiutiMovimentiSediProduzione WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiSediProduzione_tblRifiutiMovimenti
		FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiSediProduzione WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiSediProduzione_tblSedi
		FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
END
GO
IF NOT EXISTS (SELECT 1
FROM sys.indexes
WHERE
	object_id = OBJECT_ID('dbo.tblRifiutiMovimentiSediProduzione')
	AND name = 'IX_RifiutiMovimentiSediProduzione_IdSede'
)
	CREATE NONCLUSTERED INDEX IX_RifiutiMovimentiSediProduzione_IdSede ON dbo.tblRifiutiMovimentiSediProduzione (IdSede ASC);
GO
INSERT dbo.tblRifiutiOperazioniRegistriTipi (Id, IdTipo)
SELECT x.Id, f.IdTipo
FROM
	(VALUES ('P', 'F'), ('Q', 'T')) x (Id, IdModello)
	INNER JOIN dbo.tblRifiutiOperazioniRegistriTipi f ON f.Id = x.IdModello
WHERE NOT EXISTS (SELECT 1
FROM dbo.tblRifiutiOperazioniRegistriTipi p
WHERE
	p.Id = x.Id
	AND p.IdTipo = f.IdTipo
);

INSERT dbo.tblRifiutiOperazioniRelazioni (Id, IdParent)
SELECT f.Id, 'P'
FROM dbo.tblRifiutiOperazioniRelazioni f
WHERE
	f.IdParent = 'F'
	AND NOT EXISTS (SELECT 1
	FROM dbo.tblRifiutiOperazioniRelazioni p
	WHERE
		p.Id = f.Id
		AND p.IdParent = 'P'
	);
GO
IF NOT EXISTS (SELECT 1
FROM dbo.tblModuli
WHERE Id = 'VVF')
	INSERT dbo.tblModuli (Id, Nome, Attivo)
	VALUES ('VVF', 'Vi.Vi.FIR', 1);

IF NOT EXISTS (SELECT 1
FROM dbo.tblModuliRelazioni
WHERE
	Id = 'RIF'
	AND IdParent = 'VVF'
)
	INSERT dbo.tblModuliRelazioni (Id, IdParent)
	VALUES ('RIF', 'VVF');
GO
-- 6) colonna tblRifiutiMovimenti.ViviFirVidimato: il numero del formulario unico è stato vidimato su Vi.Vi.FIR
--    (Rifiuti > Formulari, "Vi.Vi.FIR - Vidima formulario unico"): blocca il numero e colora di verde l'icona degli elenchi
IF COL_LENGTH('dbo.tblRifiutiMovimenti', 'ViviFirVidimato') IS NULL
	ALTER TABLE dbo.tblRifiutiMovimenti ADD ViviFirVidimato BIT NULL;
GO
GO

-- ===== tools\vivifir_credenziali_struttura.sql
-- Vi.Vi.FIR (formulario unico degli spurghisti, art. 230, comma 5): configurazione nell'app, come Diwass > Credenziali
-- e Aziende. Da eseguire dopo 1_0_vivifir\tools\vivifir_creazione.sql (le SP dell'app scrivono in
-- [1_0_vivifir]..tblCredenziali) e dopo tools/formulario_unico_struttura.sql (modulo VVF).
-- 1) tblViviFirCredenziali: credenziale applicativa del dominio (nome, scadenza informativa, Id della riga dell'hub);
-- 2) tblViviFirCredenzialiAziende: azienda interna dello spurghista ↔ credenziale (al massimo una per azienda), con
--    l'esito dell'ultima verifica: soggetto Vi.Vi.FIR e codice del blocco del formulario unico (isArt230c5);
-- 3) funzione VVC (Vi.Vi.FIR, riservata agli amministratori) del modulo VVF;
-- 4) area di menu Vivifir (Id = modulo VVF, dopo Diwass) con le voci Credenziali e Aziende.
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.tblViviFirCredenziali', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblViviFirCredenziali (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdDominio CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdViviFir CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		Nome VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		Scadenza DATE NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblViviFirCredenziali PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblViviFirCredenziali WITH CHECK ADD CONSTRAINT FK_tblViviFirCredenziali_tblDomini
		FOREIGN KEY (IdDominio) REFERENCES dbo.tblDomini (Id);

	CREATE NONCLUSTERED INDEX IX_ViviFirCredenziali_IdDominio_Lock ON dbo.tblViviFirCredenziali (IdDominio ASC, Lock ASC);
END
GO
IF OBJECT_ID('dbo.tblViviFirCredenzialiAziende', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblViviFirCredenzialiAziende (
		IdAziendaInterna CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdCredenziale CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdSoggetto INT NULL,
		Soggetto VARCHAR(255) COLLATE Latin1_General_CI_AS NULL,
		Blocco VARCHAR(20) COLLATE Latin1_General_CI_AS NULL,
		DataVerifica DATETIME2(0) NULL,
		CONSTRAINT PK_tblViviFirCredenzialiAziende PRIMARY KEY CLUSTERED (IdAziendaInterna ASC)
	);

	ALTER TABLE dbo.tblViviFirCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblViviFirCredenzialiAziende_tblSediInterne
		FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id);
	ALTER TABLE dbo.tblViviFirCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblViviFirCredenzialiAziende_tblViviFirCredenziali
		FOREIGN KEY (IdCredenziale) REFERENCES dbo.tblViviFirCredenziali (Id);

	CREATE NONCLUSTERED INDEX IX_ViviFirCredenzialiAziende_IdCredenziale ON dbo.tblViviFirCredenzialiAziende (IdCredenziale ASC);
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'VVC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, [Master], Admin, Attiva) VALUES ('VVC', 'Vi.Vi.FIR', 0, 1, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'VVF' AND IdFunzione = 'VVC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('VVF', 'VVC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagineAree WHERE Id = 'VVF')
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('VVF', 'Vivifir', 'fal fa-stamp');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'VVZ')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('VVZ', 'VVC', 'Credenziali', NULL);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'VVY')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('VVY', 'VVC', 'Aziende', NULL);

-- Area dopo Diwass (AL0, Pos 10), prima di Impostazioni
UPDATE dbo.tblMenu SET Pos = 12 WHERE Id = 'AZ0' AND Pos <> 12;
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AM0')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AM0', NULL, 'VVF', NULL, 11);
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AM1')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AM1', 'AM0', NULL, 'VVZ', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AM2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AM2', 'AM0', NULL, 'VVY', 1);
GO
GO

-- ===== sql\views\viewViviFirFormulari.sql
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
GO

-- ===== sql\procedures\uspRifiutiFormulari_del.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
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
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RFR', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il formulario esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione (via registro/sede) — stesso pattern di
		-- uspRifiutiFormulari_get.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiFormulari
		WHERE Id = @Id);

		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT @rentriIdentificativo = r.RentriIdentificativo, @rentriData = r.RentriData
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		WHERE f.Id = @Id;

		-- Se la registrazione associata è già stata trasmessa a RENTRI, il formulario non può
		-- più essere cancellato (un formulario senza registrazione associata resta cancellabile)
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione associata è già stata inviata al RENTRI: il formulario non può più essere cancellato';
			GOTO BRANCH_END;
		END

		-- Se il record è già stato aggiunto
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;

				UPDATE dbo.tblRifiutiFormulari
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT dbo.tblIdCancellati (Id, IdSessione, [Data]) VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			-- Aggiorna il log (fuori dalla transazione)
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END
		ELSE IF @lock = 2
		BEGIN
			DECLARE @idMovimento CHAR(16);
			SELECT @idMovimento = IdMovimento
			FROM dbo.tblRifiutiFormulari
			WHERE Id = @Id;

			BEGIN TRANSACTION;

				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE Id = @idMovimento;
				-- Indirizzi di intervento del formulario unico (art. 230, comma 5)
				DELETE dbo.tblRifiutiMovimentiSediProduzione
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE Id = @idMovimento;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiFormulariEtichette
				WHERE Id = @Id;
				-- Aggiunte per il recente cambio di schema: dettagli 1:1 a chiave condivisa
				-- (Id NOT NULL) di tblRifiutiFormulari, bloccano la DELETE su tblRifiutiFormulari
				-- se esistono righe
				DELETE dbo.tblRifiutiFormulariTrasportiFerroviari
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulariTrasportiMarittimi
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulariTrasportiTerresti
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE IdMovimento = @idMovimento;
				DELETE dbo.tblRifiutiMovimenti
				WHERE Id = @idMovimento;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR Id = @idMovimento;
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR Id = @idMovimento;

			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

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
		THROW 50001, @returnMessage, 1
	END

END;
GO

-- ===== sql\procedures\uspRifiutiFormulari_del_Undo.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_del_Undo]
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

		-- Un formulario cancellato la cui registrazione indica nel frattempo un altro documento di trasporto (Allegato
		-- VII o Allegato I-B) non si ripristina: con il cambio del documento il numero del formulario è stato azzerato
		-- (uspRifiutiRegistrazioni_upd)
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblIdCancellati c
				INNER JOIN dbo.tblRifiutiFormulari f ON c.Id = f.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento
			WHERE
				c.IdSessione = @IdSessione
				AND r.Lock < 2
				AND r.IdTrasportoTransfrontalieroTipo IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario non può essere ripristinato: la sua registrazione indica ora un altro documento di trasporto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM
				dbo.tblRifiutiFormulari i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE c.IdSessione = @IdSessione;

			-- Aggiorna il Log
			DELETE i
			FROM
				dbo.tblIdLog i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;

			SET @returnMessage = IIF(@@ROWCOUNT = 1, 'Entità ripristinata', FORMAT(@@ROWCOUNT, 'N0', 'it-IT') + ' entità ripristinate');

		COMMIT TRANSACTION;

		SELECT ReturnMessage = @returnMessage;

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
GO

-- ===== sql\procedures\uspRifiutiFormulari_get.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: con un formulario attivo @IdDocumentoTrasportoTipo deve restare il Formulario; per un altro documento si cancella prima il formulario
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del
 formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = f.Id,
			IdMovimento = m.Id,
			m.IdRegistro,
			IdOperazione = ISNULL(m.IdOperazione, '0'),
			OperazioneNome = ISNULL(o.Nome, ''),
			-- Formulario unico (art. 230, comma 5): indirizzi di intervento, vidimazione su Vi.Vi.FIR e non sul RENTRI
			IsFormularioUnico = CAST(ISNULL(o.IsFormularioUnico, 0) AS BIT),
			-- Formulario unico verso il deposito temporaneo dello spurghista (riquadro 5.1 del modello): l'operazione di carico (P);
			-- quella di carico e scarico (Q) porta il rifiuto direttamente all'impianto (riquadro 5.2)
			IsFormularioUnicoDeposito = CAST(IIF(ISNULL(o.IsFormularioUnico, 0) = 1 AND o.Operazione = 'C', 1, 0) AS BIT),
			IdEer = ISNULL(m.IdEer, '000000'),
			IdProvenienza = ISNULL(m.IdProvenienza, 'S'),
			IdStatoFisico = ISNULL(m.IdStatoFisico, '0'),
			IdAttivitaRs = ISNULL(m.IdAttivita, '00'),
			VerificatoInPartenza = ISNULL(f.VerificatoInPartenza, 0),

			IsRegistrazioneAssociata = CAST(IIF(r.Id IS NOT NULL AND r.Lock < 2, 1, 0) AS BIT),
			RegistrazioneData = ISNULL(r.[Data], GETDATE()),
			RegistrazioneNumero = ISNULL(r.Numero, 0),

			-- Dati formulario
			FormularioNumero = ISNULL(m.FormularioNumero, ''),
			FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
			RentriFormularioStato = m.RentriFormularioStato,
			-- Numero vidimato su RENTRI con "RENTRI - Crea formulario cartaceo": blocca il numero e non
			-- fa più proporre la creazione del formulario (cartaceo o digitale)
			RentriFormularioCartaceo = ISNULL(m.RentriFormularioCartaceo, 0),
			-- Numero del formulario unico vidimato su Vi.Vi.FIR: blocca il numero e non fa più proporre la vidimazione
			ViviFirVidimato = CAST(ISNULL(m.ViviFirVidimato, 0) AS BIT),
			IdAdr = ISNULL(f.IdAdr, '00'),
			NumeroOnu = ISNULL(f.NumeroOnu, ''),
			TrasportoAdr = ISNULL(f.TrasportoAdr, 0),
			AdrNote = ISNULL(f.AdrNote, ''),
			IdImballo = ISNULL(f.IdImballo, '00'),
			Quantita = ISNULL(m.Quantita, 0),
			IdUnitaMisura = ISNULL(m.IdUnitaMisura, 'KG'),
			ColliNumero = ISNULL(f.ColliNumero, ''),
			AllaRinfusa = ISNULL(f.AllaRinfusa, 0),

			IdAnalisiTipo = ISNULL(f.IdAnalisiTipo, '0'),
			AnalisiNumero = ISNULL(f.AnalisiNumero, ''),
			AnalisiData = f.AnalisiData,

			FormularioNote = ISNULL(f.Note, ''),
			UtenteNote = ISNULL(m.Note, ''),

			-- Autorizzazioni
			IdAutorizzazioneProduttoreDetentore = ISNULL(mp.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneDestinatario = ISNULL(md.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore1 = ISNULL(mt1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore2 = ISNULL(mt2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore3 = ISNULL(mt3.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario1 = ISNULL(mi1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario2 = ISNULL(mi2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario3 = ISNULL(mi3.IdAutorizzazione, REPLICATE('0', 16)),

			LuogoDiProduzione = ISNULL(f.LuogoDiProduzione, 0),
			Detentore = ISNULL(f.Detentore, 0),

			-- Trasporti
			DataInizioTrasporto = m.DataInizioTrasporto,
			IdTipoTrasporto1 = ISNULL(mt1.IdTipo, 'G'),
			IdTipoTrasporto2 = ISNULL(mt2.IdTipo, 'G'),
			IdTipoTrasporto3 = ISNULL(mt3.IdTipo, 'G'),

			-- Trasporto terreste (G)
			TargaMotrice = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.TargaMotrice, '') ELSE '' END,
			TargaRimorchio = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.TargaRimorchio, '') ELSE '' END,
			ConducenteNome = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.ConducenteNome, '') ELSE '' END,
			ConducenteCognome = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.ConducenteCognome, '') ELSE '' END,
			Percorso = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.Percorso, '') ELSE '' END,
			RimorchioPrecedente = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.RimorchioPrecedente, 0) ELSE 0 END,

			-- Trasporto marittimo (N)
			Nave = CASE WHEN mt1.IdTipo = 'N' THEN ISNULL(fn.Nave, '') ELSE '' END,
			Imdg = CASE WHEN mt1.IdTipo = 'N' THEN ISNULL(fn.Imdg, 0) ELSE 0 END,

			-- Trasporto ferroviario (T)
			Treno = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Treno, '') ELSE '' END,
			Tratta = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Tratta, '') ELSE '' END,
			Rid = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Rid, 0) ELSE 0 END,

			Lock = f.Lock
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			-- Produttori
			LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
			-- Destinatari
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			-- Trasportatori
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt3 ON m.Id = mt3.Id AND mt3.Pos = 2
			-- Intermediari
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi3 ON m.Id = mi3.Id AND mi3.Pos = 2
			-- Trasporti
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiTerresti fg ON f.Id = fg.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiMarittimi fn ON f.Id = fn.Id
			LEFT JOIN dbo.tblRifiutiFormulariTrasportiFerroviari ft ON f.Id = ft.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

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
GO

-- ===== sql\procedures\uspRifiutiFormulari_get_List.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL,
	@XfirAttesaAccettazione BIT = 0,
	@XfirCopiaNonCaricata BIT = 0,
	@XfirCopiaNonTrasmessa BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @Eer = dbo.ufnStringhe_get_SenzaSpazi(@Eer, 0, 1);
		SET @Formulario = dbo.ufnStringhe_get_SenzaSpazi(@Formulario, 0, 1);
		SET @Numeri = dbo.ufnStringhe_get_SenzaSpazi(@Numeri, 0, 1);
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage INT,
            @Offset      INT,
            @IdSessione  CHAR(16),
            @DallaData   DATE,
            @AllaData    DATE,
            @Soggetto    VARCHAR(50),
            @Eer         VARCHAR(50),
            @Formulario  VARCHAR(50),
            @Etichetta   VARCHAR(50)';

		-- FormularioNumero: spostato da tblRifiutiFormulari.Numero a tblRifiutiMovimenti.FormularioNumero
		SET @stmt = N'
        WITH tbl AS (
            SELECT
                Id                      = f.Id,
                StatoValore             = CASE WHEN f.Lock = 1 THEN 2 WHEN r.Id IS NULL THEN 1 ELSE 0 END,
                StatoDescrizione        = CASE WHEN f.Lock = 1 THEN ''Formulario non confermato'' WHEN r.Id IS NULL THEN ''Formulario non registrato'' ELSE ''OK'' END,
                FormularioNumero        = m.FormularioNumero,
                FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
                OperazioneNome          = op.Nome,
                EerNome                 = c.Nome,
                EerDescrizione          = c.Descrizione,
                StatoFisicoCodice       = s.Codice,
                StatoFisicoNome         = s.Nome,
                AttivitaRsCodice        = a.Codice,
                AttivitaRsNome          = a.Nome,
                RegistrazioneNumero     = r.Numero,
                RegistrazioneData       = r.[Data],
                ProduttoreDetentoreSede = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
                Trasportatore1Sede      = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
                DestinatarioSede        = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
                Intermediario1Sede      = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
                f.Etichette,
                IsRentriCollegato       = CAST(IIF(z.Id IS NOT NULL, 1, 0) AS BIT),
                r.RentriIdentificativo,
                r.RentriData,
                RentriFormularioStato   = m.RentriFormularioStato,
                RentriFormularioCartaceo = ISNULL(m.RentriFormularioCartaceo, 0),
                IsFormularioUnico       = CAST(ISNULL(op.IsFormularioUnico, 0) AS BIT),
                ViviFirVidimato         = CAST(ISNULL(m.ViviFirVidimato, 0) AS BIT),
                RowsCount               = COUNT(*) OVER ()
            FROM
                dbo.tblRifiutiFormulari                      f
                INNER JOIN dbo.tblRifiutiMovimenti           m  ON f.IdMovimento               = m.Id
                INNER JOIN dbo.tblRifiutiRegistri            g  ON m.IdRegistro                = g.Id
                INNER JOIN dbo.tblSessioni                   e  ON g.Id                        = e.IdRegistro
                INNER JOIN dbo.tblRifiutiOperazioni          op ON m.IdOperazione              = op.Id
                LEFT  JOIN dbo.tblRifiutiRegistrazioni       r  ON f.IdMovimento               = r.IdMovimento AND r.Lock < 2
                LEFT  JOIN dbo.tblRifiutiEer                 c  ON m.IdEer                     = c.Id
                LEFT  JOIN dbo.tblRifiutiStatiFisici         s  ON m.IdStatoFisico             = s.Id
                LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento
                                                             a  ON m.IdAttivita                = a.Id
                LEFT  JOIN dbo.tblSedi                       sp ON m.IdSedeProduttoreDetentore = sp.Id
                LEFT  JOIN dbo.tblSedi                       st ON m.IdSedeTrasportatore1      = st.Id
                LEFT  JOIN dbo.tblSedi                       sd ON m.IdSedeDestinatario        = sd.Id
                LEFT  JOIN dbo.tblSedi                       si ON m.IdSedeIntermediario1      = si.Id
                LEFT  JOIN dbo.tblRentriRegistri             z  ON g.Id                        = z.Id
            WHERE
                e.Id    = @IdSessione
                AND f.Lock < 2
                AND (@DallaData IS NULL OR ISNULL(f.DataEmissione, GETDATE()) >= @DallaData)
                AND (@AllaData  IS NULL OR ISNULL(f.DataEmissione, GETDATE()) <= @AllaData)';

		IF @Soggetto IS NOT NULL
		BEGIN
			IF @Ruolo = 'P'
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'T'
				SET @stmt = @stmt + N' AND (st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'D'
				SET @stmt = @stmt + N' AND (sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'I'
				SET @stmt = @stmt + N' AND (si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
		END

		-- Filtro numeri: filtra per numero di registrazione associata.
		-- I formulari senza registrazione (r.Numero IS NULL) vengono esclusi intenzionalmente.
		-- Eccezione documentata al divieto di concatenazione: solo interi puri vengono inseriti.
		IF @Numeri IS NOT NULL
		BEGIN
			IF @Numeri LIKE '[1-9]%-%[0-9]' AND @Numeri LIKE '%[1-9]-[0-9]%'
			BEGIN
				DECLARE @numeroInizio VARCHAR(20) = SUBSTRING(@Numeri, 1, CHARINDEX('-', @Numeri) - 1);
				DECLARE @numeroFine VARCHAR(20) = SUBSTRING(@Numeri, CHARINDEX('-', @Numeri) + 1, 20);
				IF TRY_CAST(@numeroInizio AS INT) IS NOT NULL AND TRY_CAST(@numeroFine AS INT) IS NOT NULL
					SET @stmt = @stmt + N' AND r.Numero BETWEEN ' + @numeroInizio + N' AND ' + @numeroFine;
			END
			ELSE IF TRY_CAST(@Numeri AS INT) IS NOT NULL
				SET @stmt = @stmt + N' AND r.Numero = ' + @Numeri;
		END

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N' AND f.Id IN ('
					  + N'    SELECT t.Id FROM dbo.tblRifiutiFormulariEtichette t'
					  + N'    INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id'
					  + N'    WHERE et.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		-- FormularioNumero ora su tblRifiutiMovimenti (alias m)
		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		-- I 3 flag sotto riguardano solo formulari con un xFIR RENTRI collegato (RentriFormularioStato
		-- valorizzato): altrimenti il filtro intercetterebbe anche i formulari cartacei, per i quali le
		-- date sotto sono banalmente NULL (stesso principio di uspRifiutiRegistrazioni_get_List).
		IF @XfirAttesaAccettazione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato = ''InserimentoAccettazione''';

		IF @XfirCopiaNonCaricata = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataCopia IS NULL';

		IF @XfirCopiaNonTrasmessa = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataTrasmissione IS NULL';

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.FormularioNumero, tbl.FormularioDataEmissione,
            tbl.OperazioneNome,
            tbl.EerNome, tbl.EerDescrizione,
            tbl.StatoFisicoCodice, tbl.StatoFisicoNome,
            tbl.AttivitaRsCodice, tbl.AttivitaRsNome,
            tbl.RegistrazioneNumero, tbl.RegistrazioneData,
            tbl.ProduttoreDetentoreSede, tbl.Trasportatore1Sede,
            tbl.DestinatarioSede, tbl.Intermediario1Sede,
            tbl.Etichette,
            tbl.IsRentriCollegato, tbl.RentriIdentificativo, tbl.RentriData, tbl.RentriFormularioStato, tbl.RentriFormularioCartaceo,
            tbl.IsFormularioUnico, tbl.ViviFirVidimato,
            tbl.RowsCount
        FROM tbl
        ORDER BY tbl.FormularioDataEmissione DESC, tbl.FormularioNumero DESC
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY
        OPTION (RECOMPILE);';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Soggetto = @Soggetto,
			@Eer = @Eer,
			@Formulario = @Formulario,
			@Etichetta = @Etichetta;

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

-- ===== sql\procedures\uspRifiutiFormulari_get_SediProduzione_List.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Indirizzi di intervento del formulario unico (art. 230, comma 5): una riga per indirizzo, nell'ordine del modello,
-- con il testo della sede come nella select (uspSedi_get_Sedi_SelectList) e la quantità stimata. Stessi controlli di
-- permesso e titolarità di uspRifiutiFormulari_get
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_get_SediProduzione_List]
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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				f.Id = @Id
				AND f.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Pos = ROW_NUMBER() OVER (ORDER BY ISNULL(p.Pos, 255), s.NomeCompleto),
			p.IdSede,
			SedeNome = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
			p.Quantita
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimentiSediProduzione p ON f.IdMovimento = p.Id
			INNER JOIN dbo.tblSedi s ON p.IdSede = s.Id
		WHERE f.Id = @Id
		ORDER BY Pos;

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
GO

-- ===== sql\procedures\uspRifiutiFormulari_get_ViviFirStampa.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "Vi.Vi.FIR - Stampa formulario unico" (Rifiuti/Formulari/Edit): controlli prima della stampa e credenziale dell'hub
-- dell'azienda del registro, con cui l'hub riscarica il PDF vidimato da Vi.Vi.FIR e ci scrive sopra i dati del
-- formulario letti da viewViviFirFormulari ([1_0_vivifir]..uspFormulario_get_Stampa).
-- exec dbo.uspRifiutiFormulari_get_ViviFirStampa @Id='...', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get_ViviFirStampa
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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità (stesso pattern di uspRifiutiFormulari_get), operazione e azienda interna del registro
		DECLARE @idMovimento CHAR(16);
		DECLARE @isFormularioUnico BIT;
		DECLARE @viviFirVidimato BIT;
		DECLARE @idAziendaInterna CHAR(16);
		SELECT
			@idMovimento = m.Id,
			@isFormularioUnico = ISNULL(o.IsFormularioUnico, 0),
			@viviFirVidimato = ISNULL(m.ViviFirVidimato, 0),
			@idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il formulario non esiste';
			GOTO BRANCH_END;
		END
		IF @isFormularioUnico = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Su Vi.Vi.FIR si stampa solo il formulario unico degli spurghisti (art. 230, comma 5)';
			GOTO BRANCH_END;
		END
		IF @viviFirVidimato = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario unico non è ancora vidimato su Vi.Vi.FIR: vidimarlo prima di stamparlo';
			GOTO BRANCH_END;
		END

		DECLARE @idViviFir CHAR(16);
		SELECT @idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenzialiAziende a
			INNER JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
		WHERE
			a.IdAziendaInterna = @idAziendaInterna
			AND c.Lock = 0;

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda del registro non ha una credenziale Vi.Vi.FIR: associarla in Vivifir > Aziende';
			GOTO BRANCH_END;
		END

		SELECT IdViviFir = @idViviFir;

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
GO

-- ===== sql\procedures\uspRifiutiFormulari_get_ViviFirVidimazione.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "Vi.Vi.FIR - Vidima formulario unico" (Rifiuti/Formulari/Edit): dati per chiedere all'hub Vi.Vi.FIR un nuovo numero
-- sul blocco dell'azienda del registro (Vivifir > Aziende, uspViviFirAziende_upd_Verifica). Tutti i controlli sul
-- formulario si fanno qui, prima della vidimazione, che non è annullabile: dopo, uspRifiutiFormulari_upd_ViviFirNumero
-- salva il numero con i soli controlli di permesso e titolarità.
-- exec dbo.uspRifiutiFormulari_get_ViviFirVidimazione @Id='...', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get_ViviFirVidimazione
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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF dbo.ufnModuli_get_IsAttivoBySessione('VVF', @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il modulo Vi.Vi.FIR non è attivo: il formulario unico non può essere vidimato';
			GOTO BRANCH_END;
		END

		-- Titolarità (stesso pattern di uspRifiutiFormulari_upd), operazione e azienda interna del registro
		DECLARE @idMovimento CHAR(16);
		DECLARE @isFormularioUnico BIT;
		DECLARE @viviFirVidimato BIT;
		DECLARE @formularioNumero VARCHAR(20);
		DECLARE @idAziendaInterna CHAR(16);
		SELECT
			@idMovimento = m.Id,
			@isFormularioUnico = ISNULL(o.IsFormularioUnico, 0),
			@viviFirVidimato = ISNULL(m.ViviFirVidimato, 0),
			@formularioNumero = m.FormularioNumero,
			@idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il formulario non esiste';
			GOTO BRANCH_END;
		END
		IF @isFormularioUnico = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Su Vi.Vi.FIR si vidima solo il formulario unico degli spurghisti (art. 230, comma 5)';
			GOTO BRANCH_END;
		END
		IF @viviFirVidimato = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = CONCAT('Il formulario ha già il numero vidimato su Vi.Vi.FIR ', @formularioNumero);
			GOTO BRANCH_END;
		END

		DECLARE @idViviFir CHAR(16);
		DECLARE @idSoggetto INT;
		DECLARE @blocco VARCHAR(10);
		SELECT
			@idViviFir = c.IdViviFir,
			@idSoggetto = a.IdSoggetto,
			@blocco = a.Blocco
		FROM
			dbo.tblViviFirCredenzialiAziende a
			INNER JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
		WHERE
			a.IdAziendaInterna = @idAziendaInterna
			AND c.Lock = 0;

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda del registro non ha una credenziale Vi.Vi.FIR: associarla in Vivifir > Aziende';
			GOTO BRANCH_END;
		END
		IF @idSoggetto IS NULL OR @blocco IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda del registro non ha un blocco Vi.Vi.FIR per il formulario unico: eseguire Verifica Vi.Vi.FIR in Vivifir > Aziende';
			GOTO BRANCH_END;
		END

		SELECT
			IdViviFir = @idViviFir,
			IdSoggetto = @idSoggetto,
			Blocco = @blocco;

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
GO

-- ===== sql\procedures\uspRifiutiFormulari_ins.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@IdModello CHAR(16) = NULL,
	@IdCopia CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
		SET @IdCopia = NULLIF(LTRIM(RTRIM(@IdCopia)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRegistroFinale CHAR(16);
		SELECT @idRegistroFinale = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- @IdRegistro esplicito (Copia/incolla su un Registro diverso da quello corrente di sessione) sovrascrive il default
		IF @IdRegistro IS NOT NULL
			SET @idRegistroFinale = @IdRegistro;

		IF @idRegistroFinale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro nel quale inserire il nuovo formulario';
			GOTO BRANCH_END;
		END

		IF @IdRegistro IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul modello
		IF @IdModello IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @IdModello)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il modello deve generare un vero Formulario (FIR): se dichiara un documento di trasporto
		-- alternativo (es. Allegato VII/I-B per trasporto transfrontaliero), da questo modello non
		-- può essere creato un Formulario
		IF @IdModello IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiModelli m
			WHERE
				m.Id = @IdModello
				AND m.IdTrasportoTransfrontalieroTipo IS NOT NULL
				AND m.IdTrasportoTransfrontalieroTipo <> 'F')
		BEGIN
			SET @returnValue = -1;
			SELECT @returnMessage = 'Il modello utilizza "' + t.Nome + '" come documento di trasporto: non può essere usato per generare un formulario'
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiDocumentiTrasportiTipi t ON t.Id = m.IdTrasportoTransfrontalieroTipo
			WHERE m.Id = @IdModello;
			GOTO BRANCH_END;
		END

		-- Titolarità sul formulario sorgente (Copia/incolla)
		IF @IdCopia IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				r.Id = @IdCopia
				AND r.Lock < 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Lettura unica del modello (era ripetuta fino a 17 volte più sotto, una per ogni campo/EXISTS):
		-- valorizzata solo se @IdModello è specificato, riusata da tutti gli INSERT del ramo sottostante
		DECLARE
			@mIdOperazione CHAR(1),
			@mIdUnitaMisura CHAR(2),
			@mIdEer CHAR(6),
			@mIdStatoFisico CHAR(1),
			@mIdAttivita CHAR(2),
			@mIdProvenienza CHAR(1),
			@mUtenteNote VARCHAR(500),
			@mIdAutorizzazioneProduttoreDetentore CHAR(16),
			@mIdAutorizzazioneDestinatario CHAR(16),
			@mIdAutorizzazioneTrasportatore1 CHAR(16),
			@mIdAutorizzazioneTrasportatore2 CHAR(16),
			@mIdAutorizzazioneTrasportatore3 CHAR(16),
			@mIdTipoTrasporto1 CHAR(1),
			@mIdTipoTrasporto2 CHAR(1),
			@mIdTipoTrasporto3 CHAR(1),
			@mIdAutorizzazioneIntermediario1 CHAR(16),
			@mIdAutorizzazioneIntermediario2 CHAR(16),
			@mIdAutorizzazioneIntermediario3 CHAR(16),
			@mIdImballo CHAR(2),
			@mAllaRinfusa BIT,
			@mIdAdr CHAR(2),
			@mTrasportoAdr BIT,
			@mNumeroOnu VARCHAR(20),
			@mAdrNote VARCHAR(200),
			@mIdAnalisiTipo CHAR(1),
			@mAnalisiNumero VARCHAR(50),
			@mAnalisiData DATE,
			@mLuogoDiProduzione BIT,
			@mDetentore BIT,
			@mFormularioNote VARCHAR(500);

		IF @IdModello IS NOT NULL
			SELECT
				@mIdOperazione = IdOperazione,
				@mIdUnitaMisura = IdUnitaMisura,
				@mIdEer = IdEer,
				@mIdStatoFisico = IdStatoFisico,
				@mIdAttivita = IdAttivita,
				@mIdProvenienza = IdProvenienza,
				@mUtenteNote = UtenteNote,
				@mIdAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore,
				@mIdAutorizzazioneDestinatario = IdAutorizzazioneDestinatario,
				@mIdAutorizzazioneTrasportatore1 = IdAutorizzazioneTrasportatore1,
				@mIdAutorizzazioneTrasportatore2 = IdAutorizzazioneTrasportatore2,
				@mIdAutorizzazioneTrasportatore3 = IdAutorizzazioneTrasportatore3,
				@mIdTipoTrasporto1 = IdTipoTrasporto1,
				@mIdTipoTrasporto2 = IdTipoTrasporto2,
				@mIdTipoTrasporto3 = IdTipoTrasporto3,
				@mIdAutorizzazioneIntermediario1 = IdAutorizzazioneIntermediario1,
				@mIdAutorizzazioneIntermediario2 = IdAutorizzazioneIntermediario2,
				@mIdAutorizzazioneIntermediario3 = IdAutorizzazioneIntermediario3,
				@mIdImballo = IdImballo,
				@mAllaRinfusa = AllaRinfusa,
				@mIdAdr = IdAdr,
				@mTrasportoAdr = TrasportoAdr,
				@mNumeroOnu = NumeroOnu,
				@mAdrNote = AdrNote,
				@mIdAnalisiTipo = IdAnalisiTipo,
				@mAnalisiNumero = AnalisiNumero,
				@mAnalisiData = AnalisiData,
				@mLuogoDiProduzione = LuogoDiProduzione,
				@mDetentore = Detentore,
				@mFormularioNote = FormularioNote
			FROM dbo.tblRifiutiModelli
			WHERE Id = @IdModello;

		-- Lettura unica del formulario sorgente per "Copia/incolla": stesso schema del blocco Modello sopra,
		-- ma dalla coppia Formulario/Movimento esistente invece che da un Modello. Esclusi di proposito:
		-- DataEmissione (analogo di "Data di registrazione"), VerificatoInPartenza (stato legato
		-- all'esecuzione fisica del trasporto), ColliNumero, FormularioNumero (su tblRifiutiMovimenti,
		-- mai impostato da _ins), le tabelle TrasportiFerroviari/Marittimi/Terresti (dati di esecuzione
		-- del trasporto reale) e, per costruzione, qualunque riferimento a tblRifiutiRegistrazioni*:
		-- la Registrazione eventualmente associata al formulario sorgente non deve mai essere copiata.
		DECLARE
			@cIdMovimentoOrigine CHAR(16),
			@cIdOperazione CHAR(1),
			@cIdUnitaMisura CHAR(2),
			@cIdEer CHAR(6),
			@cEerDescrizione VARCHAR(200),
			@cIdStatoFisico CHAR(1),
			@cIdAttivita CHAR(2),
			@cIdProvenienza CHAR(1),
			@cNote VARCHAR(500),
			@cIdAutorizzazioneProduttoreDetentore CHAR(16),
			@cIdAutorizzazioneDestinatario CHAR(16),
			@cIdAutorizzazioneTrasportatore1 CHAR(16),
			@cIdAutorizzazioneTrasportatore2 CHAR(16),
			@cIdAutorizzazioneTrasportatore3 CHAR(16),
			@cIdTipoTrasporto1 CHAR(1),
			@cIdTipoTrasporto2 CHAR(1),
			@cIdTipoTrasporto3 CHAR(1),
			@cIdAutorizzazioneIntermediario1 CHAR(16),
			@cIdAutorizzazioneIntermediario2 CHAR(16),
			@cIdAutorizzazioneIntermediario3 CHAR(16),
			@cIdImballo CHAR(2),
			@cAllaRinfusa BIT,
			@cIdAdr CHAR(2),
			@cTrasportoAdr BIT,
			@cNumeroOnu VARCHAR(20),
			@cAdrNote VARCHAR(200),
			@cIdAnalisiTipo CHAR(1),
			@cAnalisiNumero VARCHAR(50),
			@cAnalisiData DATE,
			@cLuogoDiProduzione BIT,
			@cDetentore BIT,
			@cFormularioNote VARCHAR(500);

		IF @IdCopia IS NOT NULL
			SELECT
				@cIdMovimentoOrigine = m.Id,
				@cIdOperazione = m.IdOperazione,
				@cIdUnitaMisura = m.IdUnitaMisura,
				@cIdEer = m.IdEer,
				@cEerDescrizione = m.EerDescrizione,
				@cIdStatoFisico = m.IdStatoFisico,
				@cIdAttivita = m.IdAttivita,
				@cIdProvenienza = m.IdProvenienza,
				@cNote = m.Note,
				@cIdAutorizzazioneProduttoreDetentore = p.IdAutorizzazione,
				@cIdAutorizzazioneDestinatario = d.IdAutorizzazione,
				@cIdAutorizzazioneTrasportatore1 = t1.IdAutorizzazione,
				@cIdTipoTrasporto1 = t1.IdTipo,
				@cIdAutorizzazioneTrasportatore2 = t2.IdAutorizzazione,
				@cIdTipoTrasporto2 = t2.IdTipo,
				@cIdAutorizzazioneTrasportatore3 = t3.IdAutorizzazione,
				@cIdTipoTrasporto3 = t3.IdTipo,
				@cIdAutorizzazioneIntermediario1 = i1.IdAutorizzazione,
				@cIdAutorizzazioneIntermediario2 = i2.IdAutorizzazione,
				@cIdAutorizzazioneIntermediario3 = i3.IdAutorizzazione,
				@cIdImballo = r.IdImballo,
				@cAllaRinfusa = r.AllaRinfusa,
				@cIdAdr = r.IdAdr,
				@cTrasportoAdr = r.TrasportoAdr,
				@cNumeroOnu = r.NumeroOnu,
				@cAdrNote = r.AdrNote,
				@cIdAnalisiTipo = r.IdAnalisiTipo,
				@cAnalisiNumero = r.AnalisiNumero,
				@cAnalisiData = r.AnalisiData,
				@cLuogoDiProduzione = r.LuogoDiProduzione,
				@cDetentore = r.Detentore,
				@cFormularioNote = r.Note
			FROM
				dbo.tblRifiutiFormulari r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori p ON m.Id = p.Id AND p.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari d ON m.Id = d.Id AND d.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t1 ON m.Id = t1.Id AND t1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t2 ON m.Id = t2.Id AND t2.Pos = 1
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t3 ON m.Id = t3.Id AND t3.Pos = 2
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i1 ON m.Id = i1.Id AND i1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i2 ON m.Id = i2.Id AND i2.Pos = 1
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i3 ON m.Id = i3.Id AND i3.Pos = 2
			WHERE r.Id = @IdCopia;

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @idMovimento CHAR(16);
		-- Genera l'Id del movimento FUORI dalla transazione: usato in tutti i rami IF/ELSE IF
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		BEGIN TRANSACTION;

			IF @IdOperazione IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione)
				VALUES
					(@idMovimento, @idRegistroFinale, @IdOperazione);

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, Lock)
				VALUES
					(@returnId, @idMovimento, 2);
			END
			ELSE IF @IdModello IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, IdStatoFisico, IdAttivita, IdProvenienza, Note)
				VALUES
					(@idMovimento, @idRegistroFinale, @mIdOperazione, @mIdUnitaMisura, @mIdEer, @mIdStatoFisico, @mIdAttivita, @mIdProvenienza, @mUtenteNote);

				IF @mIdAutorizzazioneProduttoreDetentore IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneProduttoreDetentore, 0);

				IF @mIdAutorizzazioneDestinatario IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneDestinatario, 0);

				IF @mIdAutorizzazioneTrasportatore1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore1, @mIdTipoTrasporto1, 0);

				IF @mIdAutorizzazioneTrasportatore2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore2, @mIdTipoTrasporto2, 1);

				IF @mIdAutorizzazioneTrasportatore3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore3, @mIdTipoTrasporto3, 2);

				IF @mIdAutorizzazioneIntermediario1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneIntermediario1, 0);

				IF @mIdAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneIntermediario2, 1);

				IF @mIdAutorizzazioneIntermediario3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneIntermediario3, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliClassiPericolo
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
					SELECT @idMovimento, IdClasse
					FROM dbo.tblRifiutiModelliClassiPericolo
					WHERE Id = @IdModello;

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, AllaRinfusa, IdAdr, TrasportoAdr, NumeroOnu, AdrNote, IdAnalisiTipo, AnalisiNumero, AnalisiData, LuogoDiProduzione, Detentore, Note, Lock)
				VALUES
					(@returnId, @idMovimento, @mIdImballo, @mAllaRinfusa, @mIdAdr, @mTrasportoAdr, @mNumeroOnu, @mAdrNote, @mIdAnalisiTipo, @mAnalisiNumero, @mAnalisiData, @mLuogoDiProduzione, @mDetentore, @mFormularioNote, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliEtichette
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
					SELECT @returnId, IdEtichetta
					FROM dbo.tblRifiutiModelliEtichette
					WHERE Id = @IdModello;
			END
			ELSE IF @IdCopia IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdProvenienza, Note)
				VALUES
					(@idMovimento, @idRegistroFinale, @cIdOperazione, @cIdUnitaMisura, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdAttivita, @cIdProvenienza, @cNote);

				IF @cIdAutorizzazioneProduttoreDetentore IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneProduttoreDetentore, 0);

				IF @cIdAutorizzazioneDestinatario IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneDestinatario, 0);

				IF @cIdAutorizzazioneTrasportatore1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore1, @cIdTipoTrasporto1, 0);

				IF @cIdAutorizzazioneTrasportatore2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore2, @cIdTipoTrasporto2, 1);

				IF @cIdAutorizzazioneTrasportatore3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore3, @cIdTipoTrasporto3, 2);

				IF @cIdAutorizzazioneIntermediario1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneIntermediario1, 0);

				IF @cIdAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneIntermediario2, 1);

				IF @cIdAutorizzazioneIntermediario3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneIntermediario3, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiClassiPericolo
				WHERE Id = @cIdMovimentoOrigine)
					INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
					SELECT @idMovimento, IdClasse
					FROM dbo.tblRifiutiMovimentiClassiPericolo
					WHERE Id = @cIdMovimentoOrigine;

				-- Indirizzi di intervento del formulario unico (art. 230, comma 5), con le quantità stimate
				INSERT dbo.tblRifiutiMovimentiSediProduzione (Id, IdSede, Quantita, Pos)
				SELECT @idMovimento, IdSede, Quantita, Pos
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE Id = @cIdMovimentoOrigine;

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, AllaRinfusa, IdAdr, TrasportoAdr, NumeroOnu, AdrNote, IdAnalisiTipo, AnalisiNumero, AnalisiData, LuogoDiProduzione, Detentore, Note, Lock)
				VALUES
					(@returnId, @idMovimento, @cIdImballo, @cAllaRinfusa, @cIdAdr, @cTrasportoAdr, @cNumeroOnu, @cAdrNote, @cIdAnalisiTipo, @cAnalisiNumero, @cAnalisiData, @cLuogoDiProduzione, @cDetentore, @cFormularioNote, 2);

				-- Nessuna copia delle tabelle Trasporti Ferroviari/Marittimi/Terresti (dati di esecuzione del
				-- trasporto reale) né di tblRifiutiRegistrazioni*: la Registrazione eventualmente associata al
				-- formulario sorgente non viene mai creata/copiata.
				INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
				SELECT @returnId, IdEtichetta
				FROM dbo.tblRifiutiFormulariEtichette
				WHERE Id = @IdCopia;
			END
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Parametro per Operazione, Modello o Copia non disponibile';
				GOTO BRANCH_END;
			END

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
GO

-- ===== sql\procedures\uspRifiutiFormulari_upd.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@VerificatoInPartenza BIT = 0,
	@IdAttivitaRs CHAR(2) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@FormularioDataEmissione DATE = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@IdTipoTrasporto1 CHAR(1) = NULL,
	@IdTipoTrasporto2 CHAR(1) = NULL,
	@IdTipoTrasporto3 CHAR(1) = NULL,
	@TargaMotrice VARCHAR(20) = NULL,
	@TargaRimorchio VARCHAR(20) = NULL,
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@RimorchioPrecedente BIT = 0,
	@Nave VARCHAR(50) = NULL,
	@Imdg BIT = 0,
	@Treno VARCHAR(50) = NULL,
	@Tratta VARCHAR(50) = NULL,
	@Rid BIT = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdAdr CHAR(2) = NULL,
	@NumeroOnu VARCHAR(20) = NULL,
	@TrasportoAdr BIT = 0,
	@AdrNote VARCHAR(200) = NULL,
	@IdImballo CHAR(2) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = NULL,
	@ColliNumero VARCHAR(50) = NULL,
	@AllaRinfusa BIT = 0,
	@IdAnalisiTipo CHAR(1) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData DATE = NULL,
	@LuogoDiProduzione BIT = 0,
	@Detentore BIT = 0,
	@Percorso VARCHAR(100) = NULL,
	@FormularioNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL,
	-- Indirizzi di intervento del formulario unico (art. 230, comma 5), JSON [{pos, idSede, quantita}]: si salvano
	-- solo per l'operazione con IsFormularioUnico, per le altre si cancellano
	@SediProduzione NVARCHAR(MAX) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: con un formulario attivo @IdDocumentoTrasportoTipo deve restare il Formulario; per un altro documento si cancella prima il formulario
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del
 formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizzazione parametri obbligatori
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
		IF @Quantita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Quantita non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione (via registro/sede) - stesso pattern di
		-- uspRifiutiFormulari_get. Senza questo controllo, chiunque avesse permesso
		-- RFR >= 2 poteva riscrivere il formulario (autorizzazioni, EER, quantità,
		-- trasportatori, ecc.) di un'altra azienda conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);
		DECLARE @minData DATE = '19000101';
		DECLARE @maxData DATE = '20501231';

		IF @FormularioDataEmissione >= @maxData SET @FormularioDataEmissione = NULL;
		IF @DataInizioTrasporto >= @maxData SET @DataInizioTrasporto = NULL;

		DECLARE @idMovimento CHAR(16);
		DECLARE @idRegistro CHAR(16);
		DECLARE @idRegistrazione CHAR(16);
		DECLARE @lock TINYINT;
		DECLARE @isRegistrazioneAssociata BIT;
		DECLARE @registrazioneData DATE;
		DECLARE @registrazioneNumero INT;
		DECLARE @idOperazione CHAR(1);
		DECLARE @totaleQuantitaAssegnata DECIMAL(18,2);
		DECLARE @idRelazione CHAR(16);
		DECLARE @quantitaRelazione DECIMAL(18,2);
		DECLARE @quantitaResidua DECIMAL(18,2);
		DECLARE @nessunaRegistrazioneAssociata BIT = 1;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @formularioRentriStato VARCHAR(40);
		DECLARE @rentriFormularioCartaceo BIT;

		-- Recupero dati formulario dalle tabelle base
		SELECT
			@idMovimento = f.IdMovimento,
			@idRegistro = m.IdRegistro,
			@idRegistrazione = r.Id,
			@lock = f.Lock,
			@idOperazione = m.IdOperazione,
			@isRegistrazioneAssociata = IIF(r.Id IS NOT NULL AND ISNULL(r.Lock, 8) < 2, 1, 0),
			@registrazioneData = r.[Data],
			@registrazioneNumero = r.Numero,
			@rentriIdentificativo = r.RentriIdentificativo,
			@rentriData = r.RentriData,
			@formularioRentriStato = m.RentriFormularioStato,
			@rentriFormularioCartaceo = ISNULL(m.RentriFormularioCartaceo, 0),
			@nessunaRegistrazioneAssociata = CASE
				WHEN EXISTS(
					SELECT 1
					FROM dbo.tblRifiutiRegistrazioniRelazioni rel
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON rel.Id = rr.Id
					WHERE
						rel.IdParent = r.Id
						AND rr.Lock < 2
				) THEN 0
				ELSE 1
			END
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		WHERE f.Id = @Id;

		-- Verifica che il formulario esista
		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		-- Se la registrazione associata è già stata trasmessa a RENTRI, il formulario non può più
		-- essere modificato (un formulario senza registrazione associata resta invece modificabile)
		IF @isRegistrazioneAssociata = 1 AND (@rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione associata è già stata inviata al RENTRI: il formulario non può più essere modificato';
			GOTO BRANCH_END;
		END

		-- Normalizzazione parametri CHAR opzionali
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdTipoTrasporto1 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto1)), '');
		SET @IdTipoTrasporto2 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto2)), '');
		SET @IdTipoTrasporto3 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto3)), '');
		SET @IdAdr = NULLIF(LTRIM(RTRIM(@IdAdr)), '');
		SET @IdImballo = NULLIF(LTRIM(RTRIM(@IdImballo)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');

		-- Autorizzazioni: azzera se è "nessuna" (SediciZeri)
		IF @IdAutorizzazioneProduttoreDetentore = @idSediciZeri SET @IdAutorizzazioneProduttoreDetentore = NULL;
		IF @IdAutorizzazioneDestinatario = @idSediciZeri SET @IdAutorizzazioneDestinatario = NULL;

		-- Autorizzazioni trasportatore: gestisce i valori delle 3 possibili autorizzazioni
		IF @IdAutorizzazioneTrasportatore1 = @idSediciZeri
			SET @IdAutorizzazioneTrasportatore1 = NULL;

		IF @IdAutorizzazioneTrasportatore2 = @idSediciZeri OR @IdAutorizzazioneTrasportatore1 IS NULL
			SET @IdAutorizzazioneTrasportatore2 = NULL;

		IF @IdAutorizzazioneTrasportatore3 = @idSediciZeri OR @IdAutorizzazioneTrasportatore2 IS NULL
			SET @IdAutorizzazioneTrasportatore3 = NULL;

		-- Autorizzazioni intermediario: gestisce i valori delle 3 possibili autorizzazioni
		IF @IdAutorizzazioneIntermediario1 = @idSediciZeri
			SET @IdAutorizzazioneIntermediario1 = NULL;

		IF @IdAutorizzazioneIntermediario2 = @idSediciZeri OR @IdAutorizzazioneIntermediario1 IS NULL
			SET @IdAutorizzazioneIntermediario2 = NULL;

		IF @IdAutorizzazioneIntermediario3 = @idSediciZeri OR @IdAutorizzazioneIntermediario2 IS NULL
			SET @IdAutorizzazioneIntermediario3 = NULL;

		IF @AllaRinfusa = 1 SET @IdImballo = NULL;
		IF @IdImballo = '00' SET @IdImballo = NULL;

		-- Normalizzazione parametri VARCHAR opzionali
		SET @ClassiPericolo = dbo.ufnStringhe_get_SenzaSpazi(@ClassiPericolo, 0, 1);
		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @ColliNumero = dbo.ufnStringhe_get_SenzaSpazi(@ColliNumero, 0, 1);
		SET @FormularioNote = dbo.ufnStringhe_get_SenzaSpazi(@FormularioNote, 0, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 0, 1);
		SET @IdEtichette = dbo.ufnStringhe_get_SenzaSpazi(@IdEtichette, 0, 1);

		-- Trasporto terrestre (G): tblRifiutiFormulariTrasportiTerresti
		IF @IdTipoTrasporto1 <> 'G'
		BEGIN
			SET @TargaMotrice = NULL;
			SET @TargaRimorchio = NULL;
			SET @ConducenteNome = NULL;
			SET @ConducenteCognome = NULL;
			SET @Percorso = NULL;
			SET @RimorchioPrecedente = 0;
		END
		ELSE
		BEGIN
			SET @TargaMotrice = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@TargaMotrice, 0, 1));
			SET @TargaRimorchio = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@TargaRimorchio, 0, 1));
			SET @ConducenteNome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteNome, 0, 1);
			SET @ConducenteCognome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteCognome, 0, 1);
			SET @Percorso = dbo.ufnStringhe_get_SenzaSpazi(@Percorso, 0, 1);
		END

		-- Trasporto marittimo (N): tblRifiutiFormulariTrasportiMarittimi
		IF @IdTipoTrasporto1 <> 'N'
		BEGIN
			SET @Nave = NULL;
			SET @Imdg = 0;
		END
		ELSE
			SET @Nave = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Nave, 0, 1));

		-- Trasporto ferroviario (T): tblRifiutiFormulariTrasportiFerroviari
		IF @IdTipoTrasporto1 <> 'T'
		BEGIN
			SET @Treno = NULL;
			SET @Tratta = NULL;
			SET @Rid = 0;
		END
		ELSE
		BEGIN
			SET @Treno = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Treno, 0, 1));
			SET @Tratta = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Tratta, 0, 1));
		END

		-- ADR
		IF @TrasportoAdr = 0
		BEGIN
			SET @IdAdr = NULL;
			SET @NumeroOnu = NULL;
			SET @AdrNote = NULL;
		END
		ELSE
		BEGIN
			IF @IdAdr = '00' SET @IdAdr = NULL;
			SET @NumeroOnu = dbo.ufnStringhe_get_SenzaSpazi(@NumeroOnu, 0, 1);
			SET @AdrNote = dbo.ufnStringhe_get_SenzaSpazi(@AdrNote, 0, 1);
		END

		-- Analisi
		IF @IdAnalisiTipo = '0'
		BEGIN
			SET @IdAnalisiTipo = NULL;
			SET @AnalisiNumero = NULL;
			SET @AnalisiData = NULL;
		END
		ELSE
		BEGIN
			SET @AnalisiNumero = dbo.ufnStringhe_get_SenzaSpazi(@AnalisiNumero, 0, 1);
		END

		-- Calcolo totale quantità assegnata (separato dal SELECT per leggere @nessunaRegistrazioneAssociata già valorizzata)
		IF @nessunaRegistrazioneAssociata = 0
			SELECT @totaleQuantitaAssegnata = ISNULL(SUM(lq.Quantita), 0)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni lq
				INNER JOIN dbo.tblRifiutiRegistrazioni rq ON lq.Id = rq.Id
			WHERE
				lq.IdParent = @idRegistrazione
				AND lq.Quantita > 0
				AND rq.Lock < 2;
		ELSE
			SET @totaleQuantitaAssegnata = 0;

		-- Controllo numero formulario duplicato
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			WHERE
				f.IdMovimento <> @idMovimento
				AND m.IdRegistro = @idRegistro
				AND f.Lock < 2
				AND m.FormularioNumero = @FormularioNumero
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro formulario con lo stesso numero è già presente';
			GOTO BRANCH_END;
		END

		-- Indirizzi di intervento del formulario unico (art. 230, comma 5): al massimo 10, come le righe del modello
		-- Albo-2022-A; le righe senza sede ("(Selezionare)") non si salvano. Sedi proponibili come nella select
		-- (uspSedi_get_Sedi_SelectList con il contesto del registro): quelle condivise nel dominio e quelle dell'azienda
		-- del registro, non disabilitate; una sede già salvata sul formulario resta valida
		DECLARE @isFormularioUnico BIT;
		SELECT @isFormularioUnico = ISNULL(IsFormularioUnico, 0)
		FROM dbo.tblRifiutiOperazioni
		WHERE Id = @idOperazione;

		DECLARE @elencoSediProduzione TABLE (
			Pos INT NULL,
			IdSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Quantita DECIMAL(18, 2) NULL
		);

		IF @isFormularioUnico = 1
		BEGIN
			IF ISJSON(ISNULL(@SediProduzione, N'[]')) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Elenco degli indirizzi di intervento non valido';
				GOTO BRANCH_END;
			END

			INSERT INTO @elencoSediProduzione (Pos, IdSede, Quantita)
			SELECT
				j.pos,
				NULLIF(NULLIF(LTRIM(RTRIM(j.idSede)), ''), @idSediciZeri),
				j.quantita
			FROM OPENJSON(ISNULL(@SediProduzione, N'[]'))
			WITH (
				pos INT,
				idSede CHAR(16),
				quantita DECIMAL(18, 2)
			) j;

			DELETE @elencoSediProduzione
			WHERE IdSede IS NULL;

			IF NOT EXISTS (SELECT 1
			FROM @elencoSediProduzione)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare almeno un indirizzo di intervento';
				GOTO BRANCH_END;
			END
			IF (SELECT COUNT(*)
			FROM @elencoSediProduzione) > 10
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Si possono indicare al massimo 10 indirizzi di intervento';
				GOTO BRANCH_END;
			END
			IF EXISTS (
				SELECT IdSede
				FROM @elencoSediProduzione
				GROUP BY IdSede
				HAVING COUNT(*) > 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Lo stesso indirizzo di intervento è indicato più volte';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1
			FROM @elencoSediProduzione
			WHERE Quantita <= 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità stimata di un indirizzo di intervento deve essere maggiore di zero';
				GOTO BRANCH_END;
			END

			DECLARE @idAziendaInterna CHAR(16);
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			WHERE g.Id = @idRegistro;

			DECLARE @sediAmmesse TABLE (
				Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
			);

			INSERT INTO @sediAmmesse (Id)
			SELECT DISTINCT u.Id
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
			WHERE
				e.Id = @IdSessione
				AND u.Disabilitata = 0
				AND
					(
						(
						u.IdDominio = e.IdDominio
						AND u.Condivisa = 1
						)
					OR u.IdAziendaInterna = @idAziendaInterna
					);

			INSERT INTO @sediAmmesse (Id)
			SELECT p.IdSede
			FROM
				dbo.tblRifiutiMovimentiSediProduzione p
				LEFT JOIN @sediAmmesse a ON p.IdSede = a.Id
			WHERE
				p.Id = @idMovimento
				AND a.Id IS NULL;

			IF EXISTS (
				SELECT 1
				FROM
					@elencoSediProduzione x
					LEFT JOIN @sediAmmesse a ON x.IdSede = a.Id
				WHERE a.Id IS NULL)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un indirizzo di intervento selezionato non è valido';
				GOTO BRANCH_END;
			END
		END

		-- Controllo EER/stato fisico/unità di misura nelle relazioni della registrazione associata
		IF @isRegistrazioneAssociata = 1 AND @nessunaRegistrazioneAssociata = 0 AND @idOperazione <> 'K'
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					-- Valori effettivi della registrazione associata (ultima rettifica di correzione
					-- confermata, l'originale non viene mai modificato - viewRifiutiRegistrazioniEffettive)
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					(
					l.Id = @idRegistrazione
					OR l.IdParent = @idRegistrazione
					)
					AND mp.IdOperazione <> 'M'
					AND
						(
						v.IdEer <> @IdEer
						OR v.IdStatoFisico <> @IdStatoFisico
						OR v.IdUnitaMisura <> @IdUnitaMisura
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione di questo formulario è associata ad altre con differente EER e/o stato fisico e/o unità di misura';
				GOTO BRANCH_END;
			END
		END


		-- Controllo quantità già scaricata (l.Id = @idRegistrazione: verifica che @idRegistrazione, come figlio, non scenda sotto quanto già scaricato dal padre)
		IF @isRegistrazioneAssociata = 1
		BEGIN
			IF @Quantita < ISNULL((
				SELECT SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
				WHERE
					l.Id = @idRegistrazione
					AND l.Quantita > 0
					AND rp.Lock < 2
					-- Uno scarico annullato non consuma piu' la registrazione (relazione mantenuta per la stampa)
					AND vp.IsAnnullata = 0
			), 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità non può essere inferiore a quella già associata ad altre registrazioni';
				GOTO BRANCH_END;
			END
		END

		 -- Verifica quantità superiore disponibile nella registrazione associata
		IF @isRegistrazioneAssociata = 1 AND @nessunaRegistrazioneAssociata = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiOperazioniRelazioni
			WHERE Id = @idOperazione)
			BEGIN
				IF dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore(
					@idRegistrazione, @Quantita, @registrazioneData, @registrazioneNumero,
					@IdEer, @IdStatoFisico, @IdUnitaMisura, 0) > 0
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'La quantità registrata è superiore a quella disponibile nelle registrazioni associate';
					GOTO BRANCH_END;
				END
			END
		END

		-- Verifica se necessario aggiornare il log
		DECLARE @aggiornaLog BIT = 0;
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000')
						OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0')
						OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00')
						OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '')
						OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0')
						OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0)
						OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData)
						)
			)
				SET @aggiornaLog = 1;
			ELSE IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp1 ON m.Id = mp1.Id AND mp1.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(mp1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneProduttoreDetentore, @idSediciZeri)
						OR ISNULL(md.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneDestinatario, @idSediciZeri)
						OR ISNULL(mt1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneTrasportatore1, @idSediciZeri)
						OR ISNULL(mi1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneIntermediario1, @idSediciZeri)
						)
			)
				SET @aggiornaLog = 1;
		END

		-- Calcola la soglia per la pulizia del log (fuori dalla transazione, intenzionale)
		-- Se ci sono 10 o meno record @dataLogMin resta NULL: il DELETE successivo non elimina nulla (comportamento corretto)
		DECLARE @dataLogMin DATETIME2(0);
		DECLARE @idUtente CHAR(16);

		IF @aggiornaLog = 1
		BEGIN
			SELECT TOP 1
				@dataLogMin = [Data]
			FROM (
				SELECT
					[Data],
					Pos = ROW_NUMBER() OVER (ORDER BY [Data] DESC)
				FROM dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento) t
			WHERE t.Pos > 9
			ORDER BY Pos;

			-- Lettura IdUtente fuori dalla transazione (intenzionale)
			SELECT @idUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		BEGIN TRANSACTION;

			-- Produttori
			DELETE dbo.tblRifiutiMovimentiProduttori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneProduttoreDetentore IS NOT NULL
			BEGIN
				IF EXISTS (SELECT 1
				FROM dbo.tblSedi
				WHERE Id = @IdAutorizzazioneProduttoreDetentore)
				BEGIN
					DECLARE @idSede CHAR(16) = @IdAutorizzazioneProduttoreDetentore;
					SET @IdAutorizzazioneProduttoreDetentore = NULL;

					SELECT @IdAutorizzazioneProduttoreDetentore = Id
					FROM dbo.tblRifiutiAutorizzazioni
					WHERE
						IdSede = @idSede
						AND Nessuna = 1
						AND Lock = 0;

					IF @IdAutorizzazioneProduttoreDetentore IS NULL
					BEGIN
						EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @IdAutorizzazioneProduttoreDetentore OUTPUT;

						INSERT dbo.tblRifiutiAutorizzazioni
							(Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
						VALUES
							(@IdAutorizzazioneProduttoreDetentore, @idSede, 'P', @minData, @maxData, 1, 0, 0);
					END
				END

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneProduttoreDetentore, @Quantita, 0);
			END

			-- Destinatari
			DELETE dbo.tblRifiutiMovimentiDestinatari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneDestinatario IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneDestinatario, 0);
			END

			-- Trasportatori
			DELETE dbo.tblRifiutiMovimentiTrasportatori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneTrasportatore1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneTrasportatore1, @IdTipoTrasporto1, 0);

				IF @IdAutorizzazioneTrasportatore2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneTrasportatore2, @IdTipoTrasporto2, 1);

					IF @IdAutorizzazioneTrasportatore3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneTrasportatore3, @IdTipoTrasporto3, 2);
					END
				END
			END

			-- Trasporto (dettaglio per tipo, tabelle satellite del formulario)
			DELETE dbo.tblRifiutiFormulariTrasportiTerresti
			WHERE Id = @Id;
			DELETE dbo.tblRifiutiFormulariTrasportiMarittimi
			WHERE Id = @Id;
			DELETE dbo.tblRifiutiFormulariTrasportiFerroviari
			WHERE Id = @Id;

			IF @IdTipoTrasporto1 = 'G'
				INSERT dbo.tblRifiutiFormulariTrasportiTerresti
					(Id, TargaMotrice, TargaRimorchio, ConducenteNome, ConducenteCognome, Percorso, RimorchioPrecedente)
				VALUES
					(@Id, @TargaMotrice, @TargaRimorchio, @ConducenteNome, @ConducenteCognome, @Percorso, @RimorchioPrecedente);
			ELSE IF @IdTipoTrasporto1 = 'N'
				INSERT dbo.tblRifiutiFormulariTrasportiMarittimi (Id, Nave, Imdg)
				VALUES (@Id, @Nave, @Imdg);
			ELSE IF @IdTipoTrasporto1 = 'T'
				INSERT dbo.tblRifiutiFormulariTrasportiFerroviari (Id, Treno, Tratta, Rid)
				VALUES (@Id, @Treno, @Tratta, @Rid);

			-- Intermediari
			DELETE dbo.tblRifiutiMovimentiIntermediari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneIntermediario1, 0);

				IF @IdAutorizzazioneIntermediario2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneIntermediario2, 1);

					IF @IdAutorizzazioneIntermediario3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneIntermediario3, 2);
					END
				END
			END

			-- Classi di pericolo
			DELETE dbo.tblRifiutiMovimentiClassiPericolo
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT @idMovimento, c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Indirizzi di intervento del formulario unico (nessuno per le altre operazioni), numerati da 1 nell'ordine
			-- ricevuto
			DELETE dbo.tblRifiutiMovimentiSediProduzione
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiSediProduzione (Id, IdSede, Quantita, Pos)
			SELECT
				@idMovimento,
				IdSede,
				Quantita,
				ROW_NUMBER() OVER (ORDER BY ISNULL(Pos, 255))
			FROM @elencoSediProduzione;

			-- Etichette formulario
			DELETE dbo.tblRifiutiFormulariEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
			SELECT TOP 3 @Id, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			-- Aggiorna le quantità delle registrazioni in relazione carico/scarico
			IF @Quantita = 0 OR @nessunaRegistrazioneAssociata = 1
			BEGIN
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @idRegistrazione;
			END

			IF @nessunaRegistrazioneAssociata = 0 AND @Quantita > 0 AND @Quantita <> @totaleQuantitaAssegnata
			BEGIN
				UPDATE dbo.tblRifiutiRegistrazioniRelazioni
				SET Quantita = 0
				WHERE IdParent = @idRegistrazione;

				SET @quantitaRelazione = @Quantita;

				-- Distribuzione quantità sulle relazioni ordinate per Pos
				DECLARE c CURSOR FAST_FORWARD FOR
					SELECT
						l.Id,
						-- Valori effettivi (viewRifiutiRegistrazioniEffettive): quantita' dell'ultima correzione
						-- confermata, 0 se annullata; uno scarico annullato non consuma piu' i suoi carichi
						QuantitaResidua = v2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v2 ON r.Id = v2.Id
						LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
								INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
								INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vpq ON pq.Id = vpq.Id
							WHERE
								pq.Lock < 2
								AND vpq.Quantita > 0
							GROUP BY lq.Id
						) a ON l.Id = a.Id
					WHERE l.IdParent = @idRegistrazione
					ORDER BY l.Pos;

				OPEN c;
				FETCH c INTO @idRelazione, @quantitaResidua;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @quantitaRelazione > 0
					BEGIN
						IF @quantitaRelazione >= @quantitaResidua
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaResidua
							WHERE
								IdParent = @idRegistrazione
								AND Id = @idRelazione;
							SET @quantitaRelazione = @quantitaRelazione - @quantitaResidua;
						END
						ELSE
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaRelazione
							WHERE
								IdParent = @idRegistrazione
								AND Id = @idRelazione;
							SET @quantitaRelazione = 0;
						END
					END
					FETCH c INTO @idRelazione, @quantitaResidua;
				END

				CLOSE c;
				DEALLOCATE c;
			END

			DELETE dbo.tblRifiutiRegistrazioniRelazioni
			WHERE
				IdParent = @idRegistrazione
				AND Quantita = 0;

			-- Aggiornamento log storico movimento (snapshot stato corrente prima degli UPDATE)
			-- @dataLogMin = NULL se <= 10 record: il DELETE non elimina nulla (comportamento corretto)
			IF @aggiornaLog = 1
			BEGIN
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND [Data] <= @dataLogMin;

				INSERT dbo.tblRifiutiMovimentiLog
					(Id, [Data], IdUtente,
					 IdEer, IdStatoFisico, IdMateriale, IdAttivita, IdUnitaMisura,
					 Quantita, QuantitaVerificata, IdAutorizzazioneProduttoreDetentore, IdAutorizzazioneDestinatario,
					 IdAutorizzazioneTrasportatore1, IdAutorizzazioneIntermediario1,
					 RegistrazioneNumero, RegistrazioneData, FormularioNumero, DataInizioTrasporto, DataFineTrasporto)
				SELECT
					m.Id, GETDATE(), @idUtente,
					m.IdEer, m.IdStatoFisico, r.IdMateriale, m.IdAttivita, m.IdUnitaMisura,
					m.Quantita, r.QuantitaVerificata, mp.IdAutorizzazione, md.IdAutorizzazione,
					mt.IdAutorizzazione, mi.IdAutorizzazione,
					r.Numero, r.[Data], m.FormularioNumero, m.DataInizioTrasporto, r.DataFineTrasporto
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				WHERE m.Id = @idMovimento;
			END

			-- Aggiornamento formulario
			UPDATE dbo.tblRifiutiFormulari
			SET
				DataEmissione = @FormularioDataEmissione,
				Note = @FormularioNote,
				IdAdr = @IdAdr,
				NumeroOnu = @NumeroOnu,
				TrasportoAdr = @TrasportoAdr,
				AdrNote = @AdrNote,
				IdImballo = @IdImballo,
				ColliNumero = @ColliNumero,
				AllaRinfusa = @AllaRinfusa,
				VerificatoInPartenza = @VerificatoInPartenza,
				Etichette = dbo.ufnRifiutiFormulari_get_Etichette(Id),
				IdAnalisiTipo = @IdAnalisiTipo,
				AnalisiNumero = @AnalisiNumero,
				AnalisiData = @AnalisiData,
				LuogoDiProduzione = @LuogoDiProduzione,
				Detentore = @Detentore,
				Lock = 0
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Formulario non trovato o già modificato da un altro utente';
				GOTO BRANCH_END;
			END

			-- Aggiornamento movimento
			UPDATE m
			SET
				IdEer = @IdEer,
				IdProvenienza = @IdProvenienza,
				IdStatoFisico = @IdStatoFisico,
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				Quantita = @Quantita,
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede,
				-- Una volta creato il formulario digitale su RENTRI (RentriStato valorizzato), il numero
				-- non puo' piu' essere modificato dall'utente - mantiene il valore gia' a DB
				-- indipendentemente da @FormularioNumero (non blocca l'intero update, solo questo campo:
				-- gli altri dati restano modificabili e sincronizzabili su RENTRI via "Modifica").
				-- Lo stesso vale per il numero vidimato con "RENTRI - Crea formulario cartaceo" e per quello
				-- del formulario unico vidimato su Vi.Vi.FIR.
				FormularioNumero = CASE WHEN @formularioRentriStato IS NOT NULL OR @rentriFormularioCartaceo = 1 OR ISNULL(m.ViviFirVidimato, 0) = 1 THEN m.FormularioNumero ELSE @FormularioNumero END,
				DataInizioTrasporto = @DataInizioTrasporto,
				Note = @UtenteNote
			FROM
				dbo.tblRifiutiMovimenti m
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON mp.IdAutorizzazione = ap.Id
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON md.IdAutorizzazione = ad.Id
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON mt.IdAutorizzazione = ar.Id
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON mi.IdAutorizzazione = ai.Id
			WHERE m.Id = @idMovimento;

			-- Magazzino EoW allineato al registro operativo: la quantita' del movimento e' anche quella della
			-- registrazione associata, se e' una M con allocazioni queste si adeguano
			IF @idRegistrazione IS NOT NULL
				EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idRegistrazione;

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione (intenzionale)
		IF @lock > 0 OR @aggiornaLog = 1
		BEGIN
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
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

	SELECT ReturnValue = @returnValue;
END;
GO
GO

-- ===== sql\procedures\uspRifiutiFormulari_upd_ViviFirNumero.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "Vi.Vi.FIR - Vidima formulario unico" (Rifiuti/Formulari/Edit): salva sul movimento il numero appena vidimato su
-- Vi.Vi.FIR (hub 1_0_ViviFirApi, POST /formulari/vidima) e lo marca con ViviFirVidimato = 1, che blocca il numero e non
-- fa più proporre la vidimazione. Come uspRifiutiFormulari_upd_FormularioNumero per il cartaceo RENTRI, l'hub non
-- conosce il formulario e il numero lo scrive l'app. Chiamata DOPO la vidimazione, che non è annullabile: per non
-- perdere il numero i controlli sono solo permesso e titolarità; quelli sul formulario li fa
-- uspRifiutiFormulari_get_ViviFirVidimazione prima di vidimare.
-- exec dbo.uspRifiutiFormulari_upd_ViviFirNumero @Id='...', @FormularioNumero='ZTKB 000004 M', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_upd_ViviFirNumero
	@Id CHAR(16) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @aggiornati INT = 0;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @FormularioNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @FormularioNumero non può essere vuoto';
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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità (stesso pattern di uspRifiutiFormulari_upd)
		DECLARE @idMovimento CHAR(16);
		SELECT @idMovimento = m.Id
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il formulario non esiste';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRifiutiMovimenti
		SET
			FormularioNumero = @FormularioNumero,
			ViviFirVidimato = 1
		WHERE Id = @idMovimento;

		SET @aggiornati = @@ROWCOUNT;

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

	SELECT Aggiornati = @aggiornati;
END;
GO
GO

-- ===== sql\procedures\uspRifiutiLimiti_get_Operazioni_List.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_get_Operazioni_List]
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
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul limite padre
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiLimiti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'operazione del formulario unico (art. 230, comma 5) solo con il modulo Vi.Vi.FIR (VVF) attivo, o se il
		-- limite la comprende già
		DECLARE @isViviFir BIT = IIF(dbo.ufnModuli_get_IsAttivoBySessione('VVF', @IdSessione) = 1, 1, 0);

		SELECT
			o.Id,
			[Text] = o.Nome,
			Checked = CAST(IIF(sel.IdOperazione IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblRifiutiOperazioni o
			LEFT JOIN (
				SELECT IdOperazione
				FROM dbo.tblRifiutiLimitiOperazioni
				WHERE IdLimite = @Id) sel ON o.Id = sel.IdOperazione
		WHERE
			ISNULL(o.IsFormularioUnico, 0) = 0
			OR @isViviFir = 1
			OR sel.IdOperazione IS NOT NULL
		ORDER BY
			o.Pos, o.Nome;

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
GO

-- ===== sql\procedures\uspRifiutiMovimenti_ins_DaAcquisizioneFormulario.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Crea, in un'unica transazione, la bozza (Lock=2) di una Registrazione o di un Formulario a partire dai
-- dati di un formulario digitale RENTRI ("RENTRI - Acquisisci da formulario digitale", Rifiuti/Registrazioni
-- e Rifiuti/Formulari) - stesso ruolo della SP legacy 3.1 uspRifiutiSchede_ins_ImportazioneFormularioDigitale,
-- riscritta sullo schema 4.0. @ModalitaRitorno ('R'/'F') decide quale sola entità creare (mai entrambe:
-- in 4.0 Registrazioni e Formulari sono percorsi di creazione separati, a differenza della legacy).
--
-- Risoluzione FK/lookup interamente qui dentro, riusando le SP già esistenti invece di duplicarne la
-- logica: uspRifiutiAutorizzazioni_get_MatchImportazione (Produttore/Destinatario/Trasportatore/
-- Intermediario per Codice Fiscale) e uspRifiutiRegistrazioni_get_MatchCodiciImportazione (stato
-- fisico/attività R-D/esito/causale respingimento/analisi/ADR/unità di misura). Nessun match trovato -> il
-- relativo campo resta NULL, l'utente completa a mano da Edit.
--
-- La bozza risultante (Lock=2) segue esattamente lo stesso ciclo di vita di "Nuova registrazione"/"Nuovo
-- formulario": se l'utente preme Annulla in Edit, uspRifiutiRegistrazioni_del/uspRifiutiFormulari_del la
-- cancellano (hard delete, verificato che coprano tutte le tabelle popolate qui); se preme Salva, il
-- normale uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd la finalizza con tutte le sue validazioni.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_ins_DaAcquisizioneFormulario]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@ModalitaRitorno CHAR(1) = NULL, -- 'R' Registrazione, 'F' Formulario

	@Numero VARCHAR(20) = NULL,
	@Stato VARCHAR(40) = NULL,
	@DataEmissione DATE = NULL,
	@Esito VARCHAR(5) = NULL,
	@EsitoCausaleRespingimento VARCHAR(5) = NULL,
	@RespingimentoMotivo VARCHAR(500) = NULL,
	@DataOraFineTrasporto DATETIME2(0) = NULL,
	@Eer CHAR(6) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@StatoFisico VARCHAR(5) = NULL,
	@ClassiPericolo VARCHAR(200) = NULL,
	@Provenienza CHAR(1) = NULL,
	@Quantita DECIMAL(18, 3) = NULL,
	@QuantitaDestino DECIMAL(18, 3) = NULL,
	@UnitaMisura VARCHAR(5) = NULL,
	@Note VARCHAR(500) = NULL,

	@ProduttoreAutorizzazione VARCHAR(20) = NULL,
	@ProduttoreCodiceFiscale VARCHAR(20) = NULL,
	@DestinatarioAutorizzazione VARCHAR(20) = NULL,
	@DestinatarioCodiceFiscale VARCHAR(20) = NULL,
	@TrasportatoreAutorizzazioneAlbo VARCHAR(20) = NULL,
	@TrasportatoreCodiceFiscale VARCHAR(20) = NULL,
	@IntermediarioAutorizzazioneAlbo VARCHAR(20) = NULL,
	@IntermediarioCodiceFiscale VARCHAR(20) = NULL,
	@Intermediario2AutorizzazioneAlbo VARCHAR(20) = NULL,
	@Intermediario2CodiceFiscale VARCHAR(20) = NULL,

	@Destinazione VARCHAR(5) = NULL,
	@DataOraInizioTrasporto VARCHAR(20) = NULL, -- "yyyy-MM-dd HH:mm", come restituito dall'hub
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@TargaMotrice VARCHAR(10) = NULL,
	@TargaRimorchio VARCHAR(10) = NULL,
	@Percorso VARCHAR(200) = NULL,
	@Colli VARCHAR(50) = NULL,
	@NumeroONU VARCHAR(20) = NULL,
	@ClasseADR VARCHAR(5) = NULL,
	@AdrNote VARCHAR(200) = NULL,
	@Analisi VARCHAR(20) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData VARCHAR(20) = NULL,
	@QuantitaVerificataPartenza BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @returnId CHAR(16) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @ModalitaRitorno = NULLIF(LTRIM(RTRIM(@ModalitaRitorno)), '');
		SET @Numero = NULLIF(UPPER(LTRIM(RTRIM(@Numero))), '');
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @EerDescrizione = NULLIF(LTRIM(RTRIM(@EerDescrizione)), '');
		SET @ClassiPericolo = NULLIF(LTRIM(RTRIM(@ClassiPericolo)), '');
		SET @Note = NULLIF(LTRIM(RTRIM(@Note)), '');
		SET @RespingimentoMotivo = NULLIF(LTRIM(RTRIM(@RespingimentoMotivo)), '');
		SET @ConducenteNome = NULLIF(LTRIM(RTRIM(@ConducenteNome)), '');
		SET @ConducenteCognome = NULLIF(LTRIM(RTRIM(@ConducenteCognome)), '');
		SET @TargaMotrice = NULLIF(LTRIM(RTRIM(@TargaMotrice)), '');
		SET @TargaRimorchio = NULLIF(LTRIM(RTRIM(@TargaRimorchio)), '');
		SET @Percorso = NULLIF(LTRIM(RTRIM(@Percorso)), '');
		SET @NumeroONU = NULLIF(LTRIM(RTRIM(@NumeroONU)), '');
		SET @AdrNote = NULLIF(LTRIM(RTRIM(@AdrNote)), '');
		SET @AnalisiNumero = NULLIF(LTRIM(RTRIM(@AnalisiNumero)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @ModalitaRitorno NOT IN ('R', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @ModalitaRitorno deve essere ''R'' o ''F''';
			GOTO BRANCH_END;
		END
		IF @Numero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Numero formulario non valorizzato';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		DECLARE @idFunzionePermesso CHAR(3) = IIF(@ModalitaRitorno = 'F', 'RFR', 'RRG');
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzionePermesso,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE
			@operazione CHAR(1), @isProduttore BIT, @isTrasportatore BIT, @isDestinatario BIT,
			@isIntermediario BIT, @isEsito BIT, @isAttivitaRs BIT, @isIntegrazioneFir BIT, @isFormulario BIT,
			@isFormularioUnico BIT;
		SELECT
			@operazione = Operazione, @isProduttore = IsProduttore, @isTrasportatore = IsTrasportatore,
			@isDestinatario = IsDestinatario, @isIntermediario = IsIntermediario, @isEsito = IsEsito,
			@isAttivitaRs = IsAttivitaRs, @isIntegrazioneFir = IsIntegrazioneFir, @isFormulario = IsFormulario,
			@isFormularioUnico = ISNULL(IsFormularioUnico, 0)
		FROM dbo.tblRifiutiOperazioni
		WHERE Id = @IdOperazione;

		IF @operazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Causale non valida';
			GOTO BRANCH_END;
		END
		-- Il formulario unico degli spurghisti (art. 230, comma 5) si vidima su Vi.Vi.FIR: un FIR del RENTRI non lo diventa
		IF (@ModalitaRitorno = 'R' AND ISNULL(@isIntegrazioneFir, 0) = 0) OR (@ModalitaRitorno = 'F' AND ISNULL(@isFormulario, 0) = 0)
			OR @isFormularioUnico = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è valida per l''acquisizione da formulario digitale';
			GOTO BRANCH_END;
		END

		-- Duplicato: stesso numero di formulario già presente e attivo nel registro, scopato alla sola
		-- entità della modalità corrente (Registrazioni e Formulari sono percorsi di acquisizione
		-- indipendenti: lo stesso FIR può esistere come Registrazione e, separatamente, come Formulario)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiMovimenti m
			WHERE
				m.IdRegistro = @IdRegistro
				AND m.FormularioNumero = @Numero
				AND
					(
						(
						@ModalitaRitorno = 'R'
						AND EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.IdMovimento = m.Id AND r.Lock < 2)
						)
					OR
						(
						@ModalitaRitorno = 'F'
						AND EXISTS (SELECT 1 FROM dbo.tblRifiutiFormulari f WHERE f.IdMovimento = m.Id AND f.Lock < 2)
						)
					)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra registrazione o formulario con lo stesso numero di formulario è già presente in questo registro';
			GOTO BRANCH_END;
		END

		-- ── Risoluzione FK/lookup, riusando le SP dedicate già esistenti ─────────────────────
		CREATE TABLE #match (
			IdAutorizzazioneProduttoreDetentore CHAR(16) NULL,
			IdAutorizzazioneDestinatario CHAR(16) NULL,
			IdAutorizzazioneTrasportatore1 CHAR(16) NULL,
			IdAutorizzazioneIntermediario1 CHAR(16) NULL,
			IdAutorizzazioneIntermediario2 CHAR(16) NULL
		);
		INSERT #match
		EXEC dbo.uspRifiutiAutorizzazioni_get_MatchImportazione
			@IdSessione = @IdSessione, @IdRegistro = @IdRegistro,
			@ProduttoreCodiceFiscale = @ProduttoreCodiceFiscale, @ProduttoreAutorizzazione = @ProduttoreAutorizzazione,
			@DestinatarioCodiceFiscale = @DestinatarioCodiceFiscale, @DestinatarioAutorizzazione = @DestinatarioAutorizzazione,
			@TrasportatoreCodiceFiscale = @TrasportatoreCodiceFiscale, @TrasportatoreAutorizzazione = @TrasportatoreAutorizzazioneAlbo,
			@IntermediarioCodiceFiscale = @IntermediarioCodiceFiscale, @IntermediarioAutorizzazione = @IntermediarioAutorizzazioneAlbo,
			@Intermediario2CodiceFiscale = @Intermediario2CodiceFiscale, @Intermediario2Autorizzazione = @Intermediario2AutorizzazioneAlbo;

		CREATE TABLE #codici (
			IdStatoFisico CHAR(1) NULL,
			IdAttivitaRs CHAR(2) NULL,
			IdAnalisiTipo CHAR(1) NULL,
			IdAdr CHAR(2) NULL,
			IdUnitaMisura CHAR(2) NULL,
			IdEsito CHAR(1) NULL,
			IdCausaleRespingimento CHAR(1) NULL
		);
		INSERT #codici
		EXEC dbo.uspRifiutiRegistrazioni_get_MatchCodiciImportazione
			@StatoFisicoCodice = @StatoFisico, @AttivitaRsCodice = @Destinazione, @AnalisiTipoCodice = @Analisi,
			@AdrCodice = @ClasseADR, @UnitaMisuraCodice = @UnitaMisura, @EsitoCodice = @Esito,
			@CausaleRespingimentoCodice = @EsitoCausaleRespingimento;

		DECLARE
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idAnalisiTipo CHAR(1), @idAdr CHAR(2), @idUnitaMisura CHAR(2),
			@idEsito CHAR(1), @idCausaleRespingimento CHAR(1);
		SELECT TOP 1
			@idAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore,
			@idAutorizzazioneDestinatario = IdAutorizzazioneDestinatario,
			@idAutorizzazioneTrasportatore1 = IdAutorizzazioneTrasportatore1,
			@idAutorizzazioneIntermediario1 = IdAutorizzazioneIntermediario1,
			@idAutorizzazioneIntermediario2 = IdAutorizzazioneIntermediario2
		FROM #match;
		SELECT TOP 1
			@idStatoFisico = IdStatoFisico, @idAttivitaRs = IdAttivitaRs, @idAnalisiTipo = IdAnalisiTipo,
			@idAdr = IdAdr, @idUnitaMisura = IdUnitaMisura, @idEsito = IdEsito, @idCausaleRespingimento = IdCausaleRespingimento
		FROM #codici;

		-- Autorizzazioni non applicabili al ruolo dell'operazione: azzerate, stesso principio di
		-- uspRifiutiRegistrazioni_upd (righe "IF @isProduttore = 0 ... SET NULL")
		IF ISNULL(@isProduttore, 0) = 0 SET @idAutorizzazioneProduttoreDetentore = NULL;
		IF ISNULL(@isDestinatario, 0) = 0 SET @idAutorizzazioneDestinatario = NULL;
		IF ISNULL(@isTrasportatore, 0) = 0 SET @idAutorizzazioneTrasportatore1 = NULL;
		IF ISNULL(@isIntermediario, 0) = 0
		BEGIN
			SET @idAutorizzazioneIntermediario1 = NULL;
			SET @idAutorizzazioneIntermediario2 = NULL;
		END
		IF ISNULL(@isEsito, 0) = 0
		BEGIN
			SET @idEsito = NULL;
			SET @idCausaleRespingimento = NULL;
			SET @RespingimentoMotivo = NULL;
		END
		IF ISNULL(@isAttivitaRs, 0) = 0 SET @idAttivitaRs = NULL;

		-- ── Normalizzazione quantità/date con sentinella (stesso principio della legacy) ─────
		DECLARE @quantitaFinale DECIMAL(18, 3) = IIF(@Quantita >= 0, @Quantita, 0);
		DECLARE @quantitaVerificataFinale DECIMAL(18, 3) = IIF(@QuantitaDestino >= 0, @QuantitaDestino, NULL);

		DECLARE @dataOraInizioTrasportoFinale DATETIME2(0) = TRY_CAST(@DataOraInizioTrasporto AS DATETIME2(0));
		IF @dataOraInizioTrasportoFinale >= '20500101' SET @dataOraInizioTrasportoFinale = NULL;

		IF @DataOraFineTrasporto >= '20500101' SET @DataOraFineTrasporto = NULL;

		DECLARE @dataEmissioneFinale DATE = IIF(ISNULL(@DataEmissione, '19000101') < '20000101', CAST(GETDATE() AS DATE), @DataEmissione);

		DECLARE @analisiDataFinale DATE = TRY_CAST(@AnalisiData AS DATE);

		-- Data di registrazione proposta: sempre quella odierna (non le date del trasporto del FIR)
		DECLARE @registrazioneData DATE = CAST(GETDATE() AS DATE);

		CREATE TABLE #numero (Rtn INT);
		INSERT #numero EXEC dbo.uspRifiutiRegistrazioni_get_UltimoNumero @IdRegistro = @IdRegistro, @Data = @registrazioneData, @IdSessione = @IdSessione;
		DECLARE @registrazioneNumero INT = (SELECT TOP 1 Rtn + 1 FROM #numero);

		-- ── Creazione ─────────────────────────────────────────────────────────────────────
		DECLARE @idMovimento CHAR(16), @idRegistrazione CHAR(16), @idFormulario CHAR(16);

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		-- Produttore senza autorizzazioni: uspRifiutiAutorizzazioni_get_MatchImportazione (passo 3) restituisce
		-- l'Id della Sede, che va convertito nell'autorizzazione "Nessuna" della sede, creata se manca - stesso
		-- principio di uspRifiutiRegistrazioni_upd (la FK di tblRifiutiMovimentiProduttori non accetta una Sede)
		DECLARE @idSedeProduttoreNessuna CHAR(16) = NULL;
		IF EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @idAutorizzazioneProduttoreDetentore)
		BEGIN
			DECLARE @idSedeProduttore CHAR(16) = @idAutorizzazioneProduttoreDetentore;
			SET @idAutorizzazioneProduttoreDetentore = NULL;

			SELECT @idAutorizzazioneProduttoreDetentore = Id
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @idSedeProduttore
				AND IdRuolo = 'P'
				AND Nessuna = 1
				AND Lock = 0;

			IF @idAutorizzazioneProduttoreDetentore IS NULL
			BEGIN
				SET @idSedeProduttoreNessuna = @idSedeProduttore;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idAutorizzazioneProduttoreDetentore OUTPUT;
			END
		END

		IF @ModalitaRitorno = 'R'
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRegistrazione OUTPUT;
		ELSE
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idFormulario OUTPUT;

		BEGIN TRANSACTION;

			IF @idSedeProduttoreNessuna IS NOT NULL
				INSERT dbo.tblRifiutiAutorizzazioni
					(Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
				VALUES
					(@idAutorizzazioneProduttoreDetentore, @idSedeProduttoreNessuna, 'P', '19000101', '20501231', 1, 0, 0);

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, FormularioNumero, RentriFormularioStato, DataInizioTrasporto, Note)
			VALUES
				(@idMovimento, @IdRegistro, @IdOperazione, @Eer, @EerDescrizione, @idStatoFisico, @idAttivitaRs, @idUnitaMisura, @Provenienza, @quantitaFinale, @Numero, @Stato, @dataOraInizioTrasportoFinale, @Note);

			IF @idAutorizzazioneProduttoreDetentore IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @idAutorizzazioneProduttoreDetentore, @quantitaFinale, 0);

			IF @idAutorizzazioneDestinatario IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneDestinatario, 0);

			-- Solo il trasporto su strada e' estratto dal FIR (conducente/targhe/percorso): se presente uno
			-- di questi dati si assume 'G' (terrestre), altrimenti si lascia decidere all'utente da Edit.
			DECLARE @isTrasportoStrada BIT = CAST(IIF(@TargaMotrice IS NOT NULL OR @ConducenteNome IS NOT NULL, 1, 0) AS BIT);
			IF @idAutorizzazioneTrasportatore1 IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
				VALUES (@idMovimento, @idAutorizzazioneTrasportatore1, IIF(@isTrasportoStrada = 1, 'G', NULL), 0);

			IF @idAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneIntermediario1, 0);

				IF @idAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @idAutorizzazioneIntermediario2, 1);
			END

			IF @ClassiPericolo IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
				SELECT @idMovimento, c.Id
				FROM
					STRING_SPLIT(@ClassiPericolo, ';') v
					INNER JOIN dbo.tblRifiutiClassiPericolo c ON c.Codice = v.value;

			IF @ModalitaRitorno = 'R'
			BEGIN
				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, [Data], Numero, IdEsito, QuantitaVerificata, DataFineTrasporto, IdCausaleRespingimento, CausaleRespingimentoAltro, Lock)
				VALUES
					(@idRegistrazione, @idMovimento, @operazione, @registrazioneData, @registrazioneNumero, @idEsito, @quantitaVerificataFinale, @DataOraFineTrasporto, @idCausaleRespingimento, LEFT(@RespingimentoMotivo, 100), 2);

				SET @returnId = @idRegistrazione;
			END
			ELSE
			BEGIN
				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdAdr, IdAnalisiTipo, TrasportoAdr, DataEmissione, AnalisiData, AnalisiNumero, VerificatoInPartenza, NumeroOnu, AdrNote, ColliNumero, Lock)
				VALUES
					(@idFormulario, @idMovimento, @idAdr, @idAnalisiTipo, CAST(IIF(@ClasseADR IS NOT NULL, 1, 0) AS BIT), @dataEmissioneFinale, @analisiDataFinale, @AnalisiNumero, @QuantitaVerificataPartenza, @NumeroONU, @AdrNote, @Colli, 2);

				IF @isTrasportoStrada = 1
					INSERT dbo.tblRifiutiFormulariTrasportiTerresti (Id, TargaMotrice, TargaRimorchio, ConducenteNome, ConducenteCognome, Percorso)
					VALUES (@idFormulario, @TargaMotrice, @TargaRimorchio, @ConducenteNome, @ConducenteCognome, @Percorso);

				SET @returnId = @idFormulario;
			END

		COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Id = @returnId;

END;
GO
GO

-- ===== sql\procedures\uspRifiutiOperazioni_get_SelectList.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiOperazioni_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IsRentri BIT = NULL,
	@IsFormulario BIT = NULL,
	@IsIntegrazioneFir BIT = NULL,
	@Operazione CHAR(1) = NULL,
	@IsFormularioUnico BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- @IsRentri          = NULL → nessun filtro; = 1 → solo Rentri
		-- @IsFormulario      = NULL → nessun filtro; = 0 → senza formulario; = 1 → con formulario
		-- @IsIntegrazioneFir = NULL → nessun filtro; = 1 → solo operazioni che integrano un FIR altrui
		--                     (Rifiuti/Registrazioni, importazione da formulario digitale RENTRI - piu' ampio
		--                     di IsFormulario: include anche Z/I che non emettono un proprio FIR)
		-- @Operazione        = NULL → nessun filtro; altrimenti solo le operazioni del raggruppamento
		--                     (C carico, S scarico, X carico e scarico - ricerca di Rifiuti/Registrazioni)
		-- L'operazione del formulario unico (IsFormularioUnico, art. 230, comma 5) si propone solo con il modulo
		-- Vi.Vi.FIR (VVF) attivo sul dominio: senza, i formulari e le registrazioni già fatti restano, ma non se ne
		-- creano di nuovi
		-- @IsFormularioUnico = NULL → nessun filtro; = 0 → senza l'operazione del formulario unico (acquisizione da
		--                     formulario digitale RENTRI: un FIR del RENTRI non diventa un formulario unico)
		DECLARE @isViviFir BIT = IIF(dbo.ufnModuli_get_IsAttivoBySessione('VVF', @IdSessione) = 1, 1, 0);

		IF @IsFormulario = 1 SET @IsRentri = NULL;
		IF @IsIntegrazioneFir = 1 SET @IsRentri = NULL;

		SELECT
			Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(1 AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			o.Id,
			[Text] = CAST(o.Pos AS VARCHAR(2)) + '. ' + o.Nome,
			Selected = CAST(0 AS BIT),
			o.Pos
		FROM
			dbo.tblRifiutiOperazioni o
			INNER JOIN dbo.tblRifiutiOperazioniRegistriTipi ot ON o.Id = ot.Id
			INNER JOIN dbo.tblRifiutiRegistri r ON ot.IdTipo = r.IdTipo
			INNER JOIN dbo.tblSessioni e ON r.Id = e.IdRegistro
		WHERE
			e.Id = @IdSessione
			AND
				(
				@IsRentri IS NULL
				OR o.IsRentri = @IsRentri
				)
			AND
				(
				@IsFormulario IS NULL
				OR ISNULL(o.IsFormulario, 0) = @IsFormulario
				)
			AND
				(
				@IsIntegrazioneFir IS NULL
				OR ISNULL(o.IsIntegrazioneFir, 0) = @IsIntegrazioneFir
				)
			AND
				(
				@Operazione IS NULL
				OR o.Operazione = @Operazione
				)
			AND
				(
				ISNULL(o.IsFormularioUnico, 0) = 0
				OR @isViviFir = 1
				)
			AND
				(
				@IsFormularioUnico IS NULL
				OR ISNULL(o.IsFormularioUnico, 0) = @IsFormularioUnico
				)
		ORDER BY Pos
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
		THROW 50001, @returnMessage, 1
	END
END;
GO

-- ===== sql\procedures\uspRifiutiRegistrazioni_del.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0,
	@IsMultipla BIT = 0
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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id);

		-- Se @Id è una registrazione di rettifica, @idOriginaleRettifica è l'Id della registrazione
		-- rettificata (tblRentriRegistrazioniRettifiche.Id) - NULL per una registrazione normale.
		DECLARE @idOriginaleRettifica CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: registrazione mai esistita o già cancellata (es. doppio invio della
			-- richiesta di annullamento lato UI) — trattata come cancellazione già avvenuta con
			-- successo, non come errore. Salta anche il controllo di titolarità sottostante e
			-- l'intera catena Lock, che non hanno senso su un record inesistente.
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica non ancora inviata al RENTRI è sempre cancellata in modo
		-- irreversibile (mai soft-delete/Undo, vedi sotto) tramite una modale dedicata con conferma
		-- esplicita: la cancellazione multipla (checkbox in elenco) non è ammessa su di essa.
		IF @IsMultipla = 1 AND @idOriginaleRettifica IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND RentriIdentificativo IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica non ancora inviata al RENTRI va cancellata singolarmente';
			GOTO BRANCH_END;
		END

		DECLARE @idMovimento CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @isFormulario BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @conservazioneSostitutiva BIT;

		-- ── CASO 1: registrazione attiva (Lock = 0) → soft delete, o hard delete se è una rettifica ──
		IF @lock = 0
		BEGIN
			SELECT @rentriIdentificativo = RentriIdentificativo, @rentriData = RentriData, @conservazioneSostitutiva = ConservazioneSostitutiva
			FROM dbo.tblRifiutiRegistrazioni
			WHERE Id = @Id;

			-- Una registrazione già trasmessa a RENTRI non può più essere cancellata (vale anche per una rettifica)
			IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			-- Una registrazione bloccata per la conservazione sostitutiva non può più essere cancellata
			IF ISNULL(@conservazioneSostitutiva, 0) = 1
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni a
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.IdParent = r.Id
				WHERE
					a.Id = @Id
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione associata ad altre non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Recupero dati registrazione
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id,
				@operazione = r.Operazione,
				@idOperazione = m.IdOperazione
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
			WHERE r.Id = @Id;

			IF @idOriginaleRettifica IS NOT NULL
			BEGIN
				-- Rettifica confermata (Lock = 0) ma non ancora inviata al RENTRI: cancellazione sempre
				-- irreversibile (punto 6 della specifica, mai passa da Lock = 4/Undo), hard delete completo
				-- della rettifica, stessa sequenza del CASO 3 sotto. L'originale non e' mai stato modificato:
				-- cancellando la rettifica tornano operativi i valori precedenti (quelli scritti dalla rettifica
				-- confermata precedente o i valori propri dell'originale; per un annullamento, la quantita'
				-- piena). Va quindi rifiutata se nel frattempo le relazioni carico/scarico si sono basate sui
				-- valori rettificati e con i valori precedenti una giacenza andrebbe sotto zero. Una rettifica
				-- non applicata a Ecomatico (valori operativi = precedenti) si cancella sempre.
				BEGIN TRANSACTION;

					DECLARE @isAnnullamentoRettifica BIT = (SELECT ISNULL(Annullata, 0)
					FROM dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id
					);

					-- Relazioni attive dell'originale (controparte non in bozza e non annullata), bloccate fino
					-- alla fine della transazione: nessuna nuova associazione puo' nascere durante il controllo
					DECLARE @relazioni TABLE (Id CHAR(16), IdParent CHAR(16), Quantita DECIMAL(18, 2));
					INSERT @relazioni (Id, IdParent, Quantita)
					SELECT l.Id, l.IdParent, l.Quantita
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l WITH (UPDLOCK, HOLDLOCK)
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON l.Id = v.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON l.IdParent = vp.Id
					WHERE
						(
						l.Id = @idOriginaleRettifica
						OR l.IdParent = @idOriginaleRettifica
						)
						AND l.Quantita > 0
						AND r.Lock < 2
						AND rp.Lock < 2
						AND
							(
							v.IsAnnullata = 0
							OR l.Id = @idOriginaleRettifica
							)
						AND
							(
							vp.IsAnnullata = 0
							OR l.IdParent = @idOriginaleRettifica
							);

					IF @isAnnullamentoRettifica = 0 AND EXISTS (SELECT 1
					FROM @relazioni)
					BEGIN
						-- Correzione: valori operativi senza questa rettifica = quelli scritti dall'ultima altra
						-- rettifica confermata, altrimenti i valori propri dell'originale
						DECLARE @precIdEer CHAR(6), @precIdStatoFisico CHAR(1), @precIdUnitaMisura CHAR(2), @precQuantita DECIMAL(18, 2);

						SELECT
							@precIdEer = IdEer,
							@precIdStatoFisico = IdStatoFisico,
							@precIdUnitaMisura = IdUnitaMisura,
							@precQuantita = Quantita
						FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);

						IF EXISTS (
							SELECT 1
							FROM dbo.viewRifiutiRegistrazioniEffettive
							WHERE
								Id = @idOriginaleRettifica
								AND
									(
									ISNULL(@precIdEer, '') <> ISNULL(IdEer, '')
									OR ISNULL(@precIdStatoFisico, '') <> ISNULL(IdStatoFisico, '')
									OR ISNULL(@precIdUnitaMisura, '') <> ISNULL(IdUnitaMisura, '')
									)
						)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0)
						FROM @relazioni
						WHERE Id = @idOriginaleRettifica)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0)
						FROM @relazioni
						WHERE IdParent = @idOriginaleRettifica)
						BEGIN
							ROLLBACK TRANSACTION;
							SET @returnValue = -1;
							SET @returnMessage = 'La registrazione rettificata è stata associata ad altre con i valori corretti: la rettifica non può più essere cancellata';
							GOTO BRANCH_END;
						END
					END

					-- Annullamento di uno scarico: cancellandolo lo scarico torna a consumare i suoi carichi, che
					-- nel frattempo potrebbero essere stati scaricati da altre registrazioni. (Un carico annullato
					-- invece non poteva essere consumato ne' associato: torna disponibile senza problemi.)
					IF @isAnnullamentoRettifica = 1 AND EXISTS (
						SELECT 1
						FROM
							@relazioni l
							INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vc ON l.Id = vc.Id
							INNER JOIN dbo.tblRifiutiRegistrazioni ro ON l.IdParent = ro.Id
						WHERE
							l.IdParent = @idOriginaleRettifica
							AND ro.Operazione = 'S'
							AND vc.Quantita < l.Quantita + ( SELECT ISNULL(SUM(l2.Quantita), 0) FROM dbo.tblRifiutiRegistrazioniRelazioni l2 INNER JOIN dbo.tblRifiutiRegistrazioni rp2 ON l2.IdParent = rp2.Id INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp2 ON l2.IdParent = vp2.Id WHERE l2.Id = l.Id AND rp2.Operazione = 'S' AND l2.IdParent <> @idOriginaleRettifica AND l2.Quantita > 0 AND rp2.Lock < 2 AND vp2.IsAnnullata = 0 )
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'I carichi dello scarico annullato sono stati scaricati da altre registrazioni: l''annullamento non può più essere cancellato';
						GOTO BRANCH_END;
					END

					DELETE dbo.tblRifiutiRegistrazioniRelazioni
					WHERE
						Id = @Id
						OR IdParent = @Id;
					DELETE dbo.tblRifiutiMovimentiClassiPericolo
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					-- Indirizzi di intervento del formulario unico (art. 230, comma 5): restano con il formulario
					DELETE dbo.tblRifiutiMovimentiSediProduzione
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiProduttori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiDestinatari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiTrasportatori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiIntermediari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiLog
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiRegistrazioniEtichette
					WHERE Id = @Id;
					-- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione è NOT NULL (fa parte
					-- della PK composta con IdLotto) - non si può azzerare come il vecchio
					-- tblEoWMovimenti.IdRegistrazione (nullable), va rimossa la riga di collegamento.
					DELETE dbo.tblEoWLottiRifiutiRegistrazioni
					WHERE IdRegistrazione = @Id;
					DELETE dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id;
					DELETE dbo.tblRifiutiRegistrazioni
					WHERE Id = @Id;
					DELETE dbo.tblRifiutiFormulari
					WHERE
						IdMovimento = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimenti
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblIdLog
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);
					DELETE dbo.tblId
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);

					-- Magazzino EoW allineato al registro operativo: senza questa rettifica l'originale torna ai
					-- valori operativi precedenti; se sono piu' bassi (la correzione cancellata aveva aumentato
					-- una M) le sue allocazioni sui lotti si riducono
					EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginaleRettifica;

				COMMIT TRANSACTION;
			END
			ELSE
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblRifiutiRegistrazioni
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Registrazione non trovata o già eliminata';
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
		END

		-- ── CASO 2: registrazione non confermata (Lock = 1) ──────────────────
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- ── CASO 3: registrazione in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id
			FROM
				dbo.tblRifiutiRegistrazioni r
				LEFT JOIN dbo.tblRifiutiFormulari f ON r.IdMovimento = f.IdMovimento
			WHERE r.Id = @Id;

			BEGIN TRANSACTION;
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE
					Id = @Id
					OR IdParent = @Id;
				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				-- Indirizzi di intervento del formulario unico (art. 230, comma 5): restano con il formulario
				DELETE dbo.tblRifiutiMovimentiSediProduzione
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				-- (stesso gap trovato e corretto in uspRifiutiFormulari_del il 2026-08-21)
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiRegistrazioniEtichette
				WHERE Id = @Id;
				-- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione è NOT NULL (fa parte
				-- della PK composta con IdLotto) - non si può azzerare come il vecchio
				-- tblEoWMovimenti.IdRegistrazione (nullable), va rimossa la riga di collegamento.
				DELETE dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @Id;
				-- Bozza di rettifica mai confermata: non ha mai contato nei valori effettivi
				-- (viewRifiutiRegistrazioniEffettive considera solo Lock = 0), basta rimuovere il collegamento.
				DELETE dbo.tblRentriRegistrazioniRettifiche
				WHERE IdRettifica = @Id;
				DELETE dbo.tblRifiutiRegistrazioni
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE
					IdMovimento = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimenti
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
			COMMIT TRANSACTION;
		END

		-- ── CASO 4: Lock in stato non gestito ────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
GO

-- ===== sql\procedures\uspRifiutiRegistrazioni_get.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: con un formulario attivo @IdDocumentoTrasportoTipo deve restare il Formulario; per un altro documento si cancella prima il formulario
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiRegistrazioni
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = r.Id,
			IdMovimento = m.Id,
			m.IdRegistro,
			IdOperazione = ISNULL(m.IdOperazione, '0'),
			OperazioneNome = ISNULL(o.Nome, ''),
			OperazioneCodice = ISNULL(o.Codice, ''),
			IdEer = ISNULL(m.IdEer, '000000'),
			EerDescrizione = ISNULL(m.EerDescrizione, ''),
			IdStatoFisico = ISNULL(m.IdStatoFisico, '0'),
			IdProvenienza = ISNULL(m.IdProvenienza, 'S'),
			IdAttivitaRs = ISNULL(m.IdAttivita, '00'),

			RegistrazioneData = ISNULL(r.[Data], GETDATE()),
			RegistrazioneNumero = IIF(
				r.Lock = 2 OR r.Numero IS NULL,
				dbo.ufnRifiutiRegistrazioni_get_UltimoNumero(m.IdRegistro, GETDATE()) + 1,
				r.Numero
			),

			Quantita = ISNULL(m.Quantita, 0),
			IdUnitaMisura = ISNULL(m.IdUnitaMisura, 'KG'),

			NessunaRegistrazioneAssociata = CASE
														WHEN r.Lock = 2 THEN 0
														-- Solo scarico a terzi (S): procedura semplificata dei centri di raccolta
														WHEN m.IdOperazione <> 'S' THEN 0
														WHEN EXISTS(
															SELECT 1
															FROM dbo.tblRifiutiRegistrazioniRelazioni rel
															INNER JOIN dbo.tblRifiutiRegistrazioni rr ON rel.Id = rr.Id
															WHERE
																rel.IdParent = r.Id
																AND rr.Lock < 2
														) THEN 0
														ELSE 1
													END,

			DataInizioTrasporto = m.DataInizioTrasporto,

			RegistrazioneNote = ISNULL(r.Note, ''),
			UtenteNote = ISNULL(m.Note, ''),

			IdDocumentoTrasportoTipo = ISNULL(r.IdTrasportoTransfrontalieroTipo, 'F'),
			-- Formulario attivo sullo stesso movimento: il documento di trasporto resta il formulario (uspRifiutiRegistrazioni_upd)
			IsFormularioAssociato = CAST(IIF(f.Id IS NULL, 0, 1) AS BIT),
			IsFormularioNumero = CAST(CASE
				WHEN o.IsIntegrazioneFir = 1 AND r.Lock = 2 THEN 1
				ELSE IIF(m.FormularioNumero IS NULL, 0, 1)
			END AS BIT),
			FormularioNumero = ISNULL(m.FormularioNumero, ''),
			FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
			RentriFormularioStato = m.RentriFormularioStato,
			RentriFormularioDataPresaVisione = m.RentriFormularioDataPresaVisione,
			RentriFormularioDataCopia = m.RentriFormularioDataCopia,
			r.RentriIdentificativo,
			r.RentriData,
			ConservazioneSostitutiva = ISNULL(r.ConservazioneSostitutiva, 0),

			IsTrasportoTransfrontaliero = CAST(IIF(r.IdTrasportoTransfrontalieroTipo IS NOT NULL, 1, 0) AS BIT),
			IdTrasportoTransfrontalieroTipo = ISNULL(r.IdTrasportoTransfrontalieroTipo, 'D'),

			IdAutorizzazioneProduttoreDetentore = ISNULL(mp.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneDestinatario = ISNULL(md.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore1 = ISNULL(mt1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore2 = ISNULL(mt2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore3 = ISNULL(mt3.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario1 = ISNULL(mi1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario2 = ISNULL(mi2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario3 = ISNULL(mi3.IdAutorizzazione, REPLICATE('0', 16)),

			IsRelazionabile = CAST(IIF(EXISTS(SELECT 1
			FROM dbo.tblRifiutiOperazioniRelazioni
			WHERE Id = m.IdOperazione), 1, 0) AS BIT),
			IsRegistrazioneAuto = CAST(IIF(o.OperazioneAuto IS NULL, 0, 1) AS BIT),
			IsVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),

			IdRaee = ISNULL(r.IdRaee, '0'),

			VeicoloFuoriUsoNumero = ISNULL(r.VeicoloFuoriUsoNumero, ''),
			VeicoloFuoriUsoData = r.VeicoloFuoriUsoData,

			-- Esito
			IdEsito = ISNULL(r.IdEsito, '0'),
			IdCausaleRespingimento = ISNULL(r.IdCausaleRespingimento, 'N'),
			IdUnitaMisuraQuantitaRespinta = ISNULL(r.IdUnitaMisuraQuantitaRespinta, 'KG'),
			CausaleRespingimentoAltro = ISNULL(r.CausaleRespingimentoAltro, ''),
			QuantitaVerificata = ISNULL(r.QuantitaVerificata, 0),
			IsQuantitaVerificata = CAST(IIF(r.QuantitaVerificata IS NOT NULL, 1, 0) AS BIT),
			QuantitaRespinta = ISNULL(r.QuantitaRespinta, 0),
			DataFineTrasporto = r.DataFineTrasporto,

			-- Materiale
			IdMateriale = ISNULL(r.IdMateriale, '00'),
			MaterialeDescrizione = ISNULL(r.MaterialeDescrizione, ''),

			-- Provenienza
			IdAttivitaProvenienza = ISNULL(r.IdAttivitaProvenienza, '0'),

			IsIntegrazioneFir = ISNULL(o.IsIntegrazioneFir, 0),
			IsProduttore = ISNULL(o.IsProduttore, 0),
			IsTrasportatore = ISNULL(o.IsTrasportatore, 0),
			IsDestinatario = ISNULL(o.IsDestinatario, 0),
			IsIntermediario = ISNULL(o.IsIntermediario, 0),
			IsAttivitaRs = ISNULL(o.IsAttivitaRs, 0),
			IsEsito = ISNULL(o.IsEsito, 0),
			IsRentriAccettazione = ISNULL(o.IsRentriAccettazione, 0),
			IsAttivitaProvenienza = ISNULL(o.IsAttivitaProvenienza, 0),
			IsMateriale = ISNULL(o.IsMateriale, 0),
			IsStoccaggioIstantaneo = ISNULL(o.IsStoccaggioIstantaneo, 0),

			-- Rettifica: rett.Id valorizzato solo se questa registrazione e' essa stessa una rettifica di
			-- un'altra (tblRentriRegistrazioniRettifiche.IdRettifica = r.Id).
			IdRegistrazioneOriginaleRettifica = rett.Id,
			RettificaRegistrazioneNumero = ro.Numero,
			RettificaRegistrazioneData = ro.Data,
			IsRettifica = CAST(IIF(rett.Id IS NOT NULL, 1, 0) AS BIT),
			IsAnnullamento = CAST(ISNULL(rett.Annullata, 0) AS BIT),

			Lock = r.Lock
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento AND f.Lock < 2
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRentriRegistrazioniRettifiche rett ON rett.IdRettifica = r.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni ro ON rett.Id = ro.Id
			-- Produttori
			LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
			-- Destinatari
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			-- Trasportatori
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt3 ON m.Id = mt3.Id AND mt3.Pos = 2
			-- Intermediari
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi3 ON m.Id = mi3.Id AND mi3.Pos = 2
		WHERE
			r.Id = @Id
			AND r.Lock <= 2;

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

-- ===== sql\procedures\uspRifiutiRegistrazioni_get_List.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL,
	@Operazione CHAR(1) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@NonTrasmesseRentri BIT = 0,
	@NonInConservazione BIT = 0,
	@SenzaEsito BIT = 0,
	@XfirSenzaPresaVisione BIT = 0,
	@XfirAttesaAccettazione BIT = 0,
	@XfirCopiaNonCaricata BIT = 0,
	@XfirCopiaNonTrasmessa BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @Eer = dbo.ufnStringhe_get_SenzaSpazi(@Eer, 0, 1);
		SET @Formulario = dbo.ufnStringhe_get_SenzaSpazi(@Formulario, 0, 1);
		SET @Numeri = dbo.ufnStringhe_get_SenzaSpazi(@Numeri, 0, 1);
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage INT,
            @Offset      INT,
            @IdSessione  CHAR(16),
            @DallaData   DATE,
            @AllaData    DATE,
            @Soggetto    VARCHAR(50),
            @Eer         VARCHAR(50),
            @Formulario  VARCHAR(50),
            @Etichetta   VARCHAR(50),
            @Operazione   CHAR(1),
            @IdOperazione CHAR(1)';

		-- FormularioNumero: spostato da tblRifiutiFormulari.Numero a tblRifiutiMovimenti.FormularioNumero
		SET @stmt = N'
        WITH tbl AS (
            SELECT
                Id                       = r.Id,
                StatoValore              = CASE WHEN r.Lock = 1 THEN 1 ELSE 0 END,
                StatoDescrizione         = CASE WHEN r.Lock = 1 THEN ''Registrazione da confermare'' ELSE ''OK'' END,
                RegistrazioneNumero      = r.Numero,
                RegistrazioneData        = r.Data,
                OperazioneNome           = o.Nome,
                Quantita                 = m.Quantita           * IIF(r.Operazione = ''S'', -1, 1),
                IsQuantitaVerificata     = CAST(IIF(r.QuantitaVerificata IS NULL, 0, 1) AS BIT),
                QuantitaVerificata       = r.QuantitaVerificata * IIF(r.Operazione = ''S'', -1, 1),
                EerNome                  = ISNULL(c.Nome, t.Codice),
                EerDescrizione           = ISNULL(c.Descrizione, t.Nome),
                StatoFisicoCodice        = s.Codice,
                StatoFisicoNome          = s.Nome,
                AttivitaRsCodice         = a.Codice,
                AttivitaRsNome           = a.Nome,
                FormularioNumero         = m.FormularioNumero,
                ProduttoreDetentoreSede  = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
                Trasportatore1Sede       = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
                DestinatarioSede         = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
                Intermediario1Sede       = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
                r.Etichette,
                IsRentriCollegato        = CAST(IIF(z.Id IS NOT NULL, 1, 0) AS BIT),
                r.RentriIdentificativo,
                r.RentriData,
                IsRettifica              = CAST(IIF(rett.Id IS NOT NULL, 1, 0) AS BIT),
                IsAnnullamento           = CAST(ISNULL(rett.Annullata, 0) AS BIT),
                RettificaRegistrazioneNumero = ro.Numero,
                RettificaRegistrazioneData   = ro.Data,
                RentriFormularioStato    = m.RentriFormularioStato,
                RentriFormularioCartaceo = ISNULL(m.RentriFormularioCartaceo, 0),
                IsFormularioUnico        = CAST(ISNULL(o.IsFormularioUnico, 0) AS BIT),
                ViviFirVidimato          = CAST(ISNULL(m.ViviFirVidimato, 0) AS BIT)
            FROM
                dbo.tblRifiutiRegistrazioni                  r
                INNER JOIN dbo.tblRifiutiMovimenti           m  ON r.IdMovimento               = m.Id
                INNER JOIN dbo.tblRifiutiRegistri            g  ON m.IdRegistro                = g.Id
                INNER JOIN dbo.tblSessioni                   e  ON g.Id                        = e.IdRegistro
                LEFT  JOIN dbo.tblRifiutiOperazioni          o  ON m.IdOperazione              = o.Id
                LEFT  JOIN dbo.tblRifiutiEer                 c  ON m.IdEer                     = c.Id
                LEFT  JOIN dbo.tblRifiutiStatiFisici         s  ON m.IdStatoFisico             = s.Id
				LEFT  JOIN dbo.tblRifiutiMateriali		     t  ON r.IdMateriale			   = t.Id
                LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento
                                                             a  ON m.IdAttivita                = a.Id
                LEFT  JOIN dbo.tblSedi                       sp ON m.IdSedeProduttoreDetentore = sp.Id
                LEFT  JOIN dbo.tblSedi                       st ON m.IdSedeTrasportatore1      = st.Id
                LEFT  JOIN dbo.tblSedi                       sd ON m.IdSedeDestinatario        = sd.Id
                LEFT  JOIN dbo.tblSedi                       si ON m.IdSedeIntermediario1      = si.Id
                LEFT  JOIN dbo.tblRentriRegistri             z  ON g.Id                        = z.Id
                LEFT  JOIN dbo.tblRentriRegistrazioniRettifiche
                                                             rett ON rett.IdRettifica          = r.Id
                LEFT  JOIN dbo.tblRifiutiRegistrazioni       ro ON rett.Id                     = ro.Id
            WHERE
                e.Id      = @IdSessione
                AND r.Lock < 2
                AND (@DallaData IS NULL OR r.Data >= @DallaData)
                AND (@AllaData  IS NULL OR r.Data <= @AllaData)';

		IF @Soggetto IS NOT NULL
		BEGIN
			IF @Ruolo = 'P'
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'T'
				SET @stmt = @stmt + N' AND (st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'D'
				SET @stmt = @stmt + N' AND (sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'I'
				SET @stmt = @stmt + N' AND (si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
		END

		-- Filtro numeri: interi validati con TRY_CAST prima della concatenazione.
		-- Eccezione documentata al divieto di concatenazione: solo interi puri vengono inseriti.
		IF @Numeri IS NOT NULL
		BEGIN
			IF @Numeri LIKE '[1-9]%-%[0-9]' AND @Numeri LIKE '%[1-9]-[0-9]%'
			BEGIN
				DECLARE @numeroInizio VARCHAR(20) = SUBSTRING(@Numeri, 1, CHARINDEX('-', @Numeri) - 1);
				DECLARE @numeroFine VARCHAR(20) = SUBSTRING(@Numeri, CHARINDEX('-', @Numeri) + 1, 20);
				IF TRY_CAST(@numeroInizio AS INT) IS NOT NULL AND TRY_CAST(@numeroFine AS INT) IS NOT NULL
					SET @stmt = @stmt + N' AND r.Numero BETWEEN ' + @numeroInizio + N' AND ' + @numeroFine;
			END
			ELSE IF TRY_CAST(@Numeri AS INT) IS NOT NULL
				SET @stmt = @stmt + N' AND r.Numero = ' + @Numeri;
		END

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N' AND r.Id IN ('
					  + N'    SELECT t.Id FROM dbo.tblRifiutiRegistrazioniEtichette t'
					  + N'    INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id'
					  + N'    WHERE et.Nome LIKE ''%'' + @Etichetta + ''%'')';

		-- Carico/Scarico: raggruppamento della registrazione (C, S, X = carico e scarico); Operazione:
		-- l'operazione specifica del movimento. Senza Operazione si filtra solo per Carico/Scarico.
		IF @Operazione IS NOT NULL
			SET @stmt = @stmt + N' AND r.Operazione = @Operazione';

		IF @IdOperazione IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdOperazione = @IdOperazione';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		IF @NonTrasmesseRentri = 1
			SET @stmt = @stmt + N' AND r.RentriData IS NULL';

		-- "Non inviate in conservazione" = conservazione del registro (RentriDataInvioConservazione nel
		-- pannello "RENTRI - Stato"): NOT EXISTS anziché OUTER APPLY per non pagare il join cross-database
		-- su ogni riga quando il flag non è richiesto.
		IF @NonInConservazione = 1
			SET @stmt = @stmt + N' AND NOT EXISTS (
                SELECT 1 FROM [1_0_rentri]..tblRegistriConservazioni con
                WHERE con.IdRegistro = z.IdRentri COLLATE DATABASE_DEFAULT
                    AND con.Anno = YEAR(r.[Data])
                    AND r.Numero BETWEEN con.DalNumero AND con.AlNumero
                    AND con.Conservazione = 1
            )';

		IF @SenzaEsito = 1
			SET @stmt = @stmt + N' AND r.DataFineTrasporto IS NULL';

		-- I successivi 3 flag riguardano solo registrazioni con un xFIR collegato (RentriFormularioStato
		-- valorizzato): altrimenti il filtro intercetterebbe anche tutte le registrazioni senza alcun
		-- formulario digitale, per le quali le date sotto sono banalmente NULL.
		IF @XfirSenzaPresaVisione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataPresaVisione IS NULL';

		IF @XfirAttesaAccettazione = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato = ''InserimentoAccettazione''';

		IF @XfirCopiaNonCaricata = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataCopia IS NULL';

		IF @XfirCopiaNonTrasmessa = 1
			SET @stmt = @stmt + N' AND m.RentriFormularioStato IS NOT NULL AND m.RentriFormularioDataTrasmissione IS NULL';

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.RegistrazioneNumero, tbl.RegistrazioneData,
            tbl.OperazioneNome, tbl.Quantita, tbl.IsQuantitaVerificata, tbl.QuantitaVerificata,
            tbl.EerNome, tbl.EerDescrizione,
            tbl.StatoFisicoCodice, tbl.StatoFisicoNome,
            tbl.AttivitaRsCodice, tbl.AttivitaRsNome,
            tbl.FormularioNumero, tbl.ProduttoreDetentoreSede, tbl.Trasportatore1Sede, tbl.DestinatarioSede, tbl.Intermediario1Sede,
            tbl.Etichette,
            tbl.IsRentriCollegato, tbl.RentriIdentificativo, tbl.RentriData,
            tbl.IsRettifica, tbl.IsAnnullamento, tbl.RettificaRegistrazioneNumero, tbl.RettificaRegistrazioneData,
            tbl.RentriFormularioStato, tbl.RentriFormularioCartaceo, tbl.IsFormularioUnico, tbl.ViviFirVidimato,
            RowsCount = COUNT(*) OVER ()
        FROM tbl
        ORDER BY tbl.RegistrazioneData DESC, tbl.RegistrazioneNumero DESC
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY
        OPTION (RECOMPILE);';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Soggetto = @Soggetto,
			@Eer = @Eer,
			@Formulario = @Formulario,
			@Etichetta = @Etichetta,
			@Operazione = @Operazione,
			@IdOperazione = @IdOperazione;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO

-- ===== sql\procedures\uspRifiutiRegistrazioni_get_Report.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rifiuti > Report: riepiloghi delle registrazioni della sede del contesto, per operazione ed EER. La stessa
-- SP serve l'elenco a video e l'esportazione in Excel e in CSV: il nome di ogni colonna è l'intestazione,
-- nell'ordine in cui le colonne vanno mostrate (pagina comune dei report).
-- @Report sceglie le operazioni contate e le colonne in più:
--   PR  Rifiuti prodotti                                   DT, RE
--   PL  Rifiuti prodotti da lavorazione                    NP
--   RT  Rifiuti ricevuti da terzi                          T*              + produttore
--   TR  Rifiuti trasportati                                T*aT
--   TT  Rifiuti trasportati da terzi                       aT, T*          + trasportatore
--   CT  Rifiuti consegnati a terzi (destinatari)           aT              + destinatario
--   IN  Rifiuti movimentati attraverso intermediari        aT, T*, T*aT, TR + intermediario
--   DG  Destinazione (R o D) dei rifiuti gestiti nell'unità locale   T*, I  + attività
--   DC  Destinazione (R o D) dei rifiuti consegnati a terzi          aT     + attività e destinatario
--   MV  Quantità rifiuti movimentati per CER               tutte, tranne M (materiali) e SI (stoccaggio istantaneo)
--   OI  ORSO Impianti                                      T*, RE, I, aT per mese e soggetto, più la giacenza a
--       fine mese: ramo a parte, con colonne e regole sue (descritte dove inizia)
-- Nei report con la colonna del soggetto (RT, TT, CT, IN, DC) entrano solo le registrazioni che lo indicano,
-- che sia una sede esterna o una sede dell'azienda: senza soggetto la registrazione non compare. Trasportatore
-- e intermediario sono il primo indicato sul movimento; il secondo e il terzo non contano.
-- La colonna Operazione (codice e nome della causale) distingue le righe quando il report conta più operazioni.
-- Valori OPERATIVI (viewRifiutiRegistrazioniEffettive: EER, stato fisico, unità di misura e quantità dopo le
-- rettifiche): contano le registrazioni confermate (Lock = 0), escluse le rettifiche e le registrazioni
-- annullate operativamente. Le quantità non si convertono: una riga per ogni unità di misura.
-- La sede è quella del contesto della sessione (senza sede nessuna riga); @IdRegistro restringe a un registro
-- della sede, @DataDa e @DataA alla data della registrazione.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che il limite è superato).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_Report
	@IdSessione CHAR(16) = NULL,
	@Report CHAR(2) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdRegistro CHAR(16) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Report = UPPER(NULLIF(LTRIM(RTRIM(@Report)), ''));
		SET @IdRegistro = NULLIF(NULLIF(LTRIM(RTRIM(@IdRegistro)), ''), REPLICATE('0', 16));
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Report IS NULL OR @Report NOT IN ('PR', 'PL', 'RT', 'TR', 'TT', 'CT', 'IN', 'DG', 'DC', 'MV', 'OI')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Report non previsto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- ORSO Impianti: i dati mensili della scheda impianti di ORSO, per chi la compila. Una riga per mese,
		-- operazione, EER e soggetto: ricevuti da terzi (T*) con il produttore, prodotti fuori dall'unità locale
		-- (RE), trattati internamente (I), consegnati a terzi (aT) con il destinatario; per T* e I l'attività di
		-- recupero o smaltimento. Il soggetto ha comune e provincia (nazione se estero) e può mancare: la
		-- registrazione conta comunque. Gli stati fisici si sommano.
		-- In più la giacenza a fine mese, per EER: il residuo all'ultimo giorno del mese dei carichi di rifiuti
		-- non ricevuti da terzi (DT, NP, RE), cioè la quantità meno quanto prelevato dalle registrazioni fino a
		-- quel giorno (stesso calcolo di uspRifiutiGiacenze_get_Carichi_List). Solo per i mesi conclusi entro
		-- @DataA e non oltre oggi. I carichi ricevuti da terzi e i materiali non sono in questa giacenza.
		IF @Report = 'OI'
		BEGIN
			DECLARE @oggi DATE = GETDATE();
			DECLARE @fineUltima DATE = IIF(@DataA IS NULL OR @DataA > @oggi, @oggi, @DataA);
			DECLARE @fine DATE;

			-- I mesi partono da @DataDa, ma non prima della prima registrazione della sede (senza
			-- registrazioni nessun mese)
			SELECT @fine = EOMONTH(IIF(@DataDa > MIN(r.[Data]), @DataDa, MIN(r.[Data])))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			WHERE
				g.IdSede = @idSede
				AND r.Lock = 0;

			DECLARE @mesi TABLE (
				Fine DATE NOT NULL PRIMARY KEY
			);
			WHILE @fine <= @fineUltima
			BEGIN
				INSERT @mesi (Fine) VALUES (@fine);
				SET @fine = EOMONTH(DATEADD(MONTH, 1, @fine));
			END

			DECLARE @carichi TABLE (
				Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
				[Data] DATE NOT NULL,
				IdEer CHAR(6) COLLATE DATABASE_DEFAULT NULL,
				IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
				Quantita DECIMAL(18, 4) NOT NULL
			);
			INSERT @carichi (Id, [Data], IdEer, IdUnitaMisura, Quantita)
			SELECT
				r.Id,
				r.[Data],
				v.IdEer,
				v.IdUnitaMisura,
				v.Quantita
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			WHERE
				g.IdSede = @idSede
				AND r.Lock = 0
				AND v.IsRettifica = 0
				AND v.Quantita > 0
				AND m.IdOperazione IN ('C', 'M', 'F', 'P')
				AND r.[Data] <= @fineUltima
				AND
					(
					@IdRegistro IS NULL
					OR m.IdRegistro = @IdRegistro
					)
			OPTION (RECOMPILE);

			-- Quanto prelevato da ogni carico, con la data della registrazione che preleva: una registrazione
			-- annullata ha quantità effettiva zero e non consuma più il carico
			DECLARE @prelievi TABLE (
				Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
				[Data] DATE NOT NULL,
				Quantita DECIMAL(18, 4) NOT NULL
			);
			INSERT @prelievi (Id, [Data], Quantita)
			SELECT
				l.Id,
				p.[Data],
				l.Quantita
			FROM
				@carichi c
				INNER JOIN dbo.tblRifiutiRegistrazioniRelazioni l ON c.Id = l.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
			WHERE
				p.Lock = 0
				AND vp.Quantita > 0
				AND p.[Data] <= @fineUltima;

			WITH Movimenti AS (
				SELECT
					Mese = DATEFROMPARTS(YEAR(r.[Data]), MONTH(r.[Data]), 1),
					Ordine = CASE m.IdOperazione WHEN 'Z' THEN 1 WHEN 'F' THEN 2 WHEN 'P' THEN 2 WHEN 'R' THEN 3 ELSE 4 END,
					Operazione = CAST(o.Codice + ' - ' + o.Nome AS VARCHAR(110)),
					Eer = e.Nome,
					Descrizione = e.Descrizione,
					Attivita = IIF(m.IdOperazione IN ('Z', 'R'), a.Codice, NULL),
					IdSoggetto = s.Id,
					Soggetto = s.NomeCompleto,
					Comune = c.Nome,
					Provincia = CAST(IIF(pv.Id IS NULL, n.Nome, pv.Nome + ' (' + pv.Sigla + ')') AS VARCHAR(110)),
					Registrazioni = COUNT(*),
					Quantita = CAST(SUM(v.Quantita) AS DECIMAL(18, 2)),
					Unita = u.Codice
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
					INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
					LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
					LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
					LEFT JOIN dbo.tblSedi s ON s.Id =
						CASE m.IdOperazione
							WHEN 'Z' THEN m.IdSedeProduttoreDetentore
							WHEN 'S' THEN m.IdSedeDestinatario
						END
					LEFT JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
					LEFT JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
					LEFT JOIN dbo.tblComuni c ON i.IdComune = c.Id
					LEFT JOIN dbo.tblProvince pv ON c.IdProvincia = pv.Id
					LEFT JOIN dbo.tblNazioni n ON i.IdNazione = n.Id
				WHERE
					g.IdSede = @idSede
					AND r.Lock = 0
					AND v.IsRettifica = 0
					AND v.IsAnnullata = 0
					AND m.IdOperazione IN ('Z', 'F', 'P', 'R', 'S')
					AND
						(
						@IdRegistro IS NULL
						OR m.IdRegistro = @IdRegistro
						)
					AND
						(
						@DataDa IS NULL
						OR r.[Data] >= @DataDa
						)
					AND (@DataA IS NULL OR r.[Data] <= @DataA)
				GROUP BY
					DATEFROMPARTS(YEAR(r.[Data]), MONTH(r.[Data]), 1),
					m.IdOperazione,
					o.Codice,
					o.Nome,
					e.Nome,
					e.Descrizione,
					IIF(m.IdOperazione IN ('Z', 'R'), a.Codice, NULL),
					s.Id,
					s.NomeCompleto,
					c.Nome,
					pv.Id,
					pv.Nome,
					pv.Sigla,
					n.Nome,
					u.Codice
			),
			Residui AS (
				SELECT
					ms.Fine,
					c.IdEer,
					c.IdUnitaMisura,
					Residuo = c.Quantita - ISNULL(
						(SELECT SUM(p.Quantita)
						FROM @prelievi p
						WHERE
							p.Id = c.Id
							AND p.[Data] <= ms.Fine), 0)
				FROM
					@mesi ms
					INNER JOIN @carichi c ON c.[Data] <= ms.Fine
			),
			Giacenze AS (
				SELECT
					Mese = DATEFROMPARTS(YEAR(x.Fine), MONTH(x.Fine), 1),
					Ordine = 5,
					Operazione = CAST('Giacenza a fine mese' AS VARCHAR(110)),
					Eer = e.Nome,
					Descrizione = e.Descrizione,
					Attivita = CAST(NULL AS VARCHAR(3)),
					IdSoggetto = CAST(NULL AS CHAR(16)),
					Soggetto = CAST(NULL AS VARCHAR(200)),
					Comune = CAST(NULL AS VARCHAR(100)),
					Provincia = CAST(NULL AS VARCHAR(110)),
					Registrazioni = COUNT(*),
					Quantita = CAST(SUM(x.Residuo) AS DECIMAL(18, 2)),
					Unita = u.Codice
				FROM
					Residui x
					LEFT JOIN dbo.tblRifiutiEer e ON x.IdEer = e.Id
					LEFT JOIN dbo.tblUnitaMisura u ON x.IdUnitaMisura = u.Id
				WHERE x.Residuo > 0
				GROUP BY
					x.Fine,
					e.Nome,
					e.Descrizione,
					u.Codice
			)
			SELECT TOP (@MaxRighe + 1)
				[Mese] = RIGHT('0' + CAST(MONTH(x.Mese) AS VARCHAR(2)), 2) + '/' + CAST(YEAR(x.Mese) AS CHAR(4)),
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Attività] = x.Attivita,
				[Soggetto] = x.Soggetto,
				[Comune] = x.Comune,
				[Provincia] = x.Provincia,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM
				(SELECT * FROM Movimenti
				UNION ALL
				SELECT * FROM Giacenze) x
			ORDER BY
				x.Mese,
				x.Ordine,
				x.Eer,
				x.Attivita,
				x.Soggetto,
				x.IdSoggetto,
				x.Unita
			OPTION (RECOMPILE);

			GOTO BRANCH_END;
		END

		-- Operazioni contate dal report (tblRifiutiOperazioni.Id)
		DECLARE @operazioni TABLE (
			Id CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
		);
		INSERT @operazioni (Id)
		SELECT x.Id
		FROM
			(VALUES
				('PR', 'C'), ('PR', 'F'), ('PR', 'P'),
				('PL', 'M'),
				('RT', 'Z'),
				('TR', 'T'), ('TR', 'Q'),
				('TT', 'S'), ('TT', 'Z'),
				('CT', 'S'),
				('IN', 'S'), ('IN', 'Z'), ('IN', 'T'), ('IN', 'Q'), ('IN', 'I'),
				('DG', 'Z'), ('DG', 'R'),
				('DC', 'S'),
				('MV', 'C'), ('MV', 'F'), ('MV', 'P'), ('MV', 'M'), ('MV', 'Z'), ('MV', 'T'), ('MV', 'Q'), ('MV', 'S'), ('MV', 'R'), ('MV', 'I')
			) x (Report, Id)
		WHERE x.Report = @Report;

		-- Soggetto in colonna: P produttore, D destinatario, T trasportatore, I intermediario
		DECLARE @soggetto CHAR(1) =
			CASE @Report
				WHEN 'RT' THEN 'P'
				WHEN 'TT' THEN 'T'
				WHEN 'CT' THEN 'D'
				WHEN 'IN' THEN 'I'
				WHEN 'DC' THEN 'D'
			END;
		DECLARE @conAttivita BIT = IIF(@Report IN ('DG', 'DC'), 1, 0);

		DECLARE @righe TABLE (
			Pos INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			Operazione VARCHAR(110) COLLATE DATABASE_DEFAULT NULL,
			Eer VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			StatoFisico VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Pericoloso BIT NULL,
			Attivita VARCHAR(3) COLLATE DATABASE_DEFAULT NULL,
			Soggetto VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Registrazioni INT NOT NULL,
			Quantita DECIMAL(18, 2) NULL,
			Unita VARCHAR(2) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT @righe (Operazione, Eer, Descrizione, StatoFisico, Pericoloso, Attivita, Soggetto, Registrazioni, Quantita, Unita)
		SELECT TOP (@MaxRighe + 1)
			o.Codice + ' - ' + o.Nome,
			e.Nome,
			e.Descrizione,
			sf.Nome,
			e.Pericoloso,
			IIF(@conAttivita = 1, a.Codice, NULL),
			s.NomeCompleto,
			COUNT(*),
			SUM(v.Quantita),
			u.Codice
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN @operazioni p ON m.IdOperazione = p.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici sf ON v.IdStatoFisico = sf.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			LEFT JOIN dbo.tblSedi s ON s.Id =
				CASE @soggetto
					WHEN 'P' THEN m.IdSedeProduttoreDetentore
					WHEN 'D' THEN m.IdSedeDestinatario
					WHEN 'T' THEN m.IdSedeTrasportatore1
					WHEN 'I' THEN m.IdSedeIntermediario1
				END
		WHERE
			g.IdSede = @idSede
			AND r.Lock = 0
			AND v.IsRettifica = 0
			AND v.IsAnnullata = 0
			AND
				(
				@IdRegistro IS NULL
				OR m.IdRegistro = @IdRegistro
				)
			AND
				(
				@DataDa IS NULL
				OR r.[Data] >= @DataDa
				)
			AND (@DataA IS NULL OR r.[Data] <= @DataA)
			-- Report con la colonna del soggetto: solo le registrazioni che lo indicano, interno o esterno
			AND
				(
				@soggetto IS NULL
				OR s.Id IS NOT NULL
				)
		GROUP BY
			o.Pos,
			o.Codice,
			o.Nome,
			e.Nome,
			e.Descrizione,
			sf.Nome,
			e.Pericoloso,
			IIF(@conAttivita = 1, a.Codice, NULL),
			s.Id,
			s.NomeCompleto,
			u.Codice
		ORDER BY
			o.Pos,
			e.Nome,
			sf.Nome,
			IIF(@conAttivita = 1, a.Codice, NULL),
			s.NomeCompleto,
			s.Id,
			u.Codice
		OPTION (RECOMPILE);

		-- Stesse righe, con le colonne del report
		IF @Report = 'DC'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Attività] = x.Attivita,
				[Destinatario] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @Report = 'DG'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Attività] = x.Attivita,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'P'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Produttore] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'D'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Destinatario] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'T'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Trasportatore] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'I'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Intermediario] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;

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
GO

-- ===== sql\procedures\uspRifiutiRegistrazioni_upd.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdDocumentoTrasportoTipo CHAR(1) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL,

	@IsVeicoloFuoriUso BIT = 0,
	@VeicoloFuoriUsoNumero VARCHAR(50) = NULL,
	@VeicoloFuoriUsoData DATE = NULL,

	@IdRaee CHAR(1) = NULL,

	-- Esito
	@IdEsito CHAR(1) = NULL,
	@QuantitaVerificata DECIMAL(18,2) = NULL,
	@DataFineTrasporto SMALLDATETIME = NULL,
	@IdCausaleRespingimento CHAR(1) = NULL,
	@CausaleRespingimentoAltro VARCHAR(100) = NULL,
	@IdUnitaMisuraQuantitaRespinta CHAR(2) = NULL,
	@QuantitaRespinta DECIMAL(18,2) = NULL,

	-- Materiale
	@IdMateriale CHAR(2) = NULL,
	@MaterialeDescrizione VARCHAR(200) = NULL,

	-- Provenienza
	@IdAttivitaProvenienza CHAR(1) = NULL,

	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0,
	@NessunaRegistrazioneAssociata BIT = 0
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: con un formulario attivo @IdDocumentoTrasportoTipo deve restare il Formulario; per un altro documento si cancella prima il formulario
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizzazione parametri obbligatori
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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);
		DECLARE @minData DATE = '19000101';
		DECLARE @maxData DATE = '20501231';

		-- Pre-calcolo range anno per confronti sargable
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@RegistrazioneData), 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(YEAR(@RegistrazioneData) + 1, 1, 1);

		DECLARE @idMovimento CHAR(16);
		DECLARE @idRegistro CHAR(16);
		DECLARE @lock TINYINT;
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @totaleQuantitaAssegnata DECIMAL(18,2);
		DECLARE @idRelazione CHAR(16);
		DECLARE @quantitaRelazione DECIMAL(18,2);
		DECLARE @quantitaResidua DECIMAL(18,2);
		DECLARE @isIntegrazioneFir BIT;
		DECLARE @isFormularioAssociato BIT;
		DECLARE @isEsito BIT;
		DECLARE @isMateriale BIT;
		DECLARE @isProduttore BIT;
		DECLARE @isTrasportatore BIT;
		DECLARE @isDestinatario BIT;
		DECLARE @isIntermediario BIT;
		DECLARE @isAttivitaRs BIT;
		DECLARE @isAttivitaProvenienza BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @conservazioneSostitutiva BIT;

		-- "Nessuna registrazione associata" vale solo per lo scarico a terzi (S, aT): procedura semplificata del
		-- RENTRI per i centri di raccolta. Sulle altre operazioni viene ignorata, salvo per le rettifiche, che la
		-- impostano sempre (uspRifiutiRegistrazioni_upd_Rettifica: non hanno mai relazioni proprie)
		IF @NessunaRegistrazioneAssociata = 1
			AND NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Id = @Id
					AND m.IdOperazione = 'S'
			)
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = @Id)
			SET @NessunaRegistrazioneAssociata = 0;

		-- Recupero dati registrazione
		SELECT
			@idMovimento = r.IdMovimento,
			@idRegistro = m.IdRegistro,
			@lock = r.Lock,
			@operazione = r.Operazione,
			@idOperazione = m.IdOperazione,
			@rentriIdentificativo = r.RentriIdentificativo,
			@rentriData = r.RentriData,
			@conservazioneSostitutiva = r.ConservazioneSostitutiva,
			@isIntegrazioneFir = o.IsIntegrazioneFir,
			@isFormularioAssociato = CAST(IIF(f.IdMovimento IS NOT NULL AND f.Lock < 2, 1, 0) AS BIT),
			@isEsito = o.IsEsito,
			@isMateriale = o.IsMateriale,
			@isProduttore = o.IsProduttore,
			@isTrasportatore = o.IsTrasportatore,
			@isDestinatario = o.IsDestinatario,
			@isIntermediario = o.IsIntermediario,
			@isAttivitaRs = o.IsAttivitaRs,
			@isAttivitaProvenienza = o.IsAttivitaProvenienza,
			@totaleQuantitaAssegnata = CASE
				WHEN @NessunaRegistrazioneAssociata = 1 THEN 0
				ELSE
					ISNULL((
						SELECT SUM(lq.Quantita)
						FROM
							dbo.tblRifiutiRegistrazioniRelazioni lq
							INNER JOIN dbo.tblRifiutiRegistrazioni rq ON lq.Id = rq.Id
						WHERE
							lq.IdParent = r.Id
							AND lq.Quantita > 0
							AND rq.Lock < 2
					), 0)
				END
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
		WHERE r.Id = @Id;

		-- Verifica che la registrazione esista
		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @idRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione già trasmessa a RENTRI non può più essere modificata in alcun modo
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Una registrazione portata/bloccata per la conservazione sostitutiva non può più essere modificata
		IF ISNULL(@conservazioneSostitutiva, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Normalizza @isMateriale: NULL (nessuna corrispondenza in tblRifiutiOperazioni) equivale a "non materiale"
		SET @isMateriale = ISNULL(@isMateriale, 0);

		-- Normalizzazione parametri
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdAttivitaProvenienza = NULLIF(LTRIM(RTRIM(@IdAttivitaProvenienza)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdUnitaMisura = ISNULL(@IdUnitaMisura, 'KG');
		SET @IdDocumentoTrasportoTipo = NULLIF(LTRIM(RTRIM(@IdDocumentoTrasportoTipo)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');
		SET @IdEsito = NULLIF(LTRIM(RTRIM(@IdEsito)), '');
		SET @IdCausaleRespingimento = NULLIF(LTRIM(RTRIM(@IdCausaleRespingimento)), '');

		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @ClassiPericolo = dbo.ufnStringhe_get_SenzaSpazi(@ClassiPericolo, 0, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 0, 1);
		SET @RegistrazioneNote = dbo.ufnStringhe_get_SenzaSpazi(@RegistrazioneNote, 0, 1);
		SET @VeicoloFuoriUsoNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@VeicoloFuoriUsoNumero, 0, 1));
		SET @CausaleRespingimentoAltro = dbo.ufnStringhe_get_SenzaSpazi(@CausaleRespingimentoAltro, 0, 1);

		IF @NessunaRegistrazioneAssociata = 1 SET @RegistrazioneAuto = 0;

		IF @RegistrazioneAuto = 1 AND (EXISTS(
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND
					(
						(
						[Data] = @RegistrazioneData
						AND Numero = @RegistrazioneNumero
						)
					OR Lock = 2
					)
		))
			SET @RinumeraRegistro = 1;

		IF @QuantitaVerificata = @Quantita
			SET @QuantitaVerificata = NULL;

		-- EER / StatoFisico / ClassiPericolo esclusivi con Materiale; l'unità di misura per il
		-- Materiale è sempre KG, a prescindere da cosa arrivi dal client (campo disabilitato in UI).
		IF @isMateriale = 1
		BEGIN
			SET @IdEer = NULL;
			SET @IdProvenienza = NULL;
			SET @IdStatoFisico = NULL;
			SET @ClassiPericolo = NULL;
			SET @EerDescrizione = NULL;
			SET @IdUnitaMisura = 'KG';
			IF @IdMateriale = 'AL'
				SET @MaterialeDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@MaterialeDescrizione, 0, 1);
			ELSE
				SET @MaterialeDescrizione = NULL;
		END
		ELSE
		BEGIN
			SET @IdMateriale = NULL;
			SET @MaterialeDescrizione = NULL;

			IF @IdEer LIKE '%99'
				SET @EerDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@EerDescrizione, 0, 1);
			ELSE
				SET @EerDescrizione = NULL;
		END

		-- Data inizio trasporto solo se integrazione FIR
		IF @isIntegrazioneFir = 0
			SET @DataInizioTrasporto = NULL;

		-- Attività RS
		IF @isAttivitaRs = 0 OR @IdAttivitaRs = '00'
			SET @IdAttivitaRs = NULL;

		-- Attività Provenienza
		IF @isAttivitaProvenienza = 0 OR @IdAttivitaProvenienza = '0'
			SET @IdAttivitaProvenienza = NULL;

		-- Autorizzazioni: azzera se il ruolo non è previsto per l'operazione, o se è "nessuna" (SediciZeri)
		IF @isProduttore = 0 OR @IdAutorizzazioneProduttoreDetentore = @idSediciZeri
			SET @IdAutorizzazioneProduttoreDetentore = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore1 = @idSediciZeri
			SET @IdAutorizzazioneTrasportatore1 = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore2 = @idSediciZeri OR @IdAutorizzazioneTrasportatore1 IS NULL
			SET @IdAutorizzazioneTrasportatore2 = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore3 = @idSediciZeri OR @IdAutorizzazioneTrasportatore2 IS NULL
			SET @IdAutorizzazioneTrasportatore3 = NULL;

		IF @isDestinatario = 0 OR @IdAutorizzazioneDestinatario = @idSediciZeri
			SET @IdAutorizzazioneDestinatario = NULL;

		-- Autorizzazioni intermediario: gestisce i valori delle 3 possibili autorizzazioni
		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario1 = @idSediciZeri
			SET @IdAutorizzazioneIntermediario1 = NULL;

		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario2 = @idSediciZeri OR @IdAutorizzazioneIntermediario1 IS NULL
			SET @IdAutorizzazioneIntermediario2 = NULL;

		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario3 = @idSediciZeri OR @IdAutorizzazioneIntermediario2 IS NULL
			SET @IdAutorizzazioneIntermediario3 = NULL;

		-- Veicoli fuori uso
		IF
			(
				@idOperazione <> 'Z' -- Carico di rifiuto ricevuti da terzi
				OR
				ISNULL(@IdEer, '') NOT IN('160104', '160106') -- EER per veicoli fuori uso
			)
		BEGIN
			SET @IsVeicoloFuoriUso = 0;
			SET @VeicoloFuoriUsoNumero = NULL;
			SET @VeicoloFuoriUsoData = NULL;
		END

		-- Categoria RAEE
		IF
			(
				@IdRaee = '0'
				OR
				@idOperazione NOT IN('S', 'Z')
				OR
				ISNULL(@IdEer, '') NOT IN('200121', '200123', '200135', '200136', '160210', '160211', '160212', '160213', '160214', '160215', '160216')
			)
		BEGIN
			SET @IdRaee = NULL;
		END

		-- Esito
		IF @isEsito = 0 OR @IdEsito = '0'
		BEGIN
			SET @IdEsito = NULL;
			SET @QuantitaVerificata = NULL;
			SET @DataFineTrasporto = NULL;
			SET @IdCausaleRespingimento = NULL;
			SET @CausaleRespingimentoAltro = NULL;
			SET @QuantitaRespinta = NULL;
			SET @IdUnitaMisuraQuantitaRespinta = NULL;
		END
		ELSE
		BEGIN
			IF @IdEsito = 'A' SET @IdCausaleRespingimento = NULL;
			IF @IdEsito = 'A' SET @CausaleRespingimentoAltro = NULL;
			IF @IdEsito = 'A' SET @IdUnitaMisuraQuantitaRespinta = NULL;
			IF @IdEsito = 'A' SET @QuantitaRespinta = NULL;
			IF @IdEsito = 'R' SET @QuantitaRespinta = @Quantita;
			IF @IdEsito = 'R' SET @IdUnitaMisuraQuantitaRespinta = @IdUnitaMisura;
			IF @IdEsito = 'R' SET @QuantitaVerificata = NULL;
			IF @IdEsito = 'P' SET @IdUnitaMisuraQuantitaRespinta = ISNULL(@IdUnitaMisuraQuantitaRespinta, 'KG');
			IF ISNULL(@IdCausaleRespingimento, '') <> 'A' SET @CausaleRespingimentoAltro = NULL;
		END

		IF @isFormularioAssociato = 1 AND @FormularioNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questa registrazione è associata ad un formulario. Il numero deve essere valorizzato';
			GOTO BRANCH_END;
		END

		-- Con un formulario attivo il documento di trasporto resta il formulario: per indicare un Allegato VII o un
		-- Allegato I-B l'utente cancella prima il formulario, con una scelta consapevole e mai in automatico. Il
		-- formulario cancellato (Lock 4) resta sul movimento e non si tocca
		IF @isFormularioAssociato = 1 AND ISNULL(@IdDocumentoTrasportoTipo, 'F') <> 'F'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è associata a un formulario: per indicare un altro documento di trasporto cancellare prima il formulario';
			GOTO BRANCH_END;
		END

		IF @isIntegrazioneFir = 1
		BEGIN
			-- Verifica l'unicità del numero di formulario solo contro registrazioni attive
			-- (r.Lock < 2), non contro il solo elenco dei formulari: un formulario può
			-- esistere senza alcuna registrazione associata (creato standalone da Formulari),
			-- nel qual caso non deve bloccare il riutilizzo del suo numero.
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Id <> @Id
					AND m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND m.FormularioNumero = @FormularioNumero
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''altra registrazione con lo stesso numero di formulario è già presente';
				GOTO BRANCH_END;
			END
		END

		IF @RegistrazioneNumero + @RegistrazioneAuto > 999999
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di registrazione non può essere superiore a 999.999';
			GOTO BRANCH_END;
		END

		-- Controllo EER/stato fisico/unità di misura nelle relazioni
		IF @lock < 2 AND @idOperazione <> 'K'
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					-- Valori effettivi della registrazione associata (ultima rettifica di correzione
					-- confermata, l'originale non viene mai modificato - viewRifiutiRegistrazioniEffettive)
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					(
					l.Id = @Id
					OR l.IdParent = @Id
					)
					AND mp.IdOperazione <> 'M'
					AND
						(
						v.IdEer <> @IdEer
						OR v.IdStatoFisico <> @IdStatoFisico
						OR v.IdUnitaMisura <> @IdUnitaMisura
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è associata ad altre con differente EER e/o stato fisico e/o unità di misura';
				GOTO BRANCH_END;
			END
		END

		-- I controlli sul numero di registrazione (duplicato, ordine rispetto alla data) e il calcolo della
		-- rinumerazione sono dentro la transazione, dopo il blocco sul registro: vedi sotto

		-- Controllo data relazioni padre
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				WHERE
					l.Id = @Id
					AND
						(
						rp.[Data] < @RegistrazioneData
						OR
							(
							rp.[Data] = @RegistrazioneData
							AND rp.Numero < @RegistrazioneNumero
							)
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è associata ad altre con numero e/o data di registrazione inferiore';
				GOTO BRANCH_END;
			END
		END

		-- Controllo quantità già scaricata (l.Id = @Id: verifica che @Id, come figlio, non scenda sotto quanto già scaricato dal padre)
		IF @lock < 2
		BEGIN
			IF @Quantita < ISNULL((
				SELECT SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
				WHERE
					l.Id = @Id
					AND l.Quantita > 0
					AND rp.Lock < 2
					-- Uno scarico annullato non consuma piu' la registrazione (relazione mantenuta per la stampa)
					AND vp.IsAnnullata = 0
			), 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità non può essere inferiore a quella già associata ad altre registrazioni';
				GOTO BRANCH_END;
			END
		END

		-- Verifica quantità superiore disponibile
		IF @NessunaRegistrazioneAssociata = 0 AND EXISTS (SELECT 1
		FROM dbo.tblRifiutiOperazioniRelazioni
		WHERE Id = @idOperazione) AND @RegistrazioneAuto = 0
		BEGIN
			IF dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore(
				@Id, @Quantita, @RegistrazioneData, @RegistrazioneNumero,
				@IdEer, @IdStatoFisico, @IdUnitaMisura, 0) > 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità registrata è superiore a quella disponibile nelle registrazioni associate';
				GOTO BRANCH_END;
			END
		END

		-- Verifica se necessario aggiornare il log
		DECLARE @aggiornaLog BIT = 0;
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
					LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000')
						OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0')
						OR ISNULL(r.IdMateriale, '00') <> ISNULL(@IdMateriale, '00')
						OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00')
						OR ISNULL(r.Numero, -1) <> ISNULL(@RegistrazioneNumero, -1)
						OR ISNULL(r.[Data], @minData) <> ISNULL(@RegistrazioneData, @minData)
						OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0')
						OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0)
						OR ISNULL(r.QuantitaVerificata, 0) <> ISNULL(@QuantitaVerificata, 0)
						OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '')
						OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData)
						OR ISNULL(r.DataFineTrasporto, @minData) <> ISNULL(@DataFineTrasporto, @minData)
						)
			)
				SET @aggiornaLog = 1;
			ELSE IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp1 ON m.Id = mp1.Id AND mp1.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(mp1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneProduttoreDetentore, @idSediciZeri)
						OR ISNULL(md.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneDestinatario, @idSediciZeri)
						OR ISNULL(mt1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneTrasportatore1, @idSediciZeri)
						OR ISNULL(mi1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneIntermediario1, @idSediciZeri)
						)
			)
				SET @aggiornaLog = 1;
		END

		-- Calcola la soglia per la pulizia del log (fuori dalla transazione, intenzionale)
		-- Se ci sono 10 o meno record @dataLogMin resta NULL: il DELETE successivo non elimina nulla (comportamento corretto)
		DECLARE @dataLogMin DATETIME2(0);

		-- Lettura IdUtente fuori dalla transazione (intenzionale)
		DECLARE @idUtente CHAR(16);

		IF @aggiornaLog = 1
		BEGIN
			SELECT TOP 1
				@dataLogMin = [Data]
			FROM (
				SELECT
					[Data],
					Pos = ROW_NUMBER() OVER (ORDER BY [Data] DESC)
				FROM dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento) t
			WHERE t.Pos > 9
			ORDER BY Pos;

			SELECT @idUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		BEGIN TRANSACTION;

			-- Numerazione: il registro viene bloccato per tutta la transazione (UPDLOCK/HOLDLOCK sulla sua sola
			-- riga), cosi' due salvataggi contemporanei sullo stesso registro si mettono in fila e non possono
			-- leggere lo stesso ultimo numero. Registri diversi e letture non aspettano. Il registro si blocca
			-- sempre per primo, prima delle relazioni (stesso ordine in _upd_Rettifica e _upd_Annullamento)
			DECLARE @registroBloccato CHAR(16) = (
				SELECT Id
				FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
				WHERE Id = @idRegistro);

			-- Controllo numero registrazione duplicato (sargable)
			IF @RinumeraRegistro = 0
			BEGIN
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
						AND r.Numero = @RegistrazioneNumero
						AND r.Id <> @Id
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''altra registrazione con lo stesso numero è già presente';
					GOTO BRANCH_END;
				END
			END

			-- Controllo numero > con data < (sargable)
			IF @RinumeraRegistro = 0
			BEGIN
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
						AND r.Numero > @RegistrazioneNumero
						AND r.[Data] < @RegistrazioneData
						AND r.Id <> @Id
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Almeno una registrazione con numero maggiore e data inferiore a quella indicata è già presente';
					GOTO BRANCH_END;
				END
			END

			-- Controllo numero < con data > (sargable)
			IF @RinumeraRegistro = 0
			BEGIN
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
						AND r.Numero < @RegistrazioneNumero
						AND r.[Data] > @RegistrazioneData
						AND r.Id <> @Id
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Almeno una registrazione con numero inferiore e data maggiore a quella indicata è già presente';
					GOTO BRANCH_END;
				END
			END

			-- Rinumerazione registro (sargable)
			IF @RinumeraRegistro = 1
			BEGIN
				DECLARE @isLibero1 BIT = 0;
				DECLARE @isLibero2 BIT = 0;

				IF @lock = 2
					SET @RegistrazioneNumero = 1 +
						(SELECT ISNULL(MAX(r.Numero), 0)
						 FROM
							 dbo.tblRifiutiRegistrazioni r
							 INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
						 WHERE
							 r.Lock < 2
							 AND m.IdRegistro = @idRegistro
							 AND r.[Data] <= @RegistrazioneData
							 AND r.[Data] >= @annoInizio
							 AND r.[Data] < @annoFine
						);

				SET @isLibero1 = IIF(EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.Numero = @RegistrazioneNumero
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
				), 0, 1);

				SET @isLibero2 = IIF(EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.Numero = @RegistrazioneNumero + 1
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
				), 0, 1);
			END

			IF @RinumeraRegistro = 1
			BEGIN
				UPDATE r
				SET Numero = Numero + 1 + IIF(@lock = 2 AND @RegistrazioneAuto = 1 AND @isLibero1 = 0, 1, 0)
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND
						(
						r.[Data] > @RegistrazioneData
						OR
							(
							r.[Data] = @RegistrazioneData
							AND r.Numero > @RegistrazioneNumero
							)
						)
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND
						(
							(
							@lock < 2
							AND @isLibero2 = 0
							)
						OR
							(
							@lock = 2
							AND @RegistrazioneAuto = 1
							AND
								(
								@isLibero1 = 0
								OR @isLibero2 = 0
								)
							)
						OR
							(
							@lock = 2
							AND @RegistrazioneAuto = 0
							AND @isLibero1 = 0
							)
						);
			END

			-- Produttori
			DELETE dbo.tblRifiutiMovimentiProduttori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneProduttoreDetentore IS NOT NULL
			BEGIN
				IF EXISTS (SELECT 1
				FROM dbo.tblSedi
				WHERE Id = @IdAutorizzazioneProduttoreDetentore)
				BEGIN
					DECLARE @idSede CHAR(16) = @IdAutorizzazioneProduttoreDetentore;
					SET @IdAutorizzazioneProduttoreDetentore = NULL;

					SELECT @IdAutorizzazioneProduttoreDetentore = Id
					FROM dbo.tblRifiutiAutorizzazioni
					WHERE
						IdSede = @idSede
						AND Nessuna = 1
						AND Lock = 0;

					IF @IdAutorizzazioneProduttoreDetentore IS NULL
					BEGIN
						EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @IdAutorizzazioneProduttoreDetentore OUTPUT;

						INSERT dbo.tblRifiutiAutorizzazioni
							(Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
						VALUES
							(@IdAutorizzazioneProduttoreDetentore, @idSede, 'P', @minData, @maxData, 1, 0, 0);
					END
				END

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneProduttoreDetentore, @Quantita, 0);
			END

			-- Destinatari
			DELETE dbo.tblRifiutiMovimentiDestinatari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneDestinatario IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneDestinatario, 0);
			END

			-- Trasportatori
			DELETE dbo.tblRifiutiMovimentiTrasportatori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneTrasportatore1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneTrasportatore1, 0);

				IF @IdAutorizzazioneTrasportatore2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneTrasportatore2, 1);

					IF @IdAutorizzazioneTrasportatore3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneTrasportatore3, 2);
					END
				END
			END

			-- Intermediari
			DELETE dbo.tblRifiutiMovimentiIntermediari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneIntermediario1, 0);

				IF @IdAutorizzazioneIntermediario2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneIntermediario2, 1);

					IF @IdAutorizzazioneIntermediario3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneIntermediario3, 2);
					END
				END
			END

			-- Relazioni quantità
			IF @Quantita = 0 OR @NessunaRegistrazioneAssociata = 1
			BEGIN
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @Id;
			END

			IF @NessunaRegistrazioneAssociata = 0 AND @Quantita > 0 AND @Quantita <> @totaleQuantitaAssegnata
			BEGIN
				UPDATE dbo.tblRifiutiRegistrazioniRelazioni
				SET Quantita = 0
				WHERE IdParent = @Id;

				SET @quantitaRelazione = @Quantita;

				-- Distribuzione quantità sulle relazioni ordinate per Pos
				DECLARE c CURSOR FAST_FORWARD FOR
					SELECT
						l.Id,
						-- Valori effettivi (viewRifiutiRegistrazioniEffettive): quantita' dell'ultima correzione
						-- confermata, 0 se annullata; uno scarico annullato non consuma piu' i suoi carichi
						QuantitaResidua = v2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v2 ON r.Id = v2.Id
						LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
								INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
								INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vpq ON pq.Id = vpq.Id
							WHERE
								pq.Lock < 2
								AND vpq.Quantita > 0
							GROUP BY lq.Id
						) a ON l.Id = a.Id
					WHERE l.IdParent = @Id
					ORDER BY l.Pos;

				OPEN c;
				FETCH c INTO @idRelazione, @quantitaResidua;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @quantitaRelazione > 0
					BEGIN
						IF @quantitaRelazione >= @quantitaResidua
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaResidua
							WHERE
								IdParent = @Id
								AND Id = @idRelazione;
							SET @quantitaRelazione = @quantitaRelazione - @quantitaResidua;
						END
						ELSE
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaRelazione
							WHERE
								IdParent = @Id
								AND Id = @idRelazione;
							SET @quantitaRelazione = 0;
						END
					END
					FETCH c INTO @idRelazione, @quantitaResidua;
				END

				CLOSE c;
				DEALLOCATE c;
			END

			DELETE dbo.tblRifiutiRegistrazioniRelazioni
			WHERE
				IdParent = @Id
				AND Quantita = 0;

			-- Generazione registrazione automatica di compensazione
			IF @quantitaRelazione > 0 AND @RegistrazioneAuto = 1
			BEGIN
				DECLARE @idMovimentoAuto CHAR(16);
				DECLARE @idRegistrazioneAuto CHAR(16);

				EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimentoAuto OUTPUT;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRegistrazioneAuto OUTPUT;

				INSERT dbo.tblRifiutiMovimenti (Id, IdRegistro, IdOperazione, IdEer, IdProvenienza, IdStatoFisico, IdUnitaMisura, Quantita)
				VALUES (@idMovimentoAuto, @idRegistro, 'C', @IdEer, @IdProvenienza, @IdStatoFisico, @IdUnitaMisura, @quantitaRelazione);

				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, [Data], Numero, Lock)
				VALUES
					(@idRegistrazioneAuto, @idMovimentoAuto, 'C',
					 @RegistrazioneData, @RegistrazioneNumero, 0);

				INSERT dbo.tblRifiutiRegistrazioniRelazioni
					(Id, IdParent, Operazione, Quantita, Pos)
				SELECT
					@idRegistrazioneAuto, @Id, 'S', @quantitaRelazione,
					ISNULL(MAX(Pos), -1) + 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @Id;

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimentoAuto, @IdAutorizzazioneProduttoreDetentore, @quantitaRelazione, 0);

				INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
				SELECT @idMovimentoAuto, c.Id
				FROM
					dbo.tblRifiutiClassiPericolo c
					INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

				INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
				SELECT TOP 3 @idRegistrazioneAuto, e.Id
				FROM
					dbo.tblEtichette e
					INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

				SET @RegistrazioneNumero = @RegistrazioneNumero + 1;
			END

			-- Classi di pericolo
			DELETE dbo.tblRifiutiMovimentiClassiPericolo
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT @idMovimento, c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Etichette
			DELETE dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
			SELECT TOP 3 @Id, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			-- Aggiornamento log storico movimento (snapshot stato corrente prima degli UPDATE)
			-- @dataLogMin = NULL se <= 10 record: il DELETE non elimina nulla (comportamento corretto)
			IF @aggiornaLog = 1
			BEGIN
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND [Data] <= @dataLogMin;

				INSERT dbo.tblRifiutiMovimentiLog
					(Id, [Data], IdUtente,
					 IdEer, IdStatoFisico, IdMateriale, IdAttivita, IdUnitaMisura,
					 Quantita, QuantitaVerificata, IdAutorizzazioneProduttoreDetentore, IdAutorizzazioneDestinatario,
					 IdAutorizzazioneTrasportatore1, IdAutorizzazioneIntermediario1,
					 RegistrazioneNumero, RegistrazioneData, FormularioNumero, DataInizioTrasporto, DataFineTrasporto)
				SELECT
					m.Id, GETDATE(), @idUtente,
					m.IdEer, m.IdStatoFisico, r.IdMateriale, m.IdAttivita, m.IdUnitaMisura,
					m.Quantita, r.QuantitaVerificata, mp.IdAutorizzazione, md.IdAutorizzazione,
					mt.IdAutorizzazione, mi.IdAutorizzazione,
					r.Numero, r.[Data], m.FormularioNumero, m.DataInizioTrasporto, r.DataFineTrasporto
				FROM
					dbo.tblRifiutiMovimenti m
					LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
					LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				WHERE m.Id = @idMovimento;
			END

			-- Azzera FormularioNumero se il documento non è un formulario
			IF ISNULL(@IdDocumentoTrasportoTipo, 'F') <> 'F'
				SET @FormularioNumero = NULL;

			-- Nessuna cancellazione del formulario: con un formulario attivo il tipo di documento non cambia (controllo
			-- sopra), uno cancellato resta com'è (prima la SP lo eliminava, ma i trasporti e le etichette del formulario ne
			-- bloccavano la cancellazione con un errore di chiave esterna)

			-- Aggiornamento registrazione
			UPDATE dbo.tblRifiutiRegistrazioni
			SET
				[Data] = @RegistrazioneData,
				Numero = @RegistrazioneNumero,
				IdTrasportoTransfrontalieroTipo = IIF(@IdDocumentoTrasportoTipo <> 'F', @IdDocumentoTrasportoTipo, NULL),
				Note = @RegistrazioneNote,
				Etichette = dbo.ufnRifiutiRegistrazioni_get_Etichette(Id),
				VeicoloFuoriUso = @IsVeicoloFuoriUso,
				VeicoloFuoriUsoData = @VeicoloFuoriUsoData,
				VeicoloFuoriUsoNumero = @VeicoloFuoriUsoNumero,
				IdRaee = @IdRaee,
				IdEsito = @IdEsito,
				IdCausaleRespingimento = @IdCausaleRespingimento,
				CausaleRespingimentoAltro = @CausaleRespingimentoAltro,
				QuantitaVerificata = @QuantitaVerificata,
				IdUnitaMisuraQuantitaRespinta = @IdUnitaMisuraQuantitaRespinta,
				QuantitaRespinta = @QuantitaRespinta,
				DataFineTrasporto = @DataFineTrasporto,
				IdMateriale = @IdMateriale,
				MaterialeDescrizione = @MaterialeDescrizione,
				IdAttivitaProvenienza = @IdAttivitaProvenienza,
				Lock = 0
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione non trovata o già modificata da un altro utente';
				GOTO BRANCH_END;
			END

			-- Aggiornamento movimento
			UPDATE m
			SET
				IdEer = @IdEer,
				IdProvenienza = @IdProvenienza,
				EerDescrizione = @EerDescrizione,
				IdStatoFisico = @IdStatoFisico,
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				Quantita = @Quantita,
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede,
				-- Con il formulario associato, il numero assegnato dal RENTRI (formulario digitale o cartaceo vidimato) o da
				-- Vi.Vi.FIR (formulario unico) resta quello salvato, come in uspRifiutiFormulari_upd
				FormularioNumero = CASE
					WHEN @isFormularioAssociato = 1
						AND (m.RentriFormularioStato IS NOT NULL OR ISNULL(m.RentriFormularioCartaceo, 0) = 1 OR ISNULL(m.ViviFirVidimato, 0) = 1)
					THEN m.FormularioNumero
					ELSE @FormularioNumero
				END,
				DataInizioTrasporto = @DataInizioTrasporto,
				Note = @UtenteNote
			FROM
				dbo.tblRifiutiMovimenti m
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON mp.IdAutorizzazione = ap.Id
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON md.IdAutorizzazione = ad.Id
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON mt.IdAutorizzazione = ar.Id
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON mi.IdAutorizzazione = ai.Id
			WHERE m.Id = @idMovimento;

			-- Magazzino EoW allineato al registro operativo: una M con quantita' ridotta o materiale cambiato
			-- riduce/rimuove le proprie allocazioni sui lotti (nessun effetto senza allocazioni o su una
			-- rettifica, che non ne ha mai)
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @Id;

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione (intenzionale)
		IF @lock > 0 OR @aggiornaLog = 1
		BEGIN
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
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

	SELECT ReturnValue = @returnValue;
END;
GO

-- ===== sql\procedures\uspSYS_del_RegistroCascade.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_RegistroCascade
    @IdRegistro CHAR(16)    = NULL,
    @Conferma   VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
        SET @Conferma   = NULLIF(LTRIM(RTRIM(@Conferma)),   '');

        IF @IdRegistro IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistri WHERE Id = @IdRegistro)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il registro indicato non esiste';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). A differenza di
        -- una sede, un registro non possiede etichette/autorizzazioni proprie (sono risorse della
        -- sede, non del registro): non vengono quindi mai toccate da questa SP, solo scollegate
        -- dalle proprie righe di giunzione (che appartengono ai record cancellati, non alla
        -- risorsa condivisa).
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro = @IdRegistro;
        SELECT Id INTO #RifiutiMovimenti FROM dbo.tblRifiutiMovimenti WHERE IdRegistro = @IdRegistro;
        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiSediProduzione WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette           WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi  WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: il registro non ha più alcun legame con lotti/allocazioni EoW (che
            -- referenziano solo Sede+Materiale), ma le sue Registrazioni in cancellazione possono
            -- essere referenziate da tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL,
            -- parte della PK composta con IdLotto) - non azzerabile, va rimossa la riga di collegamento.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiRegistrazioniRelazioni.IdParent è NOT NULL: una registrazione di un ALTRO
            -- registro (non in cancellazione) può avere come genitore una registrazione di questo
            -- registro. Non essendo azzerabile, la riga di relazione va cancellata anche quando
            -- appartiene a quell'altra registrazione - perde il collegamento e la relativa
            -- Quantita/Pos. Stessa logica "UPDATE=NULL dove possibile, DELETE dove NOT NULL"
            -- applicata alle risorse condivise di uspSYS_del_SedeInternaCascade.
            DECLARE @relazioniEsterneRimosse INT = (
                SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioniRelazioni
                WHERE IdParent IN (SELECT Id FROM #RifiutiRegistrazioni)
                  AND Id NOT IN (SELECT Id FROM #RifiutiRegistrazioni)
            );
            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRifiutiLimiti.IdRegistro è nullable e il Limite appartiene alla Sede (non al
            -- Registro, non toccato da questa SP): cancellando solo il Registro il Limite resta
            -- valido, perde solo lo scoping specifico al registro (torna a valere sull'intera sede).
            DECLARE @limitiScollegati INT;
            UPDATE dbo.tblRifiutiLimiti SET IdRegistro = NULL WHERE IdRegistro = @IdRegistro;
            SET @limitiScollegati = @@ROWCOUNT;

            -- tblRentriRegistri è 1:1 a chiave condivisa (Id NOT NULL, nessun ON DELETE CASCADE):
            -- va rimosso prima, altrimenti la DELETE sottostante fallisce per violazione FK.
            DELETE FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro;

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id = @IdRegistro;

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT @IdRegistro
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #RifiutiMovimenti),
            ', Modelli rimossi: ', (SELECT COUNT(*) FROM #RifiutiModelli),
            ', Formulari rimossi: ', (SELECT COUNT(*) FROM #RifiutiFormulari),
            ', Registrazioni rimosse: ', (SELECT COUNT(*) FROM #RifiutiRegistrazioni),
            '. Relazioni di altre registrazioni scollegate: ', @relazioniEsterneRimosse,
            '. Limiti rifiuti scollegati dal registro: ', @limitiScollegati, '.');

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

-- ===== sql\procedures\uspSYS_del_RifiutiMovimentiCascade.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_RifiutiMovimentiCascade
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Conferma = dbo.ufnStringhe_get_SenzaSpazi(@Conferma, 0, 1);

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        SELECT Id INTO #tm FROM dbo.tblRifiutiMovimenti;
        SELECT Id INTO #tr FROM dbo.tblRifiutiRegistrazioni;
        SELECT Id INTO #tf FROM dbo.tblRifiutiFormulari;

        BEGIN TRANSACTION;
            DELETE dbo.tblRifiutiRegistrazioniRelazioni  WHERE Id       IN (SELECT Id FROM #tr) OR IdParent IN (SELECT Id FROM #tr);
            DELETE dbo.tblRifiutiMovimentiClassiPericolo WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiTrasportatori  WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiDestinatari    WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiIntermediari   WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiProduttori     WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiSediProduzione WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiFormulariEtichette      WHERE Id       IN (SELECT Id FROM #tf);
            -- Mancanti nell'originale uspRifiutiMovimenti_del_All: sono dettagli 1:1 a chiave
            -- condivisa (Id NOT NULL) di tblRifiutiFormulari, quindi bloccano la DELETE successiva
            -- su tblRifiutiFormulari con un errore FK se anche una sola riga esiste.
            DELETE dbo.tblRifiutiFormulariTrasportiFerroviari WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiFormulariTrasportiMarittimi  WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiFormulariTrasportiTerresti   WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiRegistrazioniEtichette  WHERE Id       IN (SELECT Id FROM #tr);
            -- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione referenzia le
            -- Registrazioni che stanno per essere cancellate ed è NOT NULL (parte della PK
            -- composta con IdLotto) - non azzerabile come il vecchio tblEoWMovimenti.IdRegistrazione
            -- (nullable), va rimossa la riga di collegamento; i Lotti/Allocazioni restano intatti.
            DELETE dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #tr);
            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va svuotata prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se esiste anche una sola rettifica.
            DELETE dbo.tblRentriRegistrazioniRettifiche;
            DELETE dbo.tblRifiutiFormulari;
            -- tblDiwassAllegatiVii.IdRegistrazione: gli Allegati VII restano, perdono la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IS NOT NULL;
            DELETE dbo.tblRifiutiRegistrazioni;
            DELETE dbo.tblRifiutiMovimentiLog;
            DELETE dbo.tblRifiutiMovimenti;
            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #tm),
            ', Registrazioni rimosse: ', (SELECT COUNT(*) FROM #tr),
            ', Formulari rimossi: ', (SELECT COUNT(*) FROM #tf), '.');

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

-- ===== sql\procedures\uspSYS_del_SedeEsternaCascade.sql
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
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino su una persona o un oggetto della cascata: perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

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
            -- Indirizzi di intervento dei formulari unici: dei movimenti cancellati e, negli altri movimenti, quelli
            -- che sono una delle sedi cancellate
            DELETE FROM dbo.tblRifiutiMovimentiSediProduzione WHERE Id IN (SELECT Id FROM #RifiutiMovimenti) OR IdSede IN (SELECT Id FROM #Sedi);

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
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiViiSoggetti.IdSede: le sedi cancellate escono dagli Allegati VII DIWASS preparati in Ecomatico;
            -- in quelli ricevuti da DIWASS il soggetto resta con nome e indirizzo letti da DIWASS
            UPDATE x SET IdSede = NULL FROM dbo.tblDiwassAllegatiViiSoggetti x INNER JOIN dbo.tblDiwassAllegatiVii a ON x.Id = a.Id WHERE x.IdSede IN (SELECT Id FROM #Sedi) AND a.Ricevuto = 1;
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE IdSede IN (SELECT Id FROM #Sedi);
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

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
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
GO

-- ===== sql\procedures\uspSYS_del_SedeInternaCascade.sql
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
            UPDATE dbo.tblImportiServizi SET IdSedeInterna = NULL WHERE IdSedeInterna IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino di ALTRE aziende su un articolo della cascata (non previsto): perdono l'articolo
            DELETE FROM dbo.tblImportiRigheMagazzino WHERE IdArticolo IN (SELECT Id FROM #MagArticoli);
            -- Righe di listino di ALTRE aziende su una persona o un oggetto della cascata (condivisi): perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);
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
            -- Indirizzi di intervento dei formulari unici: dei movimenti cancellati e, negli altri movimenti, quelli
            -- che sono una delle sedi cancellate
            DELETE FROM dbo.tblRifiutiMovimentiSediProduzione WHERE Id IN (SELECT Id FROM #RifiutiMovimenti) OR IdSede IN (SELECT Id FROM #Sedi);

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
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- Allegati VII DIWASS delle aziende cancellate (con i soggetti), soggetti delle sedi cancellate negli altri
            -- Allegati VII, codici e ruoli di firma ricordati per le aziende
            SELECT Id INTO #DiwassAllegatiVii FROM dbo.tblDiwassAllegatiVii WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiViiConferme WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii);
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiVii WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii);
            DELETE FROM dbo.tblDiwassCodiciRifiutiUsati WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassFirmeRuoli WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
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

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediReport WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            -- Associazione alla credenziale DIWASS prima di tblSediInterne (FK su IdAziendaInterna): la credenziale
            -- è del dominio e resta
            DELETE FROM dbo.tblDiwassCredenzialiAziende WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            -- Lo stesso per la credenziale Vi.Vi.FIR (formulario unico degli spurghisti)
            DELETE FROM dbo.tblViviFirCredenzialiAziende WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
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
                UNION SELECT Id FROM #DiwassAllegatiVii
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

-- ===== sql\procedures\uspSedi_del.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0,
	@InternaEsterna CHAR(1) = NULL,
	@IdTipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @InternaEsterna = NULLIF(LTRIM(RTRIM(@InternaEsterna)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');

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
		IF @InternaEsterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @InternaEsterna non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idFunzione CHAR(3) = IIF(@InternaEsterna = 'I', 'AZI', 'ANS');
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
				SET @returnMessage = 'Un''azienda non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			IF @InternaEsterna = 'I'
			BEGIN
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

				IF EXISTS (
					SELECT 1
					FROM dbo.tblSediEsterne e
					INNER JOIN dbo.tblSedi s ON e.Id = s.Id
					WHERE
						e.IdSedeInterna = @Id
						AND s.Lock = 0
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Un''azienda che ha sedi associate non può essere cancellata';
					GOTO BRANCH_END;
				END
			END

			IF @InternaEsterna = 'E'
			BEGIN
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
				-- Indirizzo di intervento di un formulario unico (art. 230, comma 5)
				OR EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE IdSede = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda (solo sedi interne);
			-- Lotti/Righe hanno IdSede = sede operativa (può essere una sede figlia);
			-- IdSede del DDT è sempre una sede interna (fissata alla creazione)
			IF @InternaEsterna = 'I' AND (
				EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE IdSede = @Id AND Lock = 0)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE IdSede = @Id AND Lock = 0)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id AND Lock = 0)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdSede = @Id)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdSede = @Id)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdSede = @Id)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata al modulo Magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- DDT: mittente/destinatario/trasportatore sono campi liberi della testata,
			-- possono essere sedi esterne o interne
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino (mittente/destinatario/trasportatore) non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				-- Per sicurezza: se la sede cancellata era una sede figlia (IdParent valorizzato)
				-- con UnitaLocale=true, il genitore eredita il flag, così il gruppo non resta mai
				-- senza nessuna sede attiva con UnitaLocale=true.
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
				-- Indirizzo di intervento di un formulario unico (art. 230, comma 5)
				OR EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE IdSede = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
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
					IdMittente = @Id
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

				DELETE dbo.tblRifiutiAutorizzazioni
				WHERE IdSede = @Id;
				DELETE dbo.tblRifiutiRegistri
				WHERE IdSede = @Id;
				DELETE dbo.tblTipi
				WHERE IdSede = @Id;
				DELETE dbo.tblSediEsterne
				WHERE IdSedeInterna = @Id;
				DELETE dbo.tblSediInterne
				WHERE Id = @Id;
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
GO

-- ===== sql\procedures\uspSedi_del_SediEsterne.sql
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
				-- Indirizzo di intervento di un formulario unico (art. 230, comma 5)
				OR EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE IdSede = @Id)
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
					WHERE i.Lock = 0 AND @Id IN (v.IdRichiedenteParent, v.IdRichiedente)
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
				-- Indirizzo di intervento di un formulario unico (art. 230, comma 5)
				OR EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE IdSede = @Id)
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
GO

-- ===== sql\procedures\uspSedi_del_SediInterne.sql
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
					WHERE i.Lock = 0 AND @Id IN (v.IdRichiedenteParent, v.IdRichiedente, v.IdSedeInterna)
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
				-- Indirizzo di intervento di un formulario unico (art. 230, comma 5)
				OR EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE IdSede = @Id)
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
				-- Indirizzo di intervento di un formulario unico (art. 230, comma 5)
				OR EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiSediProduzione
				WHERE IdSede = @Id)
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
				DELETE dbo.tblSediReport
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

-- ===== sql\procedures\uspViviFirAziende_get.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_get]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = e.IdDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			a.IdCredenziale,
			-- Esito dell'ultima verifica (uspViviFirAziende_upd_Verifica)
			a.IdSoggetto,
			a.Soggetto,
			a.Blocco,
			a.DataVerifica
		FROM
			dbo.tblSedi s
			LEFT JOIN dbo.tblViviFirCredenzialiAziende a ON s.Id = a.IdAziendaInterna
		WHERE s.Id = @IdAziendaInterna;

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
GO

-- ===== sql\procedures\uspViviFirAziende_get_Credenziali_SelectList.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali Vi.Vi.FIR attive del dominio della sessione, da associare a un'azienda in Vivifir > Aziende. La prima voce
-- "(Nessuna)" toglie l'associazione; @Search filtra per nome o ClientId
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_get_Credenziali_SelectList]
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- credenziale selezionata: sempre presente, anche se non combacia con @Search

			SELECT
				c.Id,
				[Text] = CAST(c.Nome + ISNULL(' (' + h.ClientId + ')', '') AS VARCHAR(200)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblViviFirCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
			WHERE
				e.Id = @IdSessione
				AND c.Id = @IdSelected
			UNION ALL -- altre credenziali attive del dominio, con il ClientId per distinguerle

			SELECT
				c.Id,
				[Text] = CAST(c.Nome + ISNULL(' (' + h.ClientId + ')', '') AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblViviFirCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
			WHERE
				e.Id = @IdSessione
				AND c.Lock = 0
				AND c.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR c.Nome LIKE '%' + @Search + '%'
					OR h.ClientId COLLATE DATABASE_DEFAULT LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20
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
GO

-- ===== sql\procedures\uspViviFirAziende_get_Esportazione.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Vivifir > Aziende (mai la chiave di autenticazione): righe per l'esportazione dell'elenco in Excel e in CSV
-- (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspViviFirAziende_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspViviFirAziende_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Azienda] = s.NomeCompleto,
			[Indirizzo] = s.IndirizzoCompleto,
			[Credenziale] = c.Nome,
			[ClientId] = h.ClientId,
			[Soggetto Vi.Vi.FIR] = a.Soggetto,
			[Blocco] = a.Blocco,
			[Verifica] = a.DataVerifica
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			LEFT JOIN dbo.tblViviFirCredenzialiAziende a ON s.Id = a.IdAziendaInterna
			LEFT JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
			LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
		WHERE
			e.Id = @IdSessione
			AND i.IdDominio = e.IdDominio
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				OR c.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto
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
GO

-- ===== sql\procedures\uspViviFirAziende_get_List.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Vivifir > Aziende: aziende interne del dominio visibili all'utente, con la credenziale Vi.Vi.FIR associata (come
-- Rentri > Sedi per le credenziali RENTRI). Pagina di configurazione: nessun contesto azienda/sede
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_get_List]
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			CredenzialeNome = c.Nome,
			h.ClientId,
			-- Esito dell'ultima verifica: soggetto Vi.Vi.FIR e blocco del formulario unico (art. 230, comma 5)
			a.Soggetto,
			a.Blocco,
			a.DataVerifica,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			LEFT JOIN dbo.tblViviFirCredenzialiAziende a ON s.Id = a.IdAziendaInterna
			LEFT JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
			LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
		WHERE
			e.Id = @IdSessione
			AND i.IdDominio = e.IdDominio
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				OR c.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto
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
GO

-- ===== sql\procedures\uspViviFirAziende_get_Verifica.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati per "Verifica Vi.Vi.FIR" di un'azienda interna (Vivifir > Aziende): la credenziale dell'hub associata e il codice
-- fiscale e la partita IVA dell'azienda, con cui l'app riconosce il soggetto tra quelli che la credenziale rappresenta
-- su Vi.Vi.FIR. Stessi controlli di uspViviFirAziende_upd: chi verifica salva anche l'esito
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_get_Verifica]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = e.IdDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idViviFir CHAR(16);
		SELECT @idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenzialiAziende a
			INNER JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
		WHERE
			a.IdAziendaInterna = @IdAziendaInterna
			AND c.Lock = 0;

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Associare e salvare prima una credenziale Vi.Vi.FIR';
			GOTO BRANCH_END;
		END

		SELECT
			IdViviFir = @idViviFir,
			s.CodiceFiscale,
			s.PartitaIva
		FROM dbo.tblSedi s
		WHERE s.Id = @IdAziendaInterna;

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
GO

-- ===== sql\procedures\uspViviFirAziende_upd.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Vivifir > Aziende: associa a un'azienda interna la credenziale Vi.Vi.FIR con cui lavora (una credenziale del dominio può
-- servire più aziende, un'azienda ne usa al massimo una). Senza credenziale (@IdCredenziale vuoto o sedici zeri)
-- l'associazione si toglie
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_upd]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdCredenziale = NULLIF(NULLIF(LTRIM(RTRIM(@IdCredenziale)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
		WHERE
			e.Id = @IdSessione
			AND i.Id = @IdAziendaInterna
			AND i.IdDominio = e.IdDominio;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La credenziale deve essere dello stesso dominio, attiva e già salvata nell'hub
		IF @IdCredenziale IS NOT NULL
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblViviFirCredenziali
				WHERE
					Id = @IdCredenziale
					AND IdDominio = @idDominio
					AND Lock = 0
					AND IdViviFir IS NOT NULL
			)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale selezionata non è valida';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @IdCredenziale IS NULL
				DELETE dbo.tblViviFirCredenzialiAziende
				WHERE IdAziendaInterna = @IdAziendaInterna;
			ELSE IF EXISTS (SELECT 1
			FROM dbo.tblViviFirCredenzialiAziende
			WHERE IdAziendaInterna = @IdAziendaInterna)
				-- Con un'altra credenziale la verifica precedente non vale più: soggetto e blocco vanno riletti
				UPDATE dbo.tblViviFirCredenzialiAziende
				SET
					IdCredenziale = @IdCredenziale,
					IdSoggetto = IIF(IdCredenziale = @IdCredenziale, IdSoggetto, NULL),
					Soggetto = IIF(IdCredenziale = @IdCredenziale, Soggetto, NULL),
					Blocco = IIF(IdCredenziale = @IdCredenziale, Blocco, NULL),
					DataVerifica = IIF(IdCredenziale = @IdCredenziale, DataVerifica, NULL)
				WHERE IdAziendaInterna = @IdAziendaInterna;
			ELSE
				INSERT INTO dbo.tblViviFirCredenzialiAziende (IdAziendaInterna, IdCredenziale)
				VALUES (@IdAziendaInterna, @IdCredenziale);
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
GO

-- ===== sql\procedures\uspViviFirAziende_upd_Verifica.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Esito di "Verifica Vi.Vi.FIR" di un'azienda interna (Vivifir > Aziende), letto dall'app sull'hub: il soggetto Vi.Vi.FIR
-- dell'azienda (Id e denominazione) e il codice del blocco del formulario unico (isArt230c5), che la vidimazione userà.
-- Senza un soggetto o senza un blocco si salva quello che c'è (NULL per il resto) con la data della verifica
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_upd_Verifica]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSoggetto INT = NULL,
	@Soggetto VARCHAR(255) = NULL,
	@Blocco VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Blocco = UPPER(NULLIF(LTRIM(RTRIM(@Blocco)), ''));

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSoggetto IS NULL AND @Blocco IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il blocco Vi.Vi.FIR richiede il soggetto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = e.IdDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblViviFirCredenzialiAziende
			SET
				IdSoggetto = @IdSoggetto,
				Soggetto = @Soggetto,
				Blocco = @Blocco,
				DataVerifica = SYSDATETIME()
			WHERE IdAziendaInterna = @IdAziendaInterna;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Associare e salvare prima una credenziale Vi.Vi.FIR';
				GOTO BRANCH_END;
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_del.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_del]
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: un @Id mai esistito o già cancellato è trattato come cancellazione
		-- già avvenuta con successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblViviFirCredenziali
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

			-- Controlla il permesso sul record (titolarità)
			IF NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblViviFirCredenziali c
					INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				WHERE
					c.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			DECLARE @lock INT = (SELECT Lock
			FROM dbo.tblViviFirCredenziali
			WHERE Id = @Id);

			-- Una credenziale usata da un'azienda non si cancella: va prima tolta in Vivifir > Aziende
			IF EXISTS (SELECT 1
			FROM dbo.tblViviFirCredenzialiAziende
			WHERE IdCredenziale = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale è associata ad aziende: toglierla prima in Vivifir > Aziende';
				GOTO BRANCH_END;
			END

			-- ── CASO 1: credenziale attiva (Lock = 0) → soft delete ────────────────
			-- La riga hub resta (per l'Undo).
			IF @lock = 0
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblViviFirCredenziali
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Credenziale non trovata o già eliminata';
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

			-- ── CASO 2: credenziale in bozza (Lock = 2) → hard delete ──────────────
			-- Nessuna riga hub esiste ancora a questo punto (creata solo da _upd).
			ELSE IF @lock = 2
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblViviFirCredenziali
					WHERE Id = @Id;
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;
					DELETE dbo.tblIdLog
					WHERE Id = @Id;
					DELETE dbo.tblId
					WHERE Id = @Id;
				COMMIT TRANSACTION;
			END

			-- ── CASO 3: Lock in stato non gestito ───────────────────────────────────
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_del_Undo.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_del_Undo]
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

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblViviFirCredenziali i
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_get.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_get]
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblViviFirCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblViviFirCredenziali
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Credenziale non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			c.Id,
			Nome = ISNULL(c.Nome, ''),
			h.ClientId,
			h.ClientSecret,
			c.Scadenza,
			c.Lock
		FROM
			dbo.tblViviFirCredenziali c
			LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_get_Esportazione.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali Vi.Vi.FIR (solo dati descrittivi, mai la chiave di autenticazione): righe per l'esportazione dell'elenco
-- in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspViviFirCredenziali_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspViviFirCredenziali_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[ClientId] = h.ClientId,
			[Scadenza] = c.Scadenza,
			[Aziende associate] = (
				SELECT STRING_AGG(CAST(s.NomeCompleto AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY s.NomeCompleto)
				FROM
					dbo.tblViviFirCredenzialiAziende a
					INNER JOIN dbo.tblSedi s ON a.IdAziendaInterna = s.Id
				WHERE a.IdCredenziale = c.Id)
		FROM
			dbo.tblViviFirCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR h.ClientId LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_get_IdViviFir.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Id della riga dell'hub [1_0_vivifir]..tblCredenziali di una credenziale (Verifica connessione)
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_get_IdViviFir]
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità), stesso pattern di uspViviFirCredenziali_get
		DECLARE @idViviFir CHAR(16);
		SELECT @idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
		WHERE
			c.Id = @Id
			AND c.Lock <= 2
			AND e.Id = @IdSessione;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Credenziale non trovata';
			GOTO BRANCH_END;
		END

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Salvare la credenziale prima di verificare la connessione';
			GOTO BRANCH_END;
		END

		SELECT rtn = @idViviFir;

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
GO

-- ===== sql\procedures\uspViviFirCredenziali_get_List.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_get_List]
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT
			c.Id,
			c.Nome,
			h.ClientId,
			c.Scadenza,
			AziendeCount = (SELECT COUNT(*)
			FROM dbo.tblViviFirCredenzialiAziende a
			WHERE a.IdCredenziale = c.Id),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblViviFirCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR h.ClientId LIKE '%' + @Search + '%'
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_ins.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_ins]
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il dominio';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblViviFirCredenziali (Id, IdDominio, Lock)
			VALUES (@returnId, @idDominio, 2);
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
GO

-- ===== sql\procedures\uspViviFirCredenziali_upd.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva la credenziale Vi.Vi.FIR del dominio, che si associa poi alle aziende interne in Vivifir > Aziende
-- (uspViviFirAziende_upd). Le credenziali applicative (ClientId e ClientSecret del flusso OAuth2) vanno nella riga dell'hub
-- [1_0_vivifir]..tblCredenziali, creata al primo salvataggio, come per le credenziali RENTRI e DIWASS; la scadenza (le
-- credenziali applicative valgono un anno) resta nell'app ed è solo informativa
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@ClientId VARCHAR(100) = NULL,
	@ClientSecret VARCHAR(200) = NULL,
	@Scadenza DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @ClientId = NULLIF(LTRIM(RTRIM(@ClientId)), '');
		SET @ClientSecret = NULLIF(LTRIM(RTRIM(@ClientSecret)), '');

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
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare un nome per la credenziale';
			GOTO BRANCH_END;
		END
		IF @ClientId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il ClientId';
			GOTO BRANCH_END;
		END
		IF @ClientSecret IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il ClientSecret';
			GOTO BRANCH_END;
		END
		IF @Scadenza IS NOT NULL AND (@Scadenza < '20200101' OR @Scadenza > '20501231')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare una scadenza compresa tra il 01/01/2020 e il 31/12/2050';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera IdDominio/IdViviFir correnti
		DECLARE @idDominio CHAR(16);
		DECLARE @idViviFir CHAR(16);
		SELECT
			@idDominio = c.IdDominio,
			@idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra credenziale con lo stesso nome nel dominio
		IF EXISTS (
			SELECT 1
			FROM dbo.tblViviFirCredenziali
			WHERE
				Id <> @Id
				AND IdDominio = @idDominio
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra credenziale con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Crea la riga hub al primo salvataggio, altrimenti la aggiorna
			IF @idViviFir IS NULL
			BEGIN
				SET @idViviFir = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_vivifir]..tblCredenziali (Id, ClientId, ClientSecret)
				VALUES (@idViviFir, @ClientId, @ClientSecret);
			END
			ELSE
			BEGIN
				UPDATE [1_0_vivifir]..tblCredenziali
				SET
					ClientId = @ClientId,
					ClientSecret = @ClientSecret
				WHERE Id = @idViviFir;
			END

			UPDATE dbo.tblViviFirCredenziali
			SET
				Lock = 0,
				IdViviFir = @idViviFir,
				Nome = @Nome,
				Scadenza = @Scadenza
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Credenziale non trovata o già eliminata';
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
GO

