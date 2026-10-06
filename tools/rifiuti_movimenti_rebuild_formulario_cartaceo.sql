-- tblRifiutiMovimenti: rebuild per portare RentriFormularioCartaceo subito dopo
-- RentriFormularioInviiConservazione, accanto agli altri campi RentriFormulario* (ALTER TABLE ADD la
-- mette in coda). Rieseguibile: se la colonna e' gia' in posizione non fa nulla.
-- Tutto in un'unica transazione (XACT_ABORT ON): al primo errore torna tutto com'era, funzione compresa.
-- Dipendenze ricreate: 8 FK in entrata, PK, indice IX_RifiutiMovimenti_IdRegistro, 12 FK in uscita.
-- Nessun default, check, trigger, permesso o statistica utente sulla tabella.
-- Oggetti schema-bound droppati qui e NON ricreati da questo file: viewRifiutiRegistrazioniEffettive,
-- ufnRifiutiRegistrazioni_get_UltimoNumero e ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore (che dipende
-- dalla vista). Li ricrea, in quest'ordine, lo script di deploy che include questo file: da solo questo
-- file li lascia mancanti.
-- Prerequisito: la colonna RentriFormularioCartaceo esiste gia' (ALTER TABLE ADD del passo precedente).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
SET NOCOUNT, XACT_ABORT ON;

