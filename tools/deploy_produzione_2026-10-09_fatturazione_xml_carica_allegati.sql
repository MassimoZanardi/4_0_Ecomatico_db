/*
Deploy produzione 2026-10-09 - Fatturazione: Carica file XML (fatture fornitori) e Genera file XML di una fattura
sola, anche con allegati (fatture clienti)

Da eseguire DOPO deploy_produzione_2026-10-08_fatturazione_xml.sql (usa tblFatture.DataXml). Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

Carica file XML (fattura elettronica ricevuta):
1. uspFatture_get_XmlCarica: azienda del contesto, fornitore del file e fattura già registrata.
2. uspFatture_get_XmlCarica_Codici_List: aliquote IVA, modalità di pagamento, tipi di documento, valute e
   unità di misura con cui l'applicazione traduce i valori del file.
3. uspFatture_ins_Xml: crea la fattura fornitore in bozza con la testata letta dal file.
4. uspFatture_get: restituisce anche DataXml (fattura nata da un file).

Genera file XML di una fattura sola (dalla scheda, o dall'elenco con allegati):
5. ufnFatture_get_XmlIntervallo: nuovo parametro @Id (la funzione va prima della SP che la usa).
6. uspFatture_get_Xml_List: nuovo parametro @Id.

Nessuna modifica alle tabelle. Va deployato insieme all'app: il file viene letto e composto dall'applicazione
(FatturaXmlCaricaService, FatturaXmlService), e la versione precedente dell'app chiama la funzione senza @Id.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'uspFatture_get_XmlCarica';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture fornitori > Carica file XML: dati che servono all'applicazione (FatturaXmlCaricaService) per
-- controllare il file prima di caricarlo. Sempre una riga:
--   l'azienda del contesto (il destinatario del file deve essere lei);
--   il fornitore del file, cercato tra le schede fornitore attive dell'azienda per partita IVA o codice
--     fiscale (Fornitori = quante schede corrispondono: con più di una la scelta resta all'utente);
--   IsPresente = 1 se la fattura è già registrata (stesso fornitore, stesso numero, stesso anno del documento).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_XmlCarica
	@IdSessione CHAR(16) = NULL,
	@PartitaIva VARCHAR(30) = NULL,
	@CodiceFiscale VARCHAR(30) = NULL,
	@NumeroFornitore VARCHAR(30) = NULL,
	@DataEmissione DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @PartitaIva = NULLIF(LTRIM(RTRIM(@PartitaIva)), '');
		SET @CodiceFiscale = NULLIF(LTRIM(RTRIM(@CodiceFiscale)), '');
		SET @NumeroFornitore = NULLIF(LTRIM(RTRIM(@NumeroFornitore)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: il caricamento registra una fattura
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

		-- Fornitore: scheda attiva dell'azienda con la stessa partita IVA o lo stesso codice fiscale
		DECLARE @fornitori INT;
		DECLARE @idClienteFornitore CHAR(16);
		DECLARE @fornitoreNome VARCHAR(500);
		SELECT
			@fornitori = COUNT(*),
			@idClienteFornitore = MIN(c.Id)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.IdAziendaInterna = @idAzienda
			AND c.Tipo = 'F'
			AND c.Lock = 0
			AND (
				(@PartitaIva IS NOT NULL AND s.PartitaIva = @PartitaIva)
				OR (@CodiceFiscale IS NOT NULL AND s.CodiceFiscale = @CodiceFiscale)
			);

		IF @fornitori <> 1
			SET @idClienteFornitore = NULL;

		SELECT @fornitoreNome = s.NomeCompleto
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE c.Id = @idClienteFornitore;

		-- Fattura già registrata: stesso fornitore, stesso numero e stesso anno del documento
		DECLARE @isPresente BIT = 0;
		IF @idClienteFornitore IS NOT NULL AND @NumeroFornitore IS NOT NULL AND @DataEmissione IS NOT NULL
			AND EXISTS (
				SELECT 1
				FROM dbo.tblFatture
				WHERE
					IdSede = @idAzienda
					AND Tipo = 'F'
					AND Lock = 0
					AND IdClienteFornitore = @idClienteFornitore
					AND NumeroFornitore = @NumeroFornitore
					AND YEAR(DataEmissione) = YEAR(@DataEmissione)
			)
			SET @isPresente = 1;

		SELECT
			AziendaNome = a.NomeCompleto,
			AziendaPartitaIva = a.PartitaIva,
			AziendaCodiceFiscale = a.CodiceFiscale,
			IdClienteFornitore = @idClienteFornitore,
			FornitoreNome = @fornitoreNome,
			Fornitori = ISNULL(@fornitori, 0),
			IsPresente = @isPresente
		FROM dbo.tblSedi a
		WHERE a.Id = @idAzienda;

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

PRINT 'uspFatture_get_XmlCarica_Codici_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture fornitori > Carica file XML: codici con cui l'applicazione (FatturaXmlCaricaService) traduce i
-- valori del file negli Id del database. Un solo elenco, distinto da Elenco:
--   A aliquote IVA attive, di sistema o dell'azienda del contesto: Valore = percentuale, Codice = natura
--     (prima quelle di sistema: a parità di percentuale e natura si usa la prima);
--   M modalità di pagamento, T tipi di documento, V valute: l'Id è il codice del tracciato (MP05, TD01, EUR);
--   U unità di misura: Codice = sigla, Nome = descrizione.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_XmlCarica_Codici_List
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

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT Elenco, Id, Codice, Nome, Valore
		FROM (
			SELECT
				Elenco = 'A',
				Id = CAST(a.Id AS VARCHAR(16)),
				Codice = CAST(a.IdNatura AS VARCHAR(10)),
				Nome = CAST(a.Nome AS VARCHAR(100)),
				Valore = a.Valore,
				Pos = IIF(a.IdSede IS NULL, 0, 1)
			FROM dbo.tblAliquoteIva a
			WHERE
				(a.IdSede IS NULL OR a.IdSede = @idAzienda)
				AND a.Lock = 0

			UNION ALL

			SELECT 'M', CAST(Id AS VARCHAR(16)), CAST(NULL AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblPagamentiModalita

			UNION ALL

			SELECT 'T', CAST(Id AS VARCHAR(16)), CAST(NULL AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblFattureTipi

			UNION ALL

			SELECT 'V', CAST(Id AS VARCHAR(16)), CAST(NULL AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblPagamentiValute

			UNION ALL

			SELECT 'U', CAST(Id AS VARCHAR(16)), CAST(Codice AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblUnitaMisura
		) t
		ORDER BY Elenco, Pos, Nome, Id;

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

PRINT 'uspFatture_ins_Xml';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture fornitori > Carica file XML: crea la fattura fornitore in bozza (Lock 2) con la testata letta dal
-- file della fattura elettronica. Righe e rate le aggiunge poi l'applicazione con uspFattureRighe_upd e
-- uspFattureRate_upd; la bozza si conferma dalla scheda con "Salva" (uspFatture_upd), che applica tutti i
-- controlli della testata e assegna il numero.
-- Il fornitore può mancare (non trovato in anagrafica): si sceglie nella scheda. DataXml = momento del
-- caricamento: distingue le fatture nate da un file, su cui la scelta del fornitore non sostituisce le
-- condizioni di pagamento arrivate dal file.
-- Restituisce l'Id della fattura.
CREATE OR ALTER PROCEDURE dbo.uspFatture_ins_Xml
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdValuta CHAR(3) = NULL,
	@NumeroFornitore VARCHAR(50) = NULL,
	@DataEmissione DATE = NULL,
	@Iban VARCHAR(50) = NULL,
	@Ordine VARCHAR(50) = NULL,
	@DataOrdine DATE = NULL,
	@SplitPayment BIT = 0,
	@Bollo DECIMAL(9, 2) = NULL,
	@CodiceCig VARCHAR(20) = NULL,
	@CodiceCup VARCHAR(20) = NULL,
	@Causale VARCHAR(250) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @IdTipo = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@IdTipo)), '')), 'TD01');
		SET @IdModalita = UPPER(NULLIF(LTRIM(RTRIM(@IdModalita)), ''));
		SET @IdValuta = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@IdValuta)), '')), 'EUR');
		SET @NumeroFornitore = NULLIF(LTRIM(RTRIM(@NumeroFornitore)), '');
		-- IBAN, CIG e CUP: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceCig = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCig)), ' ', '')), '');
		SET @CodiceCup = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCup)), ' ', '')), '');
		SET @Ordine = NULLIF(LTRIM(RTRIM(@Ordine)), '');
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @SplitPayment = ISNULL(@SplitPayment, 0);
		SET @Bollo = ISNULL(@Bollo, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @NumeroFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il file non indica il numero della fattura';
			GOTO BRANCH_END;
		END
		IF @DataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il file non indica la data della fattura';
			GOTO BRANCH_END;
		END
		IF LEN(@NumeroFornitore) > 30 OR LEN(@Iban) > 34 OR LEN(@Ordine) > 30 OR LEN(@CodiceCig) > 10 OR LEN(@CodiceCup) > 15 OR LEN(@Causale) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un dato della testata supera la lunghezza ammessa';
			GOTO BRANCH_END;
		END
		IF @Bollo < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il bollo non può essere negativo';
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

		-- Fornitore, se indicato: scheda fornitore attiva dell'azienda
		IF @IdClienteFornitore IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'F'
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il fornitore indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Tipo di documento, modalità e valuta sono codici del tracciato: la pre-fattura non è un documento ricevuto
		IF @IdTipo = 'TD00' OR NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = @IdTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di documento indicato non esiste';
			GOTO BRANCH_END;
		END
		IF @IdModalita IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = @IdValuta)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La valuta indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Fattura già registrata: stesso fornitore, stesso numero e stesso anno del documento
		IF @IdClienteFornitore IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblFatture
			WHERE
				IdSede = @idAzienda
				AND Tipo = 'F'
				AND Lock = 0
				AND IdClienteFornitore = @IdClienteFornitore
				AND NumeroFornitore = @NumeroFornitore
				AND YEAR(DataEmissione) = YEAR(@DataEmissione)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è già registrata: stesso fornitore, stesso numero e stesso anno';
			GOTO BRANCH_END;
		END

		-- La data dell'ordine non segue quella della fattura (come in uspFatture_upd): altrimenti non si importa
		IF @DataOrdine > @DataEmissione
			SET @DataOrdine = NULL;

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza, come uspFatture_ins: stato Generata, rate dalla data fattura (DF), registrazione di oggi
		BEGIN TRANSACTION;
			INSERT dbo.tblFatture (
				Id, IdSede, IdClienteFornitore, Tipo, IdTipo, IdStato, IdModalita, IdValuta, IdRataInizio,
				NumeroFornitore, DataRegistrazione, DataEmissione, Causale, Iban, RataGiorniInizio, Ordine, DataOrdine,
				SplitPayment, Bollo, CodiceCig, CodiceCup, SolaLettura, Lock, DataXml)
			VALUES (
				@returnId, @idAzienda, @IdClienteFornitore, 'F', @IdTipo, 'G', @IdModalita, @IdValuta, 'DF',
				@NumeroFornitore, CAST(GETDATE() AS DATE), @DataEmissione, @Causale, @Iban, 0, @Ordine, @DataOrdine,
				@SplitPayment, @Bollo, @CodiceCig, @CodiceCup, 0, 2, GETDATE());
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
			-- Fattura cliente: ultimo file XML generato; fattura fornitore: caricamento del file da cui è nata
			f.DataXml,
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

PRINT 'ufnFatture_get_XmlIntervallo';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture clienti dell'intervallo scelto per la generazione dei file XML della fattura elettronica: attive,
-- numerate (le pre-fatture non hanno numero), dell'azienda interna corrente della sessione, con il numero tra
-- @DalNumero e @AlNumero e la data di emissione nell'anno @Anno. @Sezionale: NULL tutti i sezionali, '0' solo
-- le fatture senza sezionale, altrimenti la lettera. @EscludiGenerate = 1 lascia fuori le fatture di cui è già
-- stato generato il file (DataXml). Con @Id si considera solo quella fattura (generazione di una fattura sola,
-- anche con allegati): valgono gli stessi requisiti, non numero, anno, sezionale e @EscludiGenerate.
-- Usata dalle uspFatture_get_Xml*_List, che devono vedere le stesse fatture.
CREATE OR ALTER FUNCTION dbo.ufnFatture_get_XmlIntervallo
(
	@IdSessione CHAR(16),
	@DalNumero INT,
	@AlNumero INT,
	@Anno INT,
	@Sezionale CHAR(1),
	@EscludiGenerate BIT,
	@Id CHAR(16)
)
RETURNS TABLE
AS
RETURN
(
	SELECT f.Id
	FROM
		dbo.tblFatture f
		INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
	WHERE
		e.Id = @IdSessione
		AND f.Tipo = 'C'
		AND f.Lock = 0
		AND f.Numero IS NOT NULL
		AND ISNULL(f.IdTipo, '') <> 'TD00'
		AND
			(
			(@Id IS NOT NULL AND f.Id = @Id)
			OR
				(
				@Id IS NULL
				AND f.Numero >= ISNULL(@DalNumero, 1)
				AND f.Numero <= ISNULL(@AlNumero, 2147483647)
				-- Con @Id l'anno non serve e può non essere valido: le due date devono comunque potersi calcolare
				AND f.DataEmissione >= DATEFROMPARTS(IIF(@Id IS NULL, @Anno, 2000), 1, 1)
				AND f.DataEmissione < DATEFROMPARTS(IIF(@Id IS NULL, @Anno, 2000) + 1, 1, 1)
				AND
					(
					@Sezionale IS NULL
					OR (@Sezionale = '0' AND f.Sezionale IS NULL)
					OR f.Sezionale = @Sezionale
					)
				AND (ISNULL(@EscludiGenerate, 0) = 0 OR f.DataXml IS NULL)
				)
			)
);
GO

PRINT 'uspFatture_get_Xml_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati per il file XML della fattura elettronica delle fatture clienti dell'intervallo (ufnFatture_get_XmlIntervallo).
-- @Elenco sceglie che cosa restituire, sempre per le stesse fatture:
--   T testate: fattura, azienda che emette (Ced*, con i dati fiscali) e cliente (Ces*), fattura di riferimento
--     della nota di credito, banca dell'azienda, totali. Al massimo 101 righe: la 101a dice a chi chiama che
--     l'intervallo supera il limite di 100 fatture per generazione.
--   R righe, in ordine di posizione; A rate, in ordine di scadenza.
-- Con @Id si lavora su quella sola fattura (generazione dalla scheda o con allegati): intervallo e anno non servono.
-- I controlli sui dati mancanti e la composizione del file sono nell'applicazione (FatturaXmlService).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Xml_List
	@IdSessione CHAR(16) = NULL,
	@Elenco CHAR(1) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@Sezionale CHAR(1) = NULL,
	@EscludiGenerate BIT = 0,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Elenco = UPPER(NULLIF(LTRIM(RTRIM(@Elenco)), ''));
		SET @Sezionale = UPPER(NULLIF(LTRIM(RTRIM(@Sezionale)), ''));
		SET @EscludiGenerate = ISNULL(@EscludiGenerate, 0);
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Elenco IS NULL OR @Elenco NOT IN ('T', 'R', 'A')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Elenco deve essere T (testate), R (righe) o A (rate)';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND (@Anno IS NULL OR @Anno < 1900 OR @Anno > 9998)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''anno delle fatture';
			GOTO BRANCH_END;
		END
		IF @DalNumero > @AlNumero
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero iniziale non può essere maggiore di quello finale';
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

		IF @Elenco = 'T'
			SELECT TOP (101)
				f.Id,
				f.Numero,
				f.Sezionale,
				f.DataEmissione,
				f.IdTipo,
				f.IdValuta,
				f.IdModalita,
				f.Causale,
				Bollo = ISNULL(f.Bollo, 0),
				SplitPayment = ISNULL(f.SplitPayment, 0),
				f.Ordine,
				f.DataOrdine,
				f.CodiceCig,
				f.CodiceCup,
				f.DataXml,
				RiferimentoNumero = rf.Numero,
				RiferimentoSezionale = rf.Sezionale,
				RiferimentoData = rf.DataEmissione,
				BancaNome = b.Nome,
				BancaIban = b.Iban,
				BancaBic = b.Bic,
				t.Imponibile,
				t.Iva,
				t.Ritenuta,
				t.Totale,
				t.NettoAPagare,
				CedIdTipo = a.IdTipo,
				CedNome = a.Nome,
				CedCognome = a.Cognome,
				CedPartitaIva = a.PartitaIva,
				CedCodiceFiscale = a.CodiceFiscale,
				CedIndirizzo = ai.Indirizzo,
				CedNumeroCivico = ai.NumeroCivico,
				CedCap = ai.CAP,
				CedComune = ac.Nome,
				CedProvincia = ap.Sigla,
				CedNazione = an.Sigla,
				d.IdRegimeFiscale,
				ReaUfficio = dp.Sigla,
				d.NumeroRea,
				d.CapitaleSociale,
				d.SocioUnico,
				d.StatoLiquidazione,
				d.IdRitenutaTipo,
				d.IdRitenutaCausale,
				f.IdClienteFornitore,
				CesIdTipo = s.IdTipo,
				CesNome = s.Nome,
				CesCognome = s.Cognome,
				CesNomeCompleto = s.NomeCompleto,
				CesPartitaIva = s.PartitaIva,
				CesCodiceFiscale = s.CodiceFiscale,
				CesIndirizzo = si.Indirizzo,
				CesNumeroCivico = si.NumeroCivico,
				CesCap = si.CAP,
				CesComune = sc.Nome,
				CesProvincia = sp.Sigla,
				CesNazione = sn.Sigla,
				c.CodiceDestinatario,
				c.PecDestinatario
			FROM
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate, @Id) x
				INNER JOIN dbo.tblFatture f ON x.Id = f.Id
				INNER JOIN dbo.tblSedi a ON f.IdSede = a.Id
				LEFT JOIN dbo.tblSediIndirizzi asi ON a.Id = asi.Id
				LEFT JOIN dbo.tblIndirizzi ai ON asi.IdIndirizzo = ai.Id
				LEFT JOIN dbo.tblComuni ac ON ai.IdComune = ac.Id
				LEFT JOIN dbo.tblProvince ap ON ac.IdProvincia = ap.Id
				LEFT JOIN dbo.tblNazioni an ON ai.IdNazione = an.Id
				LEFT JOIN dbo.tblFattureDatiFiscali d ON a.Id = d.Id
				LEFT JOIN dbo.tblProvince dp ON d.IdProvinciaRea = dp.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblSediIndirizzi ssi ON s.Id = ssi.Id
				LEFT JOIN dbo.tblIndirizzi si ON ssi.IdIndirizzo = si.Id
				LEFT JOIN dbo.tblComuni sc ON si.IdComune = sc.Id
				LEFT JOIN dbo.tblProvince sp ON sc.IdProvincia = sp.Id
				LEFT JOIN dbo.tblNazioni sn ON si.IdNazione = sn.Id
				LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
			ORDER BY
				f.Numero,
				f.Sezionale,
				f.Id;
		ELSE IF @Elenco = 'R'
			SELECT
				r.IdFattura,
				r.Pos,
				r.Descrizione,
				ConImporti = CAST(IIF(i.Id IS NULL, 0, 1) AS BIT),
				i.Quantita,
				i.Importo,
				UnitaMisuraCodice = u.Codice,
				i.IdAliquotaIva,
				AliquotaValore = v.Valore,
				v.IdNatura,
				NaturaNome = n.Nome,
				v.RiferimentoNormativo,
				RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0),
				Imponibile = CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2))
			FROM
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate, @Id) x
				INNER JOIN dbo.tblFattureRighe r ON x.Id = r.IdFattura
				LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				LEFT JOIN dbo.tblUnitaMisura u ON i.IdUnitaMisura = u.Id
				LEFT JOIN dbo.tblAliquoteIva v ON i.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblAliquoteIvaNatura n ON v.IdNatura = n.Id
			ORDER BY
				r.IdFattura,
				r.Pos,
				r.Id;
		ELSE
			SELECT
				r.IdFattura,
				r.DataScadenza,
				Importo = CAST(ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) AS DECIMAL(18, 2))
			FROM
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate, @Id) x
				INNER JOIN dbo.tblFattureRate r ON x.Id = r.IdFattura
			ORDER BY
				r.IdFattura,
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
