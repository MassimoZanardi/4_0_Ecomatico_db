/*
Deploy produzione 2026-10-06 (2) - Rifiuti > Formulari: "RENTRI - Crea formulario cartaceo"

Rieseguibile.

0. tblRifiutiMovimenti: nuova colonna RentriFormularioCartaceo BIT NULL (ALTER TABLE ADD, guardato).
   Vale 1 quando il numero del formulario e' stato vidimato con "RENTRI - Crea formulario cartaceo".
   Poi rebuild della tabella (tools\rifiuti_movimenti_rebuild_formulario_cartaceo.sql, incluso qui) per
   portare la colonna subito dopo RentriFormularioInviiConservazione: un'unica transazione che ricrea
   PK, indice IX_RifiutiMovimenti_IdRegistro, 12 FK in uscita e 8 in entrata. Blocca la tabella per la
   durata della copia: eseguire senza utenti collegati. Se la colonna e' gia' in posizione non fa nulla.
   Gli oggetti schema-bound sulla tabella vengono droppati e ricreati subito dopo, sempre (anche senza
   rebuild), nell'ordine: viewRifiutiRegistrazioniEffettive, ufnRifiutiRegistrazioni_get_UltimoNumero,
   ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore. Vista e IsQuantitaSuperiore sono ricreate WITH
   SCHEMABINDING (aggiunto il 2026-10-06). Se lo script si interrompe dopo il rebuild questi oggetti
   possono mancare: rieseguire lo script per ricrearli.
1. uspRifiutiFormulari_upd_FormularioNumero (nuova): salva sul movimento il numero vidimato su RENTRI
   dall'hub (POST /vidimazione-formulari/{app}/{id}), che non scrive nulla su questo DB, e imposta
   RentriFormularioCartaceo = 1.
2. uspRifiutiFormulari_get: nuova colonna RentriFormularioCartaceo.
3. uspRifiutiFormulari_upd: con RentriFormularioCartaceo = 1 il numero del formulario non e' piu'
   modificabile (stesso trattamento del formulario digitale gia' creato su RENTRI).
4. uspRifiutiFormulari_get_List e uspRifiutiRegistrazioni_get_List: nuova colonna
   RentriFormularioCartaceo, per l'icona "Formulario cartaceo vidimato su RENTRI" negli elenchi.

Va deployato insieme all'app: l'app nuova legge RentriFormularioCartaceo e chiama la nuova SP. Nessuna
modifica all'hub.

Dopo il deploy eseguire tools\verifica_crlf_accenti.sql: deve dare 0 righe.
*/

PRINT 'tblRifiutiMovimenti.RentriFormularioCartaceo';
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioCartaceo')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioCartaceo BIT NULL;
END
GO

PRINT 'tblRifiutiMovimenti: rebuild per la posizione di RentriFormularioCartaceo';
GO
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

PRINT 'Oggetti schema-bound su tblRifiutiMovimenti';
GO
IF OBJECT_ID('dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore') IS NOT NULL
	DROP FUNCTION dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore;
GO

