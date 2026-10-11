/*
Deploy produzione 2026-10-11 - Fatturazione: indici e numerazione

Da eseguire DOPO deploy_produzione_2026-10-10_domini_moduli_nessuno.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I. Nessuna modifica all'app: si può deployare da solo.

1. Indici (tools\fatturazione_indici.sql, dettaglio in indici-4_0_ecomatico.md, punti 21-26):
   - 10 indici rinominati alla convenzione IX_ / UX_ senza "tbl" (7 del modulo, 3 di tblAmministratori);
   - nuovi: IX_FattureRatePagamenti_IdPagamento, IX_Pagamenti_IdSede_IdBancaCassa_DataContabile_DataRegistrazione_Lock,
     IX_Fatture_IdFatturaRiferimento, IX_BancheCasse_IdSede, IX_AliquoteIva_IdSede;
   - estesi con colonne incluse: IX_Fatture_IdSede_Tipo_DataEmissione, IX_FattureRate_IdFattura.
2. uspFatture_upd, uspFatture_get_ProssimoNumero: numerazione con il filtro sulla colonna della data, in due
   letture (clienti, fornitori); il blocco UPDLOCK, HOLDLOCK delle fatture cliente copre solo l'anno dell'azienda.
3. uspFatture_upd_Xml: tolto l'hint UPDLOCK, HOLDLOCK dall'UPDATE dei dati fiscali, superfluo.
4. uspBancheCasse_del, uspFattureConti_del: il controllo sui pagamenti filtra anche per azienda e usa il nuovo
   indice dei pagamenti.
5. uspFatture_get_List: prima la pagina, poi totali e rate solo per le fatture della pagina (stessi risultati).
6. uspFattureRate_get_Scadenzario_List: il residuo si calcola con le sole colonne di filtro e ordinamento, il
   resto della riga si legge solo per le rate della pagina (stessi risultati).

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'fatturazione_indici.sql';
GO
/*
Indici del modulo Fatturazione e nomi allineati alla convenzione (indici-4_0_ecomatico.md, punti 21-26).
Rieseguibile. Eseguire con sqlcmd -f 65001 -I.

Nomi: IX_<Tabella senza "tbl">_<Colonne>[_Lock], UX_ per gli indici unici.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

-- 1. Nomi alla convenzione: gli indici nati con le tabelle avevano "tbl" nel nome
DECLARE @nomi TABLE (Tabella SYSNAME, Vecchio SYSNAME, Nuovo SYSNAME);
INSERT @nomi (Tabella, Vecchio, Nuovo)
VALUES
	('tblClientiFornitori', 'IX_tblClientiFornitori_IdSede', 'IX_ClientiFornitori_IdSede'),
	('tblClientiFornitori', 'UX_tblClientiFornitori_IdAziendaInterna_IdSede_Tipo', 'UX_ClientiFornitori_IdAziendaInterna_IdSede_Tipo_Lock'),
	('tblFatture', 'IX_tblFatture_IdClienteFornitore', 'IX_Fatture_IdClienteFornitore'),
	('tblFatture', 'IX_tblFatture_IdSede_Tipo_DataEmissione', 'IX_Fatture_IdSede_Tipo_DataEmissione'),
	('tblFattureConti', 'IX_tblFattureConti_IdSede', 'IX_FattureConti_IdSede'),
	('tblFattureRate', 'IX_tblFattureRate_IdFattura', 'IX_FattureRate_IdFattura'),
	('tblFattureRighe', 'IX_tblFattureRighe_IdFattura', 'IX_FattureRighe_IdFattura'),
	('tblAmministratori', 'IX_tblAmministratori_IdSede', 'IX_Amministratori_IdSede'),
	('tblAmministratori', 'UX_tblAmministratori_IdAziendaInterna_IdSede', 'UX_Amministratori_IdAziendaInterna_IdSede_Lock'),
	('tblAmministratoriSedi', 'IX_tblAmministratoriSedi_IdSede', 'IX_AmministratoriSedi_IdSede');

DECLARE @tabella SYSNAME;
DECLARE @vecchio SYSNAME;
DECLARE @nuovo SYSNAME;
DECLARE @oggetto NVARCHAR(400);
DECLARE cNomi CURSOR LOCAL FAST_FORWARD FOR
	SELECT Tabella, Vecchio, Nuovo
	FROM @nomi;
OPEN cNomi;
FETCH cNomi INTO @tabella, @vecchio, @nuovo;
WHILE @@FETCH_STATUS = 0
BEGIN
	IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.' + @tabella) AND name = @vecchio)
		AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.' + @tabella) AND name = @nuovo)
	BEGIN
		SET @oggetto = 'dbo.' + @tabella + '.' + @vecchio;
		EXEC sys.sp_rename @objname = @oggetto, @newname = @nuovo, @objtype = 'INDEX';
		PRINT @vecchio + ' -> ' + @nuovo;
	END
	FETCH cNomi INTO @tabella, @vecchio, @nuovo;
END
CLOSE cNomi;
DEALLOCATE cNomi;
GO

-- 2. tblFattureRatePagamenti: IdPagamento è la seconda colonna della chiave primaria (IdRata, IdPagamento).
--    Prima nota (due ricerche per ogni movimento), uspPagamenti_get_List / _get_Rate_List / _del /
--    _del_Manuale / _upd_Manuale e il controllo della chiave esterna quando si elimina un pagamento
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblFattureRatePagamenti') AND name = 'IX_FattureRatePagamenti_IdPagamento')
	CREATE NONCLUSTERED INDEX IX_FattureRatePagamenti_IdPagamento
	ON dbo.tblFattureRatePagamenti (IdPagamento)
	INCLUDE (Importo);
GO

-- 3. tblPagamenti: i movimenti attivi dell'azienda nell'ordine della prima nota (saldo progressivo per
--    banca o cassa: PARTITION BY IdBancaCassa ORDER BY DataContabile, DataRegistrazione, Id), con le
--    colonne che la prima nota legge. Serve anche ai controlli di uspBancheCasse_del e uspFattureConti_del
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblPagamenti') AND name = 'IX_Pagamenti_IdSede_IdBancaCassa_DataContabile_DataRegistrazione_Lock')
	CREATE NONCLUSTERED INDEX IX_Pagamenti_IdSede_IdBancaCassa_DataContabile_DataRegistrazione_Lock
	ON dbo.tblPagamenti (IdSede, IdBancaCassa, DataContabile, DataRegistrazione)
	INCLUDE (Tipo, Importo, IdModalita, IdConto, Causale)
	WHERE Lock = 0;
GO

-- 4. tblFatture (IdSede, Tipo, DataEmissione): stessa chiave, con le colonne che elenco, fatturato,
--    intervallo XML e numerazione leggono o filtrano (Lock prima di tutte). Non filtrato: la cancellazione
--    di un'azienda cerca per IdSede senza Lock
IF NOT EXISTS (
	SELECT 1
	FROM
		sys.indexes i
		INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
		INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
	WHERE
		i.object_id = OBJECT_ID('dbo.tblFatture')
		AND i.name = 'IX_Fatture_IdSede_Tipo_DataEmissione'
		AND ic.is_included_column = 1
		AND c.name = 'Lock'
)
BEGIN
	IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblFatture') AND name = 'IX_Fatture_IdSede_Tipo_DataEmissione')
		DROP INDEX IX_Fatture_IdSede_Tipo_DataEmissione ON dbo.tblFatture;

	CREATE NONCLUSTERED INDEX IX_Fatture_IdSede_Tipo_DataEmissione
	ON dbo.tblFatture (IdSede, Tipo, DataEmissione)
	INCLUDE (Lock, IdTipo, Numero, Sezionale, IdClienteFornitore, DataRegistrazione);
END
GO

-- 5. tblFatture.IdFatturaRiferimento: solo le note di credito lo valorizzano. uspFatture_del controlla se
--    la fattura è richiamata da una nota di credito, e la chiave esterna di tblFatture su sé stessa fa lo
--    stesso controllo a ogni eliminazione fisica: senza indice, uno scan dell'intera tabella
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblFatture') AND name = 'IX_Fatture_IdFatturaRiferimento')
	CREATE NONCLUSTERED INDEX IX_Fatture_IdFatturaRiferimento
	ON dbo.tblFatture (IdFatturaRiferimento)
	INCLUDE (Lock)
	WHERE IdFatturaRiferimento IS NOT NULL;
GO

-- 6. tblFattureRate (IdFattura): stessa chiave, con le colonne lette da scadenziario ed elenco fatture
IF NOT EXISTS (
	SELECT 1
	FROM
		sys.indexes i
		INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
		INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
	WHERE
		i.object_id = OBJECT_ID('dbo.tblFattureRate')
		AND i.name = 'IX_FattureRate_IdFattura'
		AND ic.is_included_column = 1
		AND c.name = 'DataScadenza'
)
BEGIN
	IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblFattureRate') AND name = 'IX_FattureRate_IdFattura')
		DROP INDEX IX_FattureRate_IdFattura ON dbo.tblFattureRate;

	CREATE NONCLUSTERED INDEX IX_FattureRate_IdFattura
	ON dbo.tblFattureRate (IdFattura)
	INCLUDE (Importo, Abbuono, DataScadenza);
END
GO

-- 7. tblBancheCasse e tblAliquoteIva: il filtro per azienda è l'unico accesso oltre la chiave primaria
--    (select a ogni apertura di fattura, elenchi, controlli), come già su tblFattureConti
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblBancheCasse') AND name = 'IX_BancheCasse_IdSede')
	CREATE NONCLUSTERED INDEX IX_BancheCasse_IdSede
	ON dbo.tblBancheCasse (IdSede);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblAliquoteIva') AND name = 'IX_AliquoteIva_IdSede')
	CREATE NONCLUSTERED INDEX IX_AliquoteIva_IdSede
	ON dbo.tblAliquoteIva (IdSede);
GO

-- Riepilogo: gli indici delle tabelle toccate
SELECT
	Tabella = t.name,
	Indice = i.name,
	Unico = i.is_unique,
	Filtro = ISNULL(i.filter_definition, ''),
	Chiave = STUFF((
		SELECT ', ' + c.name
		FROM
			sys.index_columns ic
			INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
		WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ic.key_ordinal
		FOR XML PATH('')), 1, 2, ''),
	Incluse = ISNULL(STUFF((
		SELECT ', ' + c.name
		FROM
			sys.index_columns ic
			INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
		WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ic.index_column_id
		FOR XML PATH('')), 1, 2, ''), '')
FROM
	sys.tables t
	INNER JOIN sys.indexes i ON t.object_id = i.object_id
WHERE
	i.is_primary_key = 0
	AND i.type > 0
	AND t.name IN ('tblClientiFornitori', 'tblFatture', 'tblFattureConti', 'tblFattureRate', 'tblFattureRatePagamenti', 'tblFattureRighe', 'tblPagamenti', 'tblBancheCasse', 'tblAliquoteIva', 'tblAmministratori', 'tblAmministratoriSedi')
ORDER BY t.name, i.name;
GO
GO

PRINT 'uspFatture_upd.sql';
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

		-- Le letture con blocco sono separate per tipo, con il filtro sulla colonna della data e non su
		-- un'espressione: per le fatture cliente il blocco copre solo l'anno dell'azienda nell'indice
		-- IX_Fatture_IdSede_Tipo_DataEmissione, per le fatture fornitore le fatture fornitore dell'azienda
		DECLARE @duplicato BIT = 0;

		BEGIN TRANSACTION;
			IF @numerata = 1 AND @Numero IS NULL
			BEGIN
				IF @tipo = 'C'
					SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Tipo = @tipo
						AND Lock = 0
						AND Id <> @Id
						AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
						AND DataEmissione >= @annoInizio
						AND DataEmissione < @annoFine;
				ELSE
					SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Tipo = @tipo
						AND Lock = 0
						AND Id <> @Id
						AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
						AND DataRegistrazione >= @annoInizio
						AND DataRegistrazione < @annoFine;
			END
			ELSE IF @numerata = 1
			BEGIN
				IF @tipo = 'C'
					SELECT @duplicato = 1
					FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Tipo = @tipo
						AND Lock = 0
						AND Id <> @Id
						AND Numero = @Numero
						AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
						AND DataEmissione >= @annoInizio
						AND DataEmissione < @annoFine;
				ELSE
					SELECT @duplicato = 1
					FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Tipo = @tipo
						AND Lock = 0
						AND Id <> @Id
						AND Numero = @Numero
						AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
						AND DataRegistrazione >= @annoInizio
						AND DataRegistrazione < @annoFine;
			END

			IF @duplicato = 1
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
GO

PRINT 'uspFatture_get_ProssimoNumero.sql';
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
			-- Due letture, una per tipo, con il filtro sulla colonna della data (come in uspFatture_upd)
			IF @tipo = 'C'
				SELECT @numero = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblFatture
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataEmissione >= @annoInizio
					AND DataEmissione < @annoFine;
			ELSE
				SELECT @numero = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblFatture
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataRegistrazione >= @annoInizio
					AND DataRegistrazione < @annoFine;
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
GO

PRINT 'uspFatture_upd_Xml.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registra la generazione dei file XML della fattura elettronica per le fatture indicate (@Ids: Id separati
-- da ;): assegna a ciascuna un progressivo dell'azienda (tblFattureDatiFiscali.ProgressivoInvio, 5 caratteri
-- in base 36: è quello del nome del file e del blocco DatiTrasmissione), segna la data della generazione e,
-- con @SolaLettura = 1, mette la fattura in sola lettura. Rigenerare il file assegna un nuovo progressivo.
-- Le fatture devono essere clienti, attive e numerate, dell'azienda interna corrente della sessione.
-- Restituisce Id e Progressivo di ogni fattura, in ordine di numero.
CREATE OR ALTER PROCEDURE dbo.uspFatture_upd_Xml
	@IdSessione CHAR(16) = NULL,
	@Ids VARCHAR(MAX) = NULL,
	@SolaLettura BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Ids = NULLIF(LTRIM(RTRIM(@Ids)), '');
		SET @SolaLettura = ISNULL(@SolaLettura, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Ids IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessuna fattura indicata';
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

		DECLARE @richieste TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		INSERT @richieste (Id)
		SELECT DISTINCT LTRIM(RTRIM(v.value))
		FROM STRING_SPLIT(@Ids, ';') v
		WHERE LTRIM(RTRIM(v.value)) <> '';

		DECLARE @fatture TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, Pos INT NOT NULL, Progressivo INT NULL);
		INSERT @fatture (Id, Pos)
		SELECT
			f.Id,
			ROW_NUMBER() OVER (ORDER BY f.DataEmissione, f.Numero, f.Sezionale, f.Id)
		FROM
			@richieste q
			INNER JOIN dbo.tblFatture f ON q.Id = f.Id
		WHERE
			f.IdSede = @idAzienda
			AND f.Tipo = 'C'
			AND f.Lock = 0
			AND f.Numero IS NOT NULL;

		IF (SELECT COUNT(*) FROM @fatture) = 0 OR (SELECT COUNT(*) FROM @fatture) <> (SELECT COUNT(*) FROM @richieste)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o una delle fatture non esiste o non è numerata';
			GOTO BRANCH_END;
		END
		IF (SELECT COUNT(*) FROM @fatture) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si possono generare al massimo 100 fatture alla volta';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureDatiFiscali WHERE Id = @idAzienda)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Completare i dati fiscali dell''azienda (Fatturazione > Dati fiscali)';
			GOTO BRANCH_END;
		END

		DECLARE @cifre CHAR(36) = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
		DECLARE @numero INT = (SELECT COUNT(*) FROM @fatture);
		DECLARE @ultimo INT;

		BEGIN TRANSACTION;
			-- Progressivi dell'azienda riservati con il blocco sulla riga dei dati fiscali: l'UPDATE la
			-- blocca in modo esclusivo fino al COMMIT, senza bisogno di hint
			UPDATE dbo.tblFattureDatiFiscali
			SET
				@ultimo = ISNULL(ProgressivoInvio, 0),
				ProgressivoInvio = ISNULL(ProgressivoInvio, 0) + @numero
			WHERE Id = @idAzienda;

			-- 5 caratteri in base 36: 60.466.175 file per azienda
			IF @ultimo + @numero > 60466175
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Progressivi dei file esauriti per questa azienda';
				GOTO BRANCH_END;
			END

			UPDATE @fatture
			SET Progressivo = @ultimo + Pos;

			UPDATE f
			SET
				DataXml = GETDATE(),
				ProgressivoXml =
					SUBSTRING(@cifre, (t.Progressivo / 1679616) % 36 + 1, 1)
					+ SUBSTRING(@cifre, (t.Progressivo / 46656) % 36 + 1, 1)
					+ SUBSTRING(@cifre, (t.Progressivo / 1296) % 36 + 1, 1)
					+ SUBSTRING(@cifre, (t.Progressivo / 36) % 36 + 1, 1)
					+ SUBSTRING(@cifre, t.Progressivo % 36 + 1, 1),
				SolaLettura = IIF(@SolaLettura = 1, 1, f.SolaLettura)
			FROM
				dbo.tblFatture f
				INNER JOIN @fatture t ON f.Id = t.Id;
		COMMIT TRANSACTION;

		SELECT
			f.Id,
			Progressivo = f.ProgressivoXml
		FROM
			dbo.tblFatture f
			INNER JOIN @fatture t ON f.Id = t.Id
		ORDER BY t.Pos;

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
GO

PRINT 'uspBancheCasse_del.sql';
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
		DECLARE @idAzienda CHAR(16) = (SELECT IdSede FROM dbo.tblBancheCasse WHERE Id = @Id);

		-- ── CASO 1: banca o cassa attiva (Lock = 0) → soft delete ────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdBancaCassa = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una banca o cassa associata a clienti o fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdBancaCassa = @Id AND Lock IN (0, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una banca o cassa indicata in una fattura non può essere cancellata';
				GOTO BRANCH_END;
			END
			-- IdSede (l'azienda della banca, la stessa dei suoi pagamenti) permette la ricerca nell'indice dei pagamenti
			IF EXISTS (SELECT 1 FROM dbo.tblPagamenti WHERE IdSede = @idAzienda AND IdBancaCassa = @Id AND Lock = 0)
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
GO

PRINT 'uspFattureConti_del.sql';
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
		DECLARE @idAzienda CHAR(16) = (SELECT IdSede FROM dbo.tblFattureConti WHERE Id = @Id);

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
			-- Lo stesso per un conto indicato in un movimento manuale attivo della prima nota. IdSede (l'azienda
			-- del conto, la stessa dei suoi movimenti) permette la ricerca nell'indice dei pagamenti
			IF EXISTS (SELECT 1 FROM dbo.tblPagamenti WHERE IdSede = @idAzienda AND IdConto = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato in un movimento della prima nota non può essere cancellato';
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
GO

PRINT 'uspFatture_get_List.sql';
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
		-- dal netto a pagare (una fattura senza rate non è segnalata).
		-- Prima si filtra e si prende la pagina, con le sole colonne di filtro e ordinamento (quelle
		-- dell'indice delle fatture); poi, solo per le fatture della pagina, si leggono le altre colonne
		-- e si calcolano totali e rate
		;WITH pagina AS (
			SELECT
				f.Id,
				f.Numero,
				f.DataEmissione,
				s.NomeCompleto,
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblFatture f
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
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
		)
		SELECT
			g.Id,
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
			g.NomeCompleto,
			t.Imponibile,
			t.Iva,
			t.Totale,
			t.NettoAPagare,
			SolaLettura = ISNULL(f.SolaLettura, 0),
			g.RowsCount
		FROM
			pagina g
			INNER JOIN dbo.tblFatture f ON g.Id = f.Id
			LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
			LEFT JOIN dbo.tblFattureStati a ON f.IdStato = a.Id
			OUTER APPLY dbo.ufnFatture_get_Totali(g.Id) t
			OUTER APPLY (SELECT Numero = COUNT(*), Importo = ISNULL(SUM(q.Importo), 0) FROM dbo.tblFattureRate q WHERE q.IdFattura = g.Id) z
		ORDER BY
			g.DataEmissione DESC,
			g.Numero DESC,
			g.Id
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

PRINT 'uspFattureRate_get_Scadenzario_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scadenziario: le rate delle fatture attive dei clienti (@Tipo = C) o dei fornitori (@Tipo = F) dell'azienda
-- del contesto, dalla scadenza più vecchia. Le pre-fatture (TD00) non entrano. @Stato: A aperte (da pagare
-- e scadute, predefinito), S scadute, D da pagare non scadute, P saldate, T tutte.
-- Residuo = importo - abbuono - pagato. La rata di una nota di credito (NotaCredito = 1) è un importo da
-- restituire.
-- SolaLettura = fattura in sola lettura: la rata non si modifica, i pagamenti si registrano comunque.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_Scadenzario_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@Stato CHAR(1) = NULL
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
		SET @Stato = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@Stato)), '')), 'A');

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
		IF @Stato NOT IN ('A', 'S', 'D', 'P', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Stato deve essere A, S, D, P o T';
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
		-- Pagato = quote dei pagamenti attivi attribuite alla rata.
		-- Il residuo serve al filtro per stato, quindi va calcolato per tutte le rate dell'azienda: lo si fa
		-- con le sole colonne che servono a filtro e ordinamento (quelle degli indici delle fatture e delle
		-- rate); il resto della riga (tipo, modalità, banca) si legge solo per le rate della pagina
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		WITH rate AS (
			SELECT
				r.Id,
				r.IdFattura,
				r.DataScadenza,
				Importo = ISNULL(r.Importo, 0),
				Abbuono = ISNULL(r.Abbuono, 0),
				x.Pagato,
				Residuo = IIF(ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato > 0, ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato, 0),
				f.Numero,
				s.NomeCompleto
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				CROSS APPLY
					(
						SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
						FROM
							dbo.tblFattureRatePagamenti rp
							INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
						WHERE
							rp.IdRata = r.Id
							AND g.Lock = 0
					) x
			WHERE
				e.Id = @IdSessione
				AND f.Tipo = @Tipo
				AND f.Lock = 0
				AND ISNULL(f.IdTipo, '') <> 'TD00'
				AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
				AND
					(
					@Numero IS NULL
					OR CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '') LIKE @Numero + '%'
					OR f.NumeroFornitore LIKE '%' + @Numero + '%'
					)
				AND (@DataDa IS NULL OR r.DataScadenza >= @DataDa)
				AND (@DataA IS NULL OR r.DataScadenza <= @DataA)
		),
		pagina AS (
			SELECT
				t.Id,
				t.IdFattura,
				t.DataScadenza,
				t.Importo,
				t.Abbuono,
				t.Pagato,
				t.Residuo,
				t.Numero,
				t.NomeCompleto,
				RowsCount = COUNT(*) OVER ()
			FROM rate t
			WHERE
				@Stato = 'T'
				OR (@Stato = 'A' AND t.Residuo > 0)
				OR (@Stato = 'S' AND t.Residuo > 0 AND t.DataScadenza < @oggi)
				OR (@Stato = 'D' AND t.Residuo > 0 AND t.DataScadenza >= @oggi)
				OR (@Stato = 'P' AND t.Residuo = 0)
			ORDER BY
				t.DataScadenza,
				t.NomeCompleto,
				t.Numero,
				t.Id
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
		)
		SELECT
			t.Id,
			t.IdFattura,
			StatoValore = CASE
				WHEN t.Residuo = 0 THEN 0
				WHEN t.DataScadenza < @oggi THEN 2
				ELSE 1
			END,
			StatoDescrizione = CASE
				WHEN t.Residuo = 0 THEN 'Saldata'
				WHEN t.DataScadenza < @oggi THEN 'Scaduta'
				ELSE 'Da pagare'
			END,
			t.DataScadenza,
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataEmissione,
			f.IdTipo,
			TipoNome = p.Nome,
			f.IdModalita,
			f.IdBancaCassa,
			t.NomeCompleto,
			NotaCredito = CAST(IIF(f.IdTipo = 'TD04', 1, 0) AS BIT),
			SolaLettura = ISNULL(f.SolaLettura, 0),
			Importo = CAST(t.Importo AS DECIMAL(18, 2)),
			Abbuono = CAST(t.Abbuono AS DECIMAL(18, 2)),
			Pagato = CAST(t.Pagato AS DECIMAL(18, 2)),
			Residuo = CAST(t.Residuo AS DECIMAL(18, 2)),
			t.RowsCount
		FROM
			pagina t
			INNER JOIN dbo.tblFatture f ON t.IdFattura = f.Id
			LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
		ORDER BY
			t.DataScadenza,
			t.NomeCompleto,
			t.Numero,
			t.Id
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

