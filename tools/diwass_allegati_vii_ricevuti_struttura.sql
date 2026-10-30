-- DIWASS: Allegati VII ricevuti, sincronizzazione e conferme (2026-10-30). Prima va eseguito sul DB dell'hub
-- 1_0_diwass\tools\allegati_vii_sincronizzazione_struttura.sql (tblAllegatiVii dell'hub, letta da
-- uspDiwassAllegatiVii_upd_Sincronizza).
-- 1) tblDiwassAllegatiVii: Ricevuto (1 = documento organizzato da altri o fuori da Ecomatico, letto da DIWASS, in sola
--    lettura), Ruoli (ruoli dell'azienda nel documento: O, P, D, I, T), DataLettura (ultima importazione da DIWASS);
-- 2) tblDiwassAllegatiViiSoggetti: IdSede facoltativa (i soggetti dei documenti ricevuti spesso non sono in anagrafica)
--    con operatore, nome, indirizzo e paese letti da DIWASS;
-- 3) tblDiwassAllegatiViiConferme: presa in carico (T), ricezione del destinatario (D), ricezione dell'impianto (I),
--    recupero completato (C).
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ===== 1. tblDiwassAllegatiVii
IF COL_LENGTH('dbo.tblDiwassAllegatiVii', 'Ricevuto') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiVii ADD Ricevuto BIT NULL;
GO
IF COL_LENGTH('dbo.tblDiwassAllegatiVii', 'Ruoli') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiVii ADD Ruoli VARCHAR(10) COLLATE Latin1_General_CI_AS NULL;
GO
IF COL_LENGTH('dbo.tblDiwassAllegatiVii', 'DataLettura') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiVii ADD DataLettura DATETIME2(0) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DiwassAllegatiVii_Numero' AND object_id = OBJECT_ID('dbo.tblDiwassAllegatiVii'))
	CREATE NONCLUSTERED INDEX IX_DiwassAllegatiVii_Numero ON dbo.tblDiwassAllegatiVii (Numero ASC, IdAziendaInterna ASC);
GO

-- ===== 2. tblDiwassAllegatiViiSoggetti
IF EXISTS (
	SELECT 1
	FROM sys.columns
	WHERE
		object_id = OBJECT_ID('dbo.tblDiwassAllegatiViiSoggetti')
		AND name = 'IdSede'
		AND is_nullable = 0
)
	ALTER TABLE dbo.tblDiwassAllegatiViiSoggetti ALTER COLUMN IdSede CHAR(16) COLLATE Latin1_General_CI_AS NULL;
GO
IF COL_LENGTH('dbo.tblDiwassAllegatiViiSoggetti', 'OperatorInternalId') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiViiSoggetti ADD OperatorInternalId BIGINT NULL;
GO
IF COL_LENGTH('dbo.tblDiwassAllegatiViiSoggetti', 'Nome') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiViiSoggetti ADD Nome NVARCHAR(250) COLLATE Latin1_General_CI_AS NULL;
GO
IF COL_LENGTH('dbo.tblDiwassAllegatiViiSoggetti', 'Indirizzo') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiViiSoggetti ADD Indirizzo NVARCHAR(500) COLLATE Latin1_General_CI_AS NULL;
GO
IF COL_LENGTH('dbo.tblDiwassAllegatiViiSoggetti', 'Paese') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiViiSoggetti ADD Paese CHAR(2) COLLATE Latin1_General_CI_AS NULL;
GO

-- ===== 3. tblDiwassAllegatiViiConferme
IF OBJECT_ID('dbo.tblDiwassAllegatiViiConferme', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblDiwassAllegatiViiConferme (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		Tipo CHAR(1) COLLATE Latin1_General_CI_AS NOT NULL,
		Pos TINYINT NOT NULL,
		Numero VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		OperatorInternalId BIGINT NULL,
		Data DATE NULL,
		MezzoTrasporto CHAR(1) COLLATE Latin1_General_CI_AS NULL,
		Targhe VARCHAR(200) COLLATE Latin1_General_CI_AS NULL,
		UnitaQuantita CHAR(1) COLLATE Latin1_General_CI_AS NULL,
		QuantitaAccettata DECIMAL(18, 5) NULL,
		QuantitaRespinta DECIMAL(18, 5) NULL,
		MotivoRespingimento NVARCHAR(500) COLLATE Latin1_General_CI_AS NULL,
		QuantitaRiutilizzo DECIMAL(18, 5) NULL,
		QuantitaRecupero DECIMAL(18, 5) NULL,
		Descrizione NVARCHAR(500) COLLATE Latin1_General_CI_AS NULL,
		ContattoNome NVARCHAR(100) COLLATE Latin1_General_CI_AS NULL,
		ContattoTelefono VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		ContattoEmail VARCHAR(100) COLLATE Latin1_General_CI_AS NULL,
		FirmaNome NVARCHAR(100) COLLATE Latin1_General_CI_AS NULL,
		FirmaRuolo NVARCHAR(100) COLLATE Latin1_General_CI_AS NULL,
		FirmaData DATETIME2(0) NULL,
		FirmaEmail VARCHAR(100) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblDiwassAllegatiViiConferme PRIMARY KEY CLUSTERED (Id ASC, Tipo ASC, Pos ASC)
	);

	ALTER TABLE dbo.tblDiwassAllegatiViiConferme WITH CHECK ADD CONSTRAINT FK_tblDiwassAllegatiViiConferme_tblDiwassAllegatiVii
		FOREIGN KEY (Id) REFERENCES dbo.tblDiwassAllegatiVii (Id);
END
GO