PRINT 'viewRifiutiRegistrazioniEffettive';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Valori OPERATIVI di ogni registrazione rifiuti ai fini di giacenze, relazioni carico/scarico, limiti ed
-- EoW. La registrazione originale non viene mai modificata da una rettifica (registro, stampa, conservazione
-- e trasmissione la riportano com'e' stata inviata al RENTRI; ogni rettifica trasmette i propri valori - stato
-- amministrativo). I valori operativi sono quelli dell'ultima rettifica confermata (Lock = 0, di correzione o di
-- annullamento, ordinata per data/numero) letti dalla sua riga di tblRentriRegistrazioniRettifiche: li scrivono
-- uspRifiutiRegistrazioni_upd_Rettifica/_upd_Annullamento alla conferma, "tutto o niente" - i nuovi valori
-- (Quantita = 0 per un annullamento) se la rettifica non rende incoerenti le relazioni carico/scarico, altrimenti
-- quelli operativi precedenti (ufnRifiutiRegistrazioni_get_RettificaOperativa). Le bozze (Lock = 2) non contano;
-- una rettifica cancellata prima dell'invio viene eliminata fisicamente insieme alla sua riga di tracking.
-- IsRettifica = 1: la registrazione e' essa stessa una rettifica/annullamento (non e' un movimento reale,
-- va sempre esclusa dai calcoli - i suoi valori restano quelli propri, esposti invariati).
-- IsAnnullata = 1: registrazione annullata anche operativamente (annullamento confermato con Quantita operativa
-- 0 - un annullamento non operativo riguarda un carico gia' consumato, quindi con quantita' > 0); le sue
-- relazioni restano (stampa/payload RENTRI) ma non contano piu' ne' come carico ne' come scarico. Un
-- annullamento non operativo lascia la registrazione pienamente valida per Ecomatico (IsAnnullata = 0).
CREATE OR ALTER VIEW [dbo].[viewRifiutiRegistrazioniEffettive]
WITH SCHEMABINDING
AS
SELECT
	r.Id,
	r.IdMovimento,
	IdEer = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdEer ELSE m.IdEer END,
	EerDescrizione = CASE WHEN c.IdRettifica IS NOT NULL THEN c.EerDescrizione ELSE m.EerDescrizione END,
	IdStatoFisico = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdStatoFisico ELSE m.IdStatoFisico END,
	IdUnitaMisura = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdUnitaMisura ELSE m.IdUnitaMisura END,
	Quantita = CASE WHEN c.IdRettifica IS NOT NULL THEN c.Quantita ELSE m.Quantita END,
	IsRettifica = CAST(IIF(t.IdRettifica IS NOT NULL, 1, 0) AS BIT),
	IsAnnullata = CAST(IIF(c.Annullata = 1 AND c.Quantita = 0, 1, 0) AS BIT),
	IdRettificaCorrente = c.IdRettifica
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	LEFT JOIN dbo.tblRentriRegistrazioniRettifiche t ON t.IdRettifica = r.Id
	OUTER APPLY (
		SELECT TOP 1
			x.IdRettifica,
			x.IdEer,
			x.EerDescrizione,
			x.IdStatoFisico,
			x.IdUnitaMisura,
			x.Quantita,
			x.Annullata
		FROM
			dbo.tblRentriRegistrazioniRettifiche x
			INNER JOIN dbo.tblRifiutiRegistrazioni rx ON x.IdRettifica = rx.Id
		WHERE
			x.Id = r.Id
			AND rx.Lock = 0
		ORDER BY
			rx.[Data] DESC,
			rx.Numero DESC
	) c;
GO

