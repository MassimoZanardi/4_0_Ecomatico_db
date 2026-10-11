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