IF (SELECT column_id FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioCartaceo')
	= (SELECT column_id FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioInviiConservazione') + 1
BEGIN
	PRINT '  RentriFormularioCartaceo già in posizione: nessun rebuild';
END
ELSE
BEGIN
	DECLARE @righePrima INT;
	DECLARE @righeDopo INT;

	BEGIN TRANSACTION;

	SELECT @righePrima = COUNT(*) FROM dbo.tblRifiutiMovimenti WITH (TABLOCKX, HOLDLOCK);

	-- Oggetti schema-bound: impediscono il DROP della tabella. Prima la funzione che dipende dalla vista
	IF OBJECT_ID('dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore') IS NOT NULL
		DROP FUNCTION dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore;
	IF OBJECT_ID('dbo.viewRifiutiRegistrazioniEffettive') IS NOT NULL
		DROP VIEW dbo.viewRifiutiRegistrazioniEffettive;
	IF OBJECT_ID('dbo.ufnRifiutiRegistrazioni_get_UltimoNumero') IS NOT NULL
		DROP FUNCTION dbo.ufnRifiutiRegistrazioni_get_UltimoNumero;

	-- FK in entrata
	ALTER TABLE dbo.tblRifiutiFormulari DROP CONSTRAINT FK_tblRifiutiFormulari_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiMovimentiClassiPericolo DROP CONSTRAINT FK_tblRifiutiMovimentiClassiPericolo_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiMovimentiDestinatari DROP CONSTRAINT FK_tblRifiutiMovimentiDestinatari_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiMovimentiIntermediari DROP CONSTRAINT FK_tblRifiutiMovimentiIntermediari_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiMovimentiLog DROP CONSTRAINT FK_tblRifiutiMovimentiLog_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiMovimentiProduttori DROP CONSTRAINT FK_tblRifiutiMovimentiProduttori_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiMovimentiTrasportatori DROP CONSTRAINT FK_tblRifiutiMovimentiTrasportatori_tblRifiutiMovimenti;
	ALTER TABLE dbo.tblRifiutiRegistrazioni DROP CONSTRAINT FK_tblRifiutiRegistrazioni_tblRifiutiMovimenti;

	CREATE TABLE dbo.tblRifiutiMovimenti_Rebuild (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdRegistro CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdOperazione CHAR(1) COLLATE Latin1_General_CI_AS NULL,
		IdEer CHAR(6) COLLATE Latin1_General_CI_AS NULL,
		IdStatoFisico CHAR(1) COLLATE Latin1_General_CI_AS NULL,
		IdAttivita CHAR(2) COLLATE Latin1_General_CI_AS NULL,
		IdSedeProduttoreDetentore CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdSedeDestinatario CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdSedeTrasportatore1 CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdSedeIntermediario1 CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdUnitaMisura CHAR(2) COLLATE Latin1_General_CI_AS NULL,
		IdProvenienza CHAR(1) COLLATE Latin1_General_CI_AS NULL,
		Quantita DECIMAL(18, 2) NULL,
		EerDescrizione VARCHAR(200) COLLATE Latin1_General_CI_AS NULL,
		FormularioNumero VARCHAR(20) COLLATE Latin1_General_CI_AS NULL,
		DataInizioTrasporto SMALLDATETIME NULL,
		Note VARCHAR(500) COLLATE Latin1_General_CI_AS NULL,
		RentriFormularioStato VARCHAR(40) COLLATE Latin1_General_CI_AS NULL,
		RentriFormularioDataCopia SMALLDATETIME NULL,
		RentriFormularioDataTrasmissione SMALLDATETIME NULL,
		RentriFormularioDataPresaVisione SMALLDATETIME NULL,
		RentriFormularioDataConservazione SMALLDATETIME NULL,
		RentriFormularioInviiConservazione INT NULL,
		RentriFormularioCartaceo BIT NULL,
		IdModello CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblRifiutiMovimenti_Rebuild PRIMARY KEY CLUSTERED (Id ASC)
	) ON [PRIMARY];

	INSERT dbo.tblRifiutiMovimenti_Rebuild
		(Id, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdSedeProduttoreDetentore, IdSedeDestinatario,
		 IdSedeTrasportatore1, IdSedeIntermediario1, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione, FormularioNumero,
		 DataInizioTrasporto, Note, RentriFormularioStato, RentriFormularioDataCopia, RentriFormularioDataTrasmissione,
		 RentriFormularioDataPresaVisione, RentriFormularioDataConservazione, RentriFormularioInviiConservazione,
		 RentriFormularioCartaceo, IdModello)
	SELECT
		Id, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdSedeProduttoreDetentore, IdSedeDestinatario,
		IdSedeTrasportatore1, IdSedeIntermediario1, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione, FormularioNumero,
		DataInizioTrasporto, Note, RentriFormularioStato, RentriFormularioDataCopia, RentriFormularioDataTrasmissione,
		RentriFormularioDataPresaVisione, RentriFormularioDataConservazione, RentriFormularioInviiConservazione,
		RentriFormularioCartaceo, IdModello
	FROM dbo.tblRifiutiMovimenti;

	SET @righeDopo = @@ROWCOUNT;
	IF @righeDopo <> @righePrima
		THROW 50001, 'Rebuild tblRifiutiMovimenti: il numero di righe copiate non coincide', 1;

	-- Con la tabella cadono PK, indice e le 12 FK in uscita
	DROP TABLE dbo.tblRifiutiMovimenti;

	EXEC sp_rename 'dbo.tblRifiutiMovimenti_Rebuild', 'tblRifiutiMovimenti';
	EXEC sp_rename 'dbo.PK_tblRifiutiMovimenti_Rebuild', 'PK_tblRifiutiMovimenti', 'OBJECT';

	CREATE NONCLUSTERED INDEX IX_RifiutiMovimenti_IdRegistro ON dbo.tblRifiutiMovimenti (IdRegistro ASC)
	INCLUDE (IdOperazione, IdEer, IdStatoFisico, IdUnitaMisura, Quantita, IdSedeDestinatario, IdSedeIntermediario1, FormularioNumero,
		IdAttivita, IdSedeProduttoreDetentore, IdSedeTrasportatore1, IdProvenienza, RentriFormularioStato, RentriFormularioDataCopia,
		RentriFormularioDataPresaVisione, RentriFormularioDataTrasmissione, RentriFormularioDataConservazione,
		RentriFormularioInviiConservazione) ON [PRIMARY];

	-- FK in uscita
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiAttivitaRecuperoSmaltimento FOREIGN KEY (IdAttivita) REFERENCES dbo.tblRifiutiAttivitaRecuperoSmaltimento (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiEer FOREIGN KEY (IdEer) REFERENCES dbo.tblRifiutiEer (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiModelli FOREIGN KEY (IdModello) REFERENCES dbo.tblRifiutiModelli (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiOperazioni FOREIGN KEY (IdOperazione) REFERENCES dbo.tblRifiutiOperazioni (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiProvenienze FOREIGN KEY (IdProvenienza) REFERENCES dbo.tblRifiutiProvenienze (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiRegistri FOREIGN KEY (IdRegistro) REFERENCES dbo.tblRifiutiRegistri (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblRifiutiStatiFisici FOREIGN KEY (IdStatoFisico) REFERENCES dbo.tblRifiutiStatiFisici (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblSedi_IdSedeDestinatario FOREIGN KEY (IdSedeDestinatario) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblSedi_IdSedeIntermediario1 FOREIGN KEY (IdSedeIntermediario1) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblSedi_IdSedeProduttoreDetentore FOREIGN KEY (IdSedeProduttoreDetentore) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblSedi_IdSedeTrasportatore1 FOREIGN KEY (IdSedeTrasportatore1) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblRifiutiMovimenti WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimenti_tblUnitaMisura FOREIGN KEY (IdUnitaMisura) REFERENCES dbo.tblUnitaMisura (Id);

	-- FK in entrata
	ALTER TABLE dbo.tblRifiutiFormulari WITH CHECK ADD CONSTRAINT FK_tblRifiutiFormulari_tblRifiutiMovimenti FOREIGN KEY (IdMovimento) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiClassiPericolo WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiClassiPericolo_tblRifiutiMovimenti FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiDestinatari WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiDestinatari_tblRifiutiMovimenti FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiIntermediari WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiIntermediari_tblRifiutiMovimenti FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiLog WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiLog_tblRifiutiMovimenti FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiProduttori WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiProduttori_tblRifiutiMovimenti FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiTrasportatori WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiTrasportatori_tblRifiutiMovimenti FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiRegistrazioni WITH CHECK ADD CONSTRAINT FK_tblRifiutiRegistrazioni_tblRifiutiMovimenti FOREIGN KEY (IdMovimento) REFERENCES dbo.tblRifiutiMovimenti (Id);

	COMMIT TRANSACTION;

	PRINT '  rebuild completato: ' + CAST(@righeDopo AS VARCHAR(10)) + ' righe';
END
GO