PRINT 'ufnRifiutiRegistrazioni_get_UltimoNumero';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_UltimoNumero]
(
	@IdRegistro CHAR(16),
	@Data DATE
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @PrimoGiornoAnno DATE = DATEFROMPARTS(YEAR(@Data), 1, 1);

	RETURN
	(
		SELECT ISNULL(MAX(r.Numero), 0)
		FROM dbo.tblRifiutiMovimenti m
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
		WHERE
			m.IdRegistro = @IdRegistro
			AND r.Data >= @PrimoGiornoAnno
			AND r.Data <= @Data
			AND r.Lock < 2
	);
END;
GO

PRINT 'ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore]
(
	@Id CHAR(16),
	@Quantita DECIMAL(18, 2),
	@RegistrazioneData DATE,
	@RegistrazioneNumero INT,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@NoParametri BIT = 0
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	-- FIX: Quantita e IdUnitaMisura spostate da tblRifiutiRegistrazioni (r/p2) a tblRifiutiMovimenti (m/mp2)
	-- Valori effettivi da viewRifiutiRegistrazioniEffettive (ultima correzione confermata, 0 se annullata):
	-- la vista non e' schema-bound, quindi la funzione non puo' piu' essere WITH SCHEMABINDING
	DECLARE @TotaleDisponibile DECIMAL(38, 2);
	SELECT
		@TotaleDisponibile =
			ISNULL(SUM(
				CONVERT(DECIMAL(38, 2), v.Quantita)
				+ lp.QuantitaAssegnataCorrente
				- ISNULL(qa.QuantitaAssociataTotale, 0)
			), 0)
	FROM
	(
		SELECT
			l.Id,
			SUM(CONVERT(DECIMAL(38, 2), l.Quantita)) AS QuantitaAssegnataCorrente
		FROM dbo.tblRifiutiRegistrazioniRelazioni l
		WHERE l.IdParent = @Id
		GROUP BY l.Id
	) lp
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON r.Id = lp.Id
		INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON v.Id = r.Id
		INNER JOIN dbo.tblRifiutiRegistrazioni rp ON rp.Id = @Id
		INNER JOIN dbo.tblRifiutiMovimenti mp ON mp.Id = rp.IdMovimento
		OUTER APPLY (
			SELECT
				SUM(CONVERT(DECIMAL(38, 2), l2.Quantita)) AS QuantitaAssociataTotale
			FROM dbo.tblRifiutiRegistrazioniRelazioni l2
			INNER JOIN dbo.tblRifiutiRegistrazioni p2 ON p2.Id = l2.IdParent
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp2 ON vp2.Id = p2.Id
			WHERE
				l2.Id = lp.Id
				AND p2.Lock < 2
				AND vp2.Quantita > 0
		) qa
	WHERE
		r.Lock = 0
		AND
			(
			@NoParametri = 1
			OR
				(
					(
					r.[Data] < @RegistrazioneData
					OR
						(
						r.[Data] = @RegistrazioneData
						AND r.Numero < @RegistrazioneNumero
						)
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR v.IdEer = @IdEer
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR v.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR v.IdUnitaMisura = @IdUnitaMisura
					)
				)
			);
	RETURN CASE
		WHEN @Quantita > ISNULL(@TotaleDisponibile, 0) THEN 1
		ELSE 0
	END;
END;
GO

PRINT 'uspRifiutiFormulari_upd_FormularioNumero';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "RENTRI - Crea formulario cartaceo" (Rifiuti/Formulari/Edit): salva sul movimento il numero appena
-- vidimato su RENTRI (hub POST /vidimazione-formulari/{app}/{id}). A differenza del formulario digitale
-- (uspFormulariDigitali_ins dell'hub, che scrive numero e stato), qui l'hub non conosce il formulario e
-- non scrive nulla su questo DB: RentriFormularioStato resta NULL (su RENTRI non esiste un FIR digitale) e
-- il movimento viene marcato con RentriFormularioCartaceo = 1, che blocca numero e nuove creazioni.
-- Chiamata DOPO la vidimazione, che non e' annullabile: per non perdere il numero i controlli sono
-- solo permesso, titolarita' e assenza del formulario digitale; quelli sul formulario li fa il
-- chiamante prima di vidimare (RentriFormularioService.CreaCartaceoAsync).
-- exec dbo.uspRifiutiFormulari_upd_FormularioNumero @Id='...', @FormularioNumero='ABCDE 000001 XY', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_upd_FormularioNumero
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

		-- Titolarità (stesso pattern di uspRifiutiFormulari_upd) e stato RENTRI del formulario
		DECLARE @idMovimento CHAR(16);
		DECLARE @formularioRentriStato VARCHAR(40);
		SELECT
			@idMovimento = m.Id,
			@formularioRentriStato = m.RentriFormularioStato
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
		IF @formularioRentriStato IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario digitale è già stato creato su RENTRI: il numero non può più essere modificato';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRifiutiMovimenti
		SET
			FormularioNumero = @FormularioNumero,
			RentriFormularioCartaceo = 1
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

PRINT 'uspRifiutiFormulari_get';
GO
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
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
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

PRINT 'uspRifiutiFormulari_upd';
GO
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
	@IdEtichette VARCHAR(50) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
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
				-- Lo stesso vale per il numero vidimato con "RENTRI - Crea formulario cartaceo".
				FormularioNumero = CASE WHEN @formularioRentriStato IS NOT NULL OR @rentriFormularioCartaceo = 1 THEN m.FormularioNumero ELSE @FormularioNumero END,
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

PRINT 'uspRifiutiFormulari_get_List';
GO
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

PRINT 'uspRifiutiRegistrazioni_get_List';
GO
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
            @Etichetta   VARCHAR(50)';

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
                RentriFormularioCartaceo = ISNULL(m.RentriFormularioCartaceo, 0)
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
            tbl.RentriFormularioStato, tbl.RentriFormularioCartaceo,
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
			@Etichetta = @Etichetta;

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

