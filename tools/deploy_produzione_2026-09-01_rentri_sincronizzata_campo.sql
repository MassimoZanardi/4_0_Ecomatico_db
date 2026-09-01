/*
	Deploy produzione - 2026-09-01 - Campo RentriSincronizzata + rinomina SP sincronizzazione RENTRI

	*** ATTENZIONE: contiene un rebuild completo di dbo.tblRifiutiRegistrazioni (DROP TABLE +
	ricrea con nuovo ordine colonne). Su una tabella con molte righe comporta una breve
	indisponibilita' della tabella (lock esclusivo durante la copia dati) - eseguire in una
	finestra di manutenzione o comunque a basso traffico, idealmente dopo un backup. Non e'
	un'operazione istantanea come una semplice ALTER TABLE ADD COLUMN. ***

	Contenuto di questo script (solo 4_0_ecomatico, verificato su dev con 18 righe reali,
	transazionale con rollback automatico su errore):

	1) Rebuild dbo.tblRifiutiRegistrazioni per aggiungere RentriSincronizzata BIT NULL
	   subito dopo RentriData (non in coda, come farebbe una ALTER TABLE ADD) - marca
	   esplicitamente (=1) le registrazioni la cui conferma RENTRI e' arrivata tramite la
	   sincronizzazione (checkbox 'sincronizza' in Rifiuti/Registrazioni/Index) invece che
	   da un invio normale, per tracciabilita'. Corretta anche la precisione di RentriData
	   da DATETIME2(6) (default implicito mai specificato esplicitamente) a DATETIME2(0),
	   coerente col tipo parametro gia' usato dalle SP. Il rebuild richiede: drop temporaneo
	   delle 2 funzioni WITH SCHEMABINDING che referenziano la tabella
	   (ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore, ufnRifiutiRegistrazioni_get_UltimoNumero)
	   e delle 4 FK in entrata (tblEoWMovimenti, tblRifiutiRegistrazioniRelazioni x2,
	   tblRifiutiRegistrazioniEtichette) - tutto ricreato identico a fine script, dentro
	   un'unica transazione con verifica del conteggio righe prima del DROP TABLE.

	2) Crea dbo.uspRentriRegistrazioni_upd_Sincronizza (nuova, sostituisce
	   uspRentriRegistrazioni_upd deployata dal precedente bundle
	   deploy_produzione_2026-09-01_sincronizzazione_rentri.sql)
	   - Nome piu' esplicito (lega SP, checkbox 'sincronizza' e campo RentriSincronizzata).
	     Sincronizza in blocco un elenco di registrazioni (JSON @Registrazioni, stesso
	     pattern OPENJSON gia' usato da 1_0_rentri..uspRegistrazioni_upd_ByRegistrazioni)
	     invece di una singola registrazione per chiamata - una sola chiamata invece di N
	     round-trip quando ci sono piu' registrazioni da sincronizzare, best-effort per riga
	     (una corrispondenza non piu' valida viene solo saltata, non blocca le altre).
	     Imposta RentriIdentificativo/RentriData/RentriSincronizzata=1, RentriData catturato
	     una volta sola per l'intero blocco.
	     La vecchia uspRentriRegistrazioni_upd viene droppata in fondo a questo script.

	Verificato su DB dev: rebuild transazionale completato senza errori (18 righe invariate,
	2 indici/8 FK uscita/4 FK entrata/2 funzioni schema-bound tutti ricreati correttamente,
	colonna in posizione corretta, precisione DATETIME2(0) confermata), smoke test su
	funzioni schema-bound + view con dati reali, vecchio nome SP droppato senza errori.
	SP a blocco JSON testata con 2 corrispondenze reali + 1 senza corrispondenza nello
	stesso batch: le 2 valide sincronizzate correttamente (stesso RentriData condiviso),
	quella senza corrispondenza saltata senza errori (conteggio di ritorno = 2).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-01_rentri_sincronizzata_campo.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) Rebuild dbo.tblRifiutiRegistrazioni (aggiunge RentriSincronizzata dopo RentriData)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

-- 1) Drop delle 2 funzioni WITH SCHEMABINDING (bloccano il DROP TABLE)
DROP FUNCTION dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore;
DROP FUNCTION dbo.ufnRifiutiRegistrazioni_get_UltimoNumero;

-- 2) Drop delle 4 FK in entrata
ALTER TABLE dbo.tblEoWMovimenti DROP CONSTRAINT FK_tblEoWMovimenti_tblRifiutiRegistrazioni;
ALTER TABLE dbo.tblRifiutiRegistrazioniRelazioni DROP CONSTRAINT FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_Id;
ALTER TABLE dbo.tblRifiutiRegistrazioniRelazioni DROP CONSTRAINT FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_IdParent;
ALTER TABLE dbo.tblRifiutiRegistrazioniEtichette DROP CONSTRAINT FK_tblRifiutiRegistrazioniEtichette_tblRifiutiRegistrazioni;

-- 3) CREATE TABLE nuova con RentriSincronizzata subito dopo RentriData
CREATE TABLE dbo.tblRifiutiRegistrazioni_new(
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMovimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEsito] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdRaee] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdCausaleRespingimento] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdTrasportoTransfrontalieroTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAttivitaProvenienza] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisuraQuantitaRespinta] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[CausaleRespingimentoAltro] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[QuantitaRespinta] [decimal](18, 2) NULL,
	[DataFineTrasporto] [smalldatetime] NULL,
	[Operazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Data] [date] NULL,
	[Numero] [int] NULL,
	[QuantitaVerificata] [decimal](18, 2) NULL,
	[VeicoloFuoriUso] [bit] NULL,
	[VeicoloFuoriUsoNumero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[VeicoloFuoriUsoData] [date] NULL,
	[MaterialeDescrizione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[RentriIdentificativo] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[RentriData] [datetime2](0) NULL,
	[RentriSincronizzata] [bit] NULL,
	[Etichette] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiRegistrazioni_new] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY];

-- 4) Copia dati (colonne esplicite)
INSERT INTO dbo.tblRifiutiRegistrazioni_new
(
	Id, IdMovimento, IdEsito, IdRaee, IdCausaleRespingimento, IdTrasportoTransfrontalieroTipo,
	IdMateriale, IdAttivitaProvenienza, IdUnitaMisuraQuantitaRespinta, CausaleRespingimentoAltro,
	QuantitaRespinta, DataFineTrasporto, Operazione, Data, Numero, QuantitaVerificata,
	VeicoloFuoriUso, VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione,
	RentriIdentificativo, RentriData, RentriSincronizzata, Etichette, Note, Lock
)
SELECT
	Id, IdMovimento, IdEsito, IdRaee, IdCausaleRespingimento, IdTrasportoTransfrontalieroTipo,
	IdMateriale, IdAttivitaProvenienza, IdUnitaMisuraQuantitaRespinta, CausaleRespingimentoAltro,
	QuantitaRespinta, DataFineTrasporto, Operazione, Data, Numero, QuantitaVerificata,
	VeicoloFuoriUso, VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione,
	RentriIdentificativo, RentriData, RentriSincronizzata, Etichette, Note, Lock
FROM dbo.tblRifiutiRegistrazioni;

-- 5) Verifica conteggio righe invariato
IF (SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioni) <> (SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioni_new)
	THROW 50001, 'Conteggio righe non corrispondente dopo la copia - abort', 1;

-- 6) Drop vecchia tabella, rename nuova
DROP TABLE dbo.tblRifiutiRegistrazioni;
EXEC sp_rename 'dbo.tblRifiutiRegistrazioni_new', 'tblRifiutiRegistrazioni';
EXEC sp_rename 'dbo.PK_tblRifiutiRegistrazioni_new', 'PK_tblRifiutiRegistrazioni';

-- 7) Ricrea i 2 indici nonclustered
CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioni_Data_Lock] ON [dbo].[tblRifiutiRegistrazioni]
(
	[Data] DESC
)
INCLUDE([IdMovimento],[Numero],[QuantitaVerificata],[Operazione],[Etichette])
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];

CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock] ON [dbo].[tblRifiutiRegistrazioni]
(
	[IdMovimento] ASC,
	[Data] ASC,
	[Numero] ASC
)
INCLUDE([QuantitaVerificata],[DataFineTrasporto],[IdTrasportoTransfrontalieroTipo],[Note],[Operazione],[Etichette])
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];

-- 8) Ricrea le 8 FK in uscita
ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMateriali];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMovimenti] FOREIGN KEY([IdMovimento])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMovimenti];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRaee] FOREIGN KEY([IdRaee])
REFERENCES [dbo].[tblRifiutiRaee] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRaee];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsiti] FOREIGN KEY([IdEsito])
REFERENCES [dbo].[tblRifiutiRegistrazioniEsiti] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsiti];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsitiCausaliRespingimento] FOREIGN KEY([IdCausaleRespingimento])
REFERENCES [dbo].[tblRifiutiRegistrazioniEsitiCausaliRespingimento] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsitiCausaliRespingimento];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiDocumentiTrasportiTipi] FOREIGN KEY([IdTrasportoTransfrontalieroTipo])
REFERENCES [dbo].[tblRifiutiDocumentiTrasportiTipi] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiDocumentiTrasportiTipi];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblUnitaMisura] FOREIGN KEY([IdUnitaMisuraQuantitaRespinta])
REFERENCES [dbo].[tblUnitaMisura] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblUnitaMisura];

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiAttivitaProvenienze] FOREIGN KEY([IdAttivitaProvenienza])
REFERENCES [dbo].[tblRifiutiAttivitaProvenienze] ([Id]);
ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiAttivitaProvenienze];

-- 9) Ricrea le 4 FK in entrata
ALTER TABLE dbo.tblEoWMovimenti WITH CHECK ADD CONSTRAINT FK_tblEoWMovimenti_tblRifiutiRegistrazioni FOREIGN KEY(IdRegistrazione)
REFERENCES dbo.tblRifiutiRegistrazioni (Id);
ALTER TABLE dbo.tblEoWMovimenti CHECK CONSTRAINT FK_tblEoWMovimenti_tblRifiutiRegistrazioni;

ALTER TABLE dbo.tblRifiutiRegistrazioniRelazioni WITH CHECK ADD CONSTRAINT FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_Id FOREIGN KEY(Id)
REFERENCES dbo.tblRifiutiRegistrazioni (Id);
ALTER TABLE dbo.tblRifiutiRegistrazioniRelazioni CHECK CONSTRAINT FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_Id;

ALTER TABLE dbo.tblRifiutiRegistrazioniRelazioni WITH CHECK ADD CONSTRAINT FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_IdParent FOREIGN KEY(IdParent)
REFERENCES dbo.tblRifiutiRegistrazioni (Id);
ALTER TABLE dbo.tblRifiutiRegistrazioniRelazioni CHECK CONSTRAINT FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_IdParent;

ALTER TABLE dbo.tblRifiutiRegistrazioniEtichette WITH CHECK ADD CONSTRAINT FK_tblRifiutiRegistrazioniEtichette_tblRifiutiRegistrazioni FOREIGN KEY(Id)
REFERENCES dbo.tblRifiutiRegistrazioni (Id);
ALTER TABLE dbo.tblRifiutiRegistrazioniEtichette CHECK CONSTRAINT FK_tblRifiutiRegistrazioniEtichette_tblRifiutiRegistrazioni;

COMMIT TRANSACTION;
PRINT 'Rebuild tabella completato (indici/FK ricreati)';
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
	PRINT 'ERRORE - rollback eseguito: ' + ERROR_MESSAGE();
	THROW;
END CATCH;
GO

-- 10) Ricrea le 2 funzioni schema-bound (fuori transazione: CREATE FUNCTION non puo' stare nello stesso batch/tran di altre DDL con GO)
CREATE FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore]
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
	DECLARE @TotaleDisponibile DECIMAL(38, 2);
	SELECT
		@TotaleDisponibile =
			ISNULL(SUM(
				CONVERT(DECIMAL(38, 2), m.Quantita)
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
		INNER JOIN dbo.tblRifiutiMovimenti m ON m.Id = r.IdMovimento
		INNER JOIN dbo.tblRifiutiRegistrazioni rp ON rp.Id = @Id
		INNER JOIN dbo.tblRifiutiMovimenti mp ON mp.Id = rp.IdMovimento
		OUTER APPLY (
			SELECT
				SUM(CONVERT(DECIMAL(38, 2), l2.Quantita)) AS QuantitaAssociataTotale
			FROM dbo.tblRifiutiRegistrazioniRelazioni l2
			INNER JOIN dbo.tblRifiutiRegistrazioni p2 ON p2.Id = l2.IdParent
			INNER JOIN dbo.tblRifiutiMovimenti mp2 ON mp2.Id = p2.IdMovimento
			WHERE
				l2.Id = lp.Id
				AND p2.Lock < 2
				AND mp2.Quantita > 0
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
					OR m.IdEer = @IdEer
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR m.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR m.IdUnitaMisura = @IdUnitaMisura
					)
				)
			);
	RETURN CASE
		WHEN @Quantita > ISNULL(@TotaleDisponibile, 0) THEN 1
		ELSE 0
	END;
END;
GO

CREATE FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_UltimoNumero]
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

--------------------------------------------------------------------------------
-- 2) dbo.uspRentriRegistrazioni_upd_Sincronizza (rinominata da uspRentriRegistrazioni_upd)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Sincronizza in blocco un elenco di registrazioni con un dato già presente su RENTRI ma non
-- ancora confermato lato app (invio asincrono: RENTRI ha ricevuto/elaborato le registrazioni
-- ma la conferma non è mai arrivata/stata scritta sull'app, es. per un problema di rete o un
-- crash durante l'attesa). Usata da Rifiuti/Registrazioni/Index (checkbox "sincronizza" in
-- modale 2) dopo un confronto con l'elenco reale restituito da RENTRI - non chiamata
-- direttamente dall'utente, nessuna registrazione "nuova" viene mai creata qui, solo
-- aggiornati RentriIdentificativo/RentriData su righe già esistenti e mai confermate prima.
-- RentriSincronizzata = 1 marca esplicitamente che la conferma è arrivata da questa
-- sincronizzazione e non da un invio normale, per tracciabilità.
-- @Registrazioni: JSON array [{numero, anno, identificativo}, ...]. @RentriData catturato
-- una volta sola per l'intero blocco (stesso pattern di 1_0_rentri..uspRegistrazioni_upd_ByRegistrazioni,
-- non per singola riga). Comportamento best-effort: una riga del JSON senza corrispondenza
-- (già sincronizzata, Lock diverso da 0, ecc.) viene semplicemente saltata, non blocca le
-- altre - il chiamante ha già verificato l'elenco momenti prima, un singolo mancato match
-- non deve interrompere il resto del blocco. Ritorna il conteggio delle righe aggiornate.
-- Rinominata da uspRentriRegistrazioni_upd (2026-09-01) per distinguerla chiaramente da un
-- generico update della registrazione - lega nome SP, checkbox "sincronizza" e campo
-- RentriSincronizzata. Passata da chiamata singola a blocco JSON lo stesso giorno, per
-- evitare N round-trip separati quando ci sono più registrazioni da sincronizzare.
-- exec dbo.uspRentriRegistrazioni_upd_Sincronizza @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Registrazioni='[{"numero":3,"anno":2026,"identificativo":"..."}]', @RentriData='2026-08-15 10:30:00'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_Sincronizza]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Registrazioni NVARCHAR(MAX) = NULL,
	@RentriData DATETIME2(0) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @sincronizzate INT = 0;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL OR @IdSessione IS NULL OR @Registrazioni IS NULL OR @RentriData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri mancanti';
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

		DECLARE @Numero INT, @Anno INT, @Identificativo VARCHAR(50);

		DECLARE c CURSOR LOCAL FAST_FORWARD FOR
		SELECT Numero, Anno, Identificativo
		FROM OPENJSON(@Registrazioni) WITH (
			Numero INT '$.numero',
			Anno INT '$.anno',
			Identificativo VARCHAR(50) '$.identificativo'
		);

		OPEN c;
		FETCH c INTO @Numero, @Anno, @Identificativo;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			UPDATE r
			SET
				RentriIdentificativo = @Identificativo,
				RentriData = @RentriData,
				RentriSincronizzata = 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				m.IdRegistro = @IdRegistro
				AND r.Numero = @Numero
				AND YEAR(r.[Data]) = @Anno
				AND r.Lock = 0
				AND r.RentriIdentificativo IS NULL
				AND r.RentriData IS NULL;

			SET @sincronizzate = @sincronizzate + @@ROWCOUNT;

			FETCH c INTO @Numero, @Anno, @Identificativo;
		END

		CLOSE c;
		DEALLOCATE c;

	END TRY
	BEGIN CATCH
		IF CURSOR_STATUS('local', 'c') >= -1
		BEGIN
			CLOSE c;
			DEALLOCATE c;
		END;
		THROW;
	END CATCH

	BRANCH_END:

	SET NOCOUNT, XACT_ABORT OFF;

	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Sincronizzate = @sincronizzate;

END
GO

--------------------------------------------------------------------------------
-- DROP del vecchio nome SP (dopo aver verificato che la CREATE sopra sia andata a buon fine)
--------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS dbo.uspRentriRegistrazioni_upd;
GO
