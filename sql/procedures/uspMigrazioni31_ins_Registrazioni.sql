SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 5: movimenti e registrazioni. SP interna di uspMigrazioni31_ins, eseguita dentro
-- la sua transazione dopo le fasi 3 e 4 (registri, sedi e autorizzazioni gia' migrati); legge #registrazioni di
-- uspMigrazioni31_get_Perimetro (Importabile = 1, gruppi A-D) e scrive nel #log del chiamante. Inserimenti in blocco.
-- Un movimento 4.0 per ogni registrazione 3.1 (nella 3.1 un movimento puo' avere piu' registrazioni). Corrispondenze:
-- tblRifiutiRegistrazioni e tblRifiutiMovimenti con IdOrigine = Id della registrazione 3.1.
-- Valori: quelli della registrazione cosi' come inviata al RENTRI (Quantita', EER, stato fisico originali; i valori
-- corretti di una rettifica si migrano con le rettifiche). Quantita' e unita' di misura passano sul movimento. Numero e
-- data di inizio trasporto del formulario dalla scheda 3.1 (i formulari non si migrano). Codici con tblMigrazioniCodici,
-- causale -> operazione con tblRifiutiCausaliOperazioni31.
-- Ruoli, solo se previsti dall'operazione 4.0 (Is* di tblRifiutiOperazioni, come uspRifiutiRegistrazioni_upd):
-- - produttore: con il luogo di produzione 3.1 (IDPosizione) l'autorizzazione "Nessuna" di quella sede (e' il produttore
--   che la 3.1 inviava al RENTRI); altrimenti l'autorizzazione del produttore; se manca e l'operazione ha il produttore
--   nella sede del registro (ProduttoreSede), la "Nessuna" della sede del registro. Le "Nessuna" mancanti si creano;
-- - trasportatori (fino a 2, con il tipo di trasporto), destinatario, intermediari (fino a 2): autorizzazioni migrate;
-- - esito, causale di respingimento e quantita' respinta solo con IsEsito; attivita' di provenienza con
--   IsAttivitaProvenienza;
-- - attivita' di destinazione R/D sempre, se presente: l'hub la invia al RENTRI senza filtro per operazione, quindi la
--   3.1 l'ha trasmessa anche per le operazioni che in 4.0 non la prevedono (es. CFP -> F).
-- Le sedi del movimento (IdSede*) sono quelle delle autorizzazioni, come in uspRifiutiRegistrazioni_upd.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Registrazioni
	@IdMigrazione INT = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @IdMigrazione IS NULL OR @IdDominioA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdMigrazione e @IdDominioA sono obbligatori';
			GOTO BRANCH_END;
		END

		-- Registrazioni da migrare, con tutti i valori 4.0
		CREATE TABLE #mov (
			Id31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Gruppo CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdMovimento40 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdRegistrazione40 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			DataInserimento DATETIME2(0) NULL,
			IdRegistro CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdSedeRegistro CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdOperazione CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			Operazione CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IsTrasportatore BIT NULL,
			IsDestinatario BIT NULL,
			IsIntermediario BIT NULL,
			IdEer CHAR(6) COLLATE DATABASE_DEFAULT NULL,
			IdStatoFisico CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdAttivita CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			IdProvenienza CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			Quantita DECIMAL(18, 2) NULL,
			EerDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			FormularioNumero VARCHAR(20) COLLATE DATABASE_DEFAULT NULL,
			DataInizioTrasporto SMALLDATETIME NULL,
			NoteMovimento VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			IdEsito CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdRaee CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdCausaleRespingimento CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdTrasportoTransfrontalieroTipo CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdMateriale CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			IdAttivitaProvenienza CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdUnitaMisuraQuantitaRespinta CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			CausaleRespingimentoAltro VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			QuantitaRespinta DECIMAL(18, 2) NULL,
			DataFineTrasporto SMALLDATETIME NULL,
			[Data] DATE NULL,
			Numero INT NULL,
			QuantitaVerificata DECIMAL(18, 2) NULL,
			VeicoloFuoriUso BIT NULL,
			VeicoloFuoriUsoNumero VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			VeicoloFuoriUsoData DATE NULL,
			MaterialeDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			RentriIdentificativo VARCHAR(20) COLLATE DATABASE_DEFAULT NULL,
			RentriData DATETIME2 NULL,
			ConservazioneSostitutiva BIT NULL,
			NoteRegistrazione VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			-- Ruoli: sede da cui prendere la "Nessuna" del produttore, oppure autorizzazione 3.1 del ruolo
			IdSedeNessuna CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneProduttore31 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneDestinatario31 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneTrasportatore131 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneTrasportatore231 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdTipoTrasporto1 CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdTipoTrasporto2 CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneIntermediario131 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneIntermediario231 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneProduttore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneDestinatario CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneTrasportatore1 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneTrasportatore2 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneIntermediario1 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAutorizzazioneIntermediario2 CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO #mov (
			Id31, Gruppo, DataInserimento, IdRegistro, IdSedeRegistro, IdOperazione, Operazione, IsTrasportatore, IsDestinatario,
			IsIntermediario, IdEer, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione,
			FormularioNumero, DataInizioTrasporto, NoteMovimento, IdEsito, IdRaee, IdCausaleRespingimento,
			IdTrasportoTransfrontalieroTipo, IdMateriale, IdAttivitaProvenienza, IdUnitaMisuraQuantitaRespinta,
			CausaleRespingimentoAltro, QuantitaRespinta, DataFineTrasporto, [Data], Numero, QuantitaVerificata, VeicoloFuoriUso,
			VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione, RentriIdentificativo, RentriData,
			ConservazioneSostitutiva, NoteRegistrazione, IdSedeNessuna, IdAutorizzazioneProduttore31,
			IdAutorizzazioneDestinatario31, IdAutorizzazioneTrasportatore131, IdAutorizzazioneTrasportatore231, IdTipoTrasporto1,
			IdTipoTrasporto2, IdAutorizzazioneIntermediario131, IdAutorizzazioneIntermediario231)
		SELECT
			x.Id,
			x.Gruppo,
			id31.DataInserimento,
			mg.IdDestinazione,
			g.IdSede,
			o.Id,
			o.Operazione,
			ISNULL(o.IsTrasportatore, 0),
			ISNULL(o.IsDestinatario, 0),
			ISNULL(o.IsIntermediario, 0),
			NULLIF(LTRIM(RTRIM(m.IDCER)), ''),
			kSf.CodiceDestinazione,
			kAtt.CodiceDestinazione,
			kUm.CodiceDestinazione,
			kPr.CodiceDestinazione,
			r.[Quantità],
			NULLIF(LTRIM(RTRIM(m.CerDescrizione)), ''),
			NULLIF(LTRIM(RTRIM(s.Numero)), ''),
			s.DataInizioTrasporto,
			NULLIF(LTRIM(RTRIM(m.Note)), ''),
			IIF(ISNULL(o.IsEsito, 0) = 1, kEs.CodiceDestinazione, NULL),
			kRa.CodiceDestinazione,
			IIF(ISNULL(o.IsEsito, 0) = 1, kCr.CodiceDestinazione, NULL),
			IIF(ISNULL(r.Transfrontaliero, 0) = 1, kTf.CodiceDestinazione, NULL),
			kMa.CodiceDestinazione,
			IIF(ISNULL(o.IsAttivitaProvenienza, 0) = 1, kAp.CodiceDestinazione, NULL),
			IIF(ISNULL(o.IsEsito, 0) = 1 AND r.[RespingimentoQuantità] IS NOT NULL, kUm.CodiceDestinazione, NULL),
			IIF(ISNULL(o.IsEsito, 0) = 1, NULLIF(LTRIM(RTRIM(r.RespingimentoMotivo)), ''), NULL),
			IIF(ISNULL(o.IsEsito, 0) = 1, r.[RespingimentoQuantità], NULL),
			r.DataEsito,
			r.[Data],
			r.Numero,
			d.[Quantità],
			ISNULL(m.VeicoloFuoriUso, 0),
			NULLIF(LTRIM(RTRIM(m.VeicoloFuoriUsoNumero)), ''),
			m.VeicoloFuoriUsoData,
			NULLIF(LTRIM(RTRIM(m.MaterialeDescrizione)), ''),
			NULLIF(LTRIM(RTRIM(r.RentriIdentificativo)), ''),
			r.RentriData,
			ISNULL(r.Conservazione, 0),
			NULLIF(LTRIM(RTRIM(r.Note)), ''),
			-- Produttore
			CASE
				WHEN ISNULL(o.IsProduttore, 0) = 0 THEN NULL
				WHEN m.IDPosizione IS NOT NULL THEN mPos.IdDestinazione
				WHEN m.IDAutorizzazioneProduttore IS NOT NULL THEN NULL
				WHEN ISNULL(o.ProduttoreSede, 0) = 1 THEN g.IdSede
			END,
			IIF(ISNULL(o.IsProduttore, 0) = 1 AND m.IDPosizione IS NULL, m.IDAutorizzazioneProduttore, NULL),
			IIF(ISNULL(o.IsDestinatario, 0) = 1, m.IDAutorizzazioneDestinatario, NULL),
			IIF(ISNULL(o.IsTrasportatore, 0) = 1, m.IDAutorizzazioneTrasportatore, NULL),
			IIF(ISNULL(o.IsTrasportatore, 0) = 1 AND m.IDAutorizzazioneTrasportatore IS NOT NULL, m.IDAutorizzazioneTrasportatore2, NULL),
			IIF(ISNULL(o.IsTrasportatore, 0) = 1 AND m.IDAutorizzazioneTrasportatore IS NOT NULL, kT1.CodiceDestinazione, NULL),
			IIF(ISNULL(o.IsTrasportatore, 0) = 1 AND m.IDAutorizzazioneTrasportatore IS NOT NULL AND m.IDAutorizzazioneTrasportatore2 IS NOT NULL, kT2.CodiceDestinazione, NULL),
			IIF(ISNULL(o.IsIntermediario, 0) = 1, m.IDAutorizzazioneIntermediario1, NULL),
			IIF(ISNULL(o.IsIntermediario, 0) = 1 AND m.IDAutorizzazioneIntermediario1 IS NOT NULL, m.IDAutorizzazioneIntermediario2, NULL)
		FROM
			#registrazioni x
			INNER JOIN dbo.syn31RifiutiRegistrazioni r ON x.Id = r.IDRegistrazione COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IDMovimento = m.IDMovimento
			LEFT JOIN dbo.syn31ID id31 ON r.IDRegistrazione = id31.ID
			LEFT JOIN dbo.syn31RifiutiSchede s ON m.IDMovimento = s.IDMovimento
			LEFT JOIN dbo.syn31RifiutiRegistrazioniQuantitaDestino d ON r.IDRegistrazione = d.IDRegistrazione
			LEFT JOIN dbo.tblRifiutiCausaliOperazioni31 co ON x.IdCausale = co.IdCausale
			LEFT JOIN dbo.tblRifiutiOperazioni o ON co.IdOperazione = o.Id
			LEFT JOIN dbo.tblMigrazioniId mg ON mg.Versione = '31'
				AND mg.IdDominioA = @IdDominioA
				AND mg.Tabella = 'tblRifiutiRegistri'
				AND mg.IdOrigine = x.IdRegistro
			LEFT JOIN dbo.tblRifiutiRegistri g ON mg.IdDestinazione = g.Id
			LEFT JOIN dbo.tblMigrazioniId mPos ON mPos.Versione = '31'
				AND mPos.IdDominioA = @IdDominioA
				AND mPos.Tabella = 'tblSedi'
				AND mPos.IdOrigine = m.IDPosizione COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kSf ON kSf.Versione = '31' AND kSf.Tabella = 'tblRifiutiStatiFisici' AND kSf.CodiceOrigine = m.IDStatoFisico COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kAtt ON kAtt.Versione = '31' AND kAtt.Tabella = 'tblRifiutiAttivitaRecuperoSmaltimento' AND kAtt.CodiceOrigine = m.IDDestinazione COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kUm ON kUm.Versione = '31' AND kUm.Tabella = 'tblUnitaMisura' AND kUm.CodiceOrigine = r.[IDUnitàMisura] COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kPr ON kPr.Versione = '31' AND kPr.Tabella = 'tblRifiutiProvenienze' AND kPr.CodiceOrigine = m.Provenienza COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kEs ON kEs.Versione = '31' AND kEs.Tabella = 'tblRifiutiRegistrazioniEsiti' AND kEs.CodiceOrigine = r.IDEsito COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kRa ON kRa.Versione = '31' AND kRa.Tabella = 'tblRifiutiRaee' AND kRa.CodiceOrigine = m.IDRaee COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kCr ON kCr.Versione = '31' AND kCr.Tabella = 'tblRifiutiRegistrazioniEsitiCausaliRespingimento' AND kCr.CodiceOrigine = r.IDEsitoCausaleRespingimento COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kTf ON kTf.Versione = '31' AND kTf.Tabella = 'tblRifiutiTrasportiTransfrontalieriTipi' AND kTf.CodiceOrigine = m.TransfrontalieroTipo COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kMa ON kMa.Versione = '31' AND kMa.Tabella = 'tblRifiutiMateriali' AND kMa.CodiceOrigine = m.IDMaterialeSecondario COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kAp ON kAp.Versione = '31' AND kAp.Tabella = 'tblRifiutiAttivitaProvenienze' AND kAp.CodiceOrigine = m.IDOrigine COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kT1 ON kT1.Versione = '31' AND kT1.Tabella = 'tblRifiutiMovimentiTrasportiTipi' AND kT1.CodiceOrigine = m.TrasportoTipo COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblMigrazioniCodici kT2 ON kT2.Versione = '31' AND kT2.Tabella = 'tblRifiutiMovimentiTrasportiTipi' AND kT2.CodiceOrigine = m.TrasportoTipo2 COLLATE DATABASE_DEFAULT
		WHERE
			x.Importabile = 1
			AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mr WHERE mr.Versione = '31' AND mr.IdDominioA = @IdDominioA AND mr.Tabella = 'tblRifiutiRegistrazioni' AND mr.IdOrigine = x.Id);

		DECLARE @righe INT = (SELECT COUNT(*)
		FROM #mov);

		IF @righe = 0
		BEGIN
			INSERT INTO #log (Fase, Livello, Tabella, Messaggio)
			VALUES ('Registrazioni', 'I', 'tblRifiutiRegistrazioni', 'Nessuna registrazione da migrare');

			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1
		FROM #mov
		WHERE
			IdRegistro IS NULL
			OR IdOperazione IS NULL
			OR [Data] IS NULL
			OR Numero IS NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazioni senza registro migrato, operazione, data o numero: la verifica avrebbe dovuto segnalarle';
			GOTO BRANCH_END;
		END

		-- Autorizzazioni 4.0 dei ruoli (gia' migrate in fase 4)
		UPDATE x
		SET
			IdAutorizzazioneProduttore = ap.IdDestinazione,
			IdAutorizzazioneDestinatario = ad.IdDestinazione,
			IdAutorizzazioneTrasportatore1 = at1.IdDestinazione,
			IdAutorizzazioneTrasportatore2 = at2.IdDestinazione,
			IdAutorizzazioneIntermediario1 = ai1.IdDestinazione,
			IdAutorizzazioneIntermediario2 = ai2.IdDestinazione
		FROM
			#mov x
			LEFT JOIN dbo.tblMigrazioniId ap ON ap.Versione = '31' AND ap.IdDominioA = @IdDominioA AND ap.Tabella = 'tblRifiutiAutorizzazioni' AND ap.IdOrigine = x.IdAutorizzazioneProduttore31
			LEFT JOIN dbo.tblMigrazioniId ad ON ad.Versione = '31' AND ad.IdDominioA = @IdDominioA AND ad.Tabella = 'tblRifiutiAutorizzazioni' AND ad.IdOrigine = x.IdAutorizzazioneDestinatario31
			LEFT JOIN dbo.tblMigrazioniId at1 ON at1.Versione = '31' AND at1.IdDominioA = @IdDominioA AND at1.Tabella = 'tblRifiutiAutorizzazioni' AND at1.IdOrigine = x.IdAutorizzazioneTrasportatore131
			LEFT JOIN dbo.tblMigrazioniId at2 ON at2.Versione = '31' AND at2.IdDominioA = @IdDominioA AND at2.Tabella = 'tblRifiutiAutorizzazioni' AND at2.IdOrigine = x.IdAutorizzazioneTrasportatore231
			LEFT JOIN dbo.tblMigrazioniId ai1 ON ai1.Versione = '31' AND ai1.IdDominioA = @IdDominioA AND ai1.Tabella = 'tblRifiutiAutorizzazioni' AND ai1.IdOrigine = x.IdAutorizzazioneIntermediario131
			LEFT JOIN dbo.tblMigrazioniId ai2 ON ai2.Versione = '31' AND ai2.IdDominioA = @IdDominioA AND ai2.Tabella = 'tblRifiutiAutorizzazioni' AND ai2.IdOrigine = x.IdAutorizzazioneIntermediario231;

		IF EXISTS (SELECT 1
		FROM #mov
		WHERE
			(
			IdAutorizzazioneProduttore31 IS NOT NULL
			AND IdAutorizzazioneProduttore IS NULL
			)
			OR
				(
				IdAutorizzazioneDestinatario31 IS NOT NULL
				AND IdAutorizzazioneDestinatario IS NULL
				)
			OR
				(
				IdAutorizzazioneTrasportatore131 IS NOT NULL
				AND IdAutorizzazioneTrasportatore1 IS NULL
				)
			OR
				(
				IdAutorizzazioneTrasportatore231 IS NOT NULL
				AND IdAutorizzazioneTrasportatore2 IS NULL
				)
			OR
				(
				IdAutorizzazioneIntermediario131 IS NOT NULL
				AND IdAutorizzazioneIntermediario1 IS NULL
				)
			OR
				(
				IdAutorizzazioneIntermediario231 IS NOT NULL
				AND IdAutorizzazioneIntermediario2 IS NULL
				)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazioni con un''autorizzazione non migrata nella fase 4';
			GOTO BRANCH_END;
		END

		-- Produttore "Nessuna": quella attiva della sede (una per sede), creata se manca
		DECLARE @idSede40 CHAR(16);
		DECLARE @idNessuna CHAR(16);
		DECLARE @idOrigineNessuna VARCHAR(50);

		DECLARE cn CURSOR LOCAL FAST_FORWARD FOR
			SELECT DISTINCT x.IdSedeNessuna
			FROM #mov x
			WHERE
				x.IdSedeNessuna IS NOT NULL
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioni a WHERE a.IdSede = x.IdSedeNessuna AND a.Nessuna = 1 AND a.Lock = 0);

		OPEN cn;
		FETCH cn INTO @idSede40;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @idNessuna = NULL;
			SET @idOrigineNessuna = 'Nessuna ' + @idSede40;

			EXEC dbo.uspMigrazioniId_ins
				@Versione = '31',
				@IdDominioA = @IdDominioA,
				@Tabella = 'tblRifiutiAutorizzazioni',
				@IdOrigine = @idOrigineNessuna,
				@IdMigrazione = @IdMigrazione,
				@Id = @idNessuna OUTPUT;

			INSERT INTO dbo.tblRifiutiAutorizzazioni (Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
			VALUES (@idNessuna, @idSede40, 'P', '19000101', '20501231', 1, 0, 0);

			INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
			VALUES ('Registrazioni', 'I', 'tblRifiutiAutorizzazioni', @idOrigineNessuna, 1, CONCAT('Creata l''autorizzazione "Nessuna" ', @idNessuna, ' del produttore'));

			FETCH cn INTO @idSede40;
		END

		CLOSE cn;
		DEALLOCATE cn;

		UPDATE x
		SET IdAutorizzazioneProduttore = n.Id
		FROM
			#mov x
			CROSS APPLY (
				SELECT TOP (1) a.Id
				FROM dbo.tblRifiutiAutorizzazioni a
				WHERE
					a.IdSede = x.IdSedeNessuna
					AND a.Nessuna = 1
					AND a.Lock = 0
				ORDER BY a.Id
			) n
		WHERE x.IdSedeNessuna IS NOT NULL;

		-- Id 4.0 di movimenti e registrazioni
		CREATE TABLE #nuoviId (
			Tabella VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
			IdOrigine VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
			DataInserimento DATETIME2(0) NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			PRIMARY KEY (Tabella, IdOrigine)
		);

		INSERT INTO #nuoviId (Tabella, IdOrigine, DataInserimento)
		SELECT 'tblRifiutiMovimenti', Id31, DataInserimento
		FROM #mov
		UNION ALL
		SELECT 'tblRifiutiRegistrazioni', Id31, DataInserimento
		FROM #mov;

		EXEC dbo.uspMigrazioniId_ins_Lista
			@Versione = '31',
			@IdDominioA = @IdDominioA,
			@IdMigrazione = @IdMigrazione;

		UPDATE x
		SET
			IdMovimento40 = nm.Id,
			IdRegistrazione40 = nr.Id
		FROM
			#mov x
			INNER JOIN #nuoviId nm ON nm.Tabella = 'tblRifiutiMovimenti' AND x.Id31 = nm.IdOrigine
			INNER JOIN #nuoviId nr ON nr.Tabella = 'tblRifiutiRegistrazioni' AND x.Id31 = nr.IdOrigine;

		-- Movimenti, registrazioni e tabelle collegate
		INSERT INTO dbo.tblRifiutiMovimenti
			(Id, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione,
			 FormularioNumero, DataInizioTrasporto, Note)
		SELECT
			IdMovimento40, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione,
			FormularioNumero, DataInizioTrasporto, NoteMovimento
		FROM #mov;

		INSERT INTO dbo.tblRifiutiRegistrazioni
			(Id, IdMovimento, IdEsito, IdRaee, IdCausaleRespingimento, IdTrasportoTransfrontalieroTipo, IdMateriale, IdAttivitaProvenienza,
			 IdUnitaMisuraQuantitaRespinta, CausaleRespingimentoAltro, QuantitaRespinta, DataFineTrasporto, Operazione, [Data], Numero,
			 QuantitaVerificata, VeicoloFuoriUso, VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione, RentriIdentificativo,
			 RentriData, ConservazioneSostitutiva, Note, Lock)
		SELECT
			IdRegistrazione40, IdMovimento40, IdEsito, IdRaee, IdCausaleRespingimento, IdTrasportoTransfrontalieroTipo, IdMateriale,
			IdAttivitaProvenienza, IdUnitaMisuraQuantitaRespinta, CausaleRespingimentoAltro, QuantitaRespinta, DataFineTrasporto, Operazione,
			[Data], Numero, QuantitaVerificata, VeicoloFuoriUso, VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione,
			RentriIdentificativo, RentriData, ConservazioneSostitutiva, NoteRegistrazione, 0
		FROM #mov;

		INSERT INTO dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
		SELECT IdMovimento40, IdAutorizzazioneProduttore, Quantita, 0
		FROM #mov
		WHERE IdAutorizzazioneProduttore IS NOT NULL;

		INSERT INTO dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
		SELECT IdMovimento40, IdAutorizzazioneDestinatario, 0
		FROM #mov
		WHERE IdAutorizzazioneDestinatario IS NOT NULL;

		INSERT INTO dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos, IdTipo)
		SELECT IdMovimento40, IdAutorizzazioneTrasportatore1, 0, IdTipoTrasporto1
		FROM #mov
		WHERE IdAutorizzazioneTrasportatore1 IS NOT NULL
		UNION ALL
		SELECT IdMovimento40, IdAutorizzazioneTrasportatore2, 1, IdTipoTrasporto2
		FROM #mov
		WHERE
			IdAutorizzazioneTrasportatore1 IS NOT NULL
			AND IdAutorizzazioneTrasportatore2 IS NOT NULL;

		INSERT INTO dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
		SELECT IdMovimento40, IdAutorizzazioneIntermediario1, 0
		FROM #mov
		WHERE IdAutorizzazioneIntermediario1 IS NOT NULL
		UNION ALL
		SELECT IdMovimento40, IdAutorizzazioneIntermediario2, 1
		FROM #mov
		WHERE
			IdAutorizzazioneIntermediario1 IS NOT NULL
			AND IdAutorizzazioneIntermediario2 IS NOT NULL;

		INSERT INTO dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
		SELECT DISTINCT x.IdMovimento40, k.CodiceDestinazione
		FROM
			#mov x
			INNER JOIN dbo.syn31RifiutiRegistrazioni r ON x.Id31 = r.IDRegistrazione COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiMovimentiClassiPericolo c ON r.IDMovimento = c.IDMovimento
			INNER JOIN dbo.tblMigrazioniCodici k ON k.Versione = '31'
				AND k.Tabella = 'tblRifiutiClassiPericolo'
				AND k.CodiceOrigine = c.IDClasse COLLATE DATABASE_DEFAULT
		WHERE k.CodiceDestinazione IS NOT NULL;

		-- Luoghi di produzione (piu' unita' locali, pulizia manutentiva)
		INSERT INTO dbo.tblRifiutiMovimentiSediProduzione (Id, IdSede, Quantita, Pos)
		SELECT x.IdMovimento40, ms.IdDestinazione, MAX(sp.[Quantità]), MIN(sp.Pos)
		FROM
			#mov x
			INNER JOIN dbo.syn31RifiutiRegistrazioni r ON x.Id31 = r.IDRegistrazione COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiMovimentiSedi sp ON r.IDMovimento = sp.IDMovimento
			INNER JOIN dbo.tblMigrazioniId ms ON ms.Versione = '31'
				AND ms.IdDominioA = @IdDominioA
				AND ms.Tabella = 'tblSedi'
				AND ms.IdOrigine = sp.IDSede COLLATE DATABASE_DEFAULT
		GROUP BY x.IdMovimento40, ms.IdDestinazione;

		-- Sedi del movimento dalle autorizzazioni dei ruoli, come uspRifiutiRegistrazioni_upd
		UPDATE m
		SET
			IdSedeProduttoreDetentore = ap.IdSede,
			IdSedeDestinatario = ad.IdSede,
			IdSedeTrasportatore1 = ar.IdSede,
			IdSedeIntermediario1 = ai.IdSede
		FROM
			#mov x
			INNER JOIN dbo.tblRifiutiMovimenti m ON x.IdMovimento40 = m.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON x.IdAutorizzazioneProduttore = ap.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON x.IdAutorizzazioneDestinatario = ad.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON x.IdAutorizzazioneTrasportatore1 = ar.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON x.IdAutorizzazioneIntermediario1 = ai.Id;

		INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
		SELECT 'Registrazioni', 'I', 'tblRifiutiRegistrazioni', NULL, COUNT(*),
			CONCAT('Migrate ', COUNT(*), ' registrazioni del gruppo ', Gruppo, ' (', SUM(IIF(RentriIdentificativo IS NULL, 0, 1)), ' inviate al RENTRI)')
		FROM #mov
		GROUP BY Gruppo;
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
