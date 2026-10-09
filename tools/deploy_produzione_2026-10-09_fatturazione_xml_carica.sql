/*
Deploy produzione 2026-10-09 - Fatturazione > Fatture fornitori > Carica file XML (fattura elettronica ricevuta)

Da eseguire DOPO deploy_produzione_2026-10-08_fatturazione_xml.sql (usa tblFatture.DataXml). Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

1. uspFatture_get_XmlCarica: azienda del contesto, fornitore del file e fattura già registrata.
2. uspFatture_get_XmlCarica_Codici_List: aliquote IVA, modalità di pagamento, tipi di documento, valute e
   unità di misura con cui l'applicazione traduce i valori del file.
3. uspFatture_ins_Xml: crea la fattura fornitore in bozza con la testata letta dal file.
4. uspFatture_get: restituisce anche DataXml (fattura nata da un file).

Nessuna modifica alle tabelle. Va deployato insieme all'app: il file viene letto dall'applicazione
(FatturaXmlCaricaService).

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
