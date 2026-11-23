/*
	Deploy produzione - 2026-11-23 - Servizi: durata, Impegni (Giorno per risorsa, Settimana, Mese, Elenco, Cerca,
	risorse a pagine), calendari a blocchi di Servizi e Scadenze con lo spostamento trascinando, voci di menu;
	Fatture e scadenziario clienti: ricerca per amministratore

	Solo 4_0_ecomatico (DB comune a 40-demo e produzione). Tutto quello che e' stato committato nel repo DB dopo il tag
	deployed-prod (commit da 57e1545 a e3f2c3a). Una colonna e un vincolo (creati solo se mancano), un indice (creato
	solo se manca), due voci di menu (inserite o aggiornate solo se serve), funzioni e stored procedure tutte
	CREATE OR ALTER: lo script e' rieseguibile. Nessun dato dei clienti modificato. Da eseguire da SSMS sul database
	4_0_ecomatico (o con sqlcmd -f 65001 -I).

	Prima il DB, poi l'app (commit 4.0 5da8cda o successivo): le SP nuove o con parametri in piu' non disturbano
	l'app attuale (parametri facoltativi), ma le voci di menu Servizi > Calendario e Servizi > Impegni puntano alle
	pagine nuove, quindi l'app va pubblicata subito dopo.

	1. tblServizi.Durata (minuti, facoltativa) con il vincolo CK_tblServizi_Durata (1-1440).
	2. Indice IX_RicorrenzeEccezioni_IdEvento (elenchi di Servizi e Scadenze con le serie).
	3. Menu: Servizi > Calendario con la funzione dei Servizi (pagina SRV invece di CAL).
	4. Menu: Servizi > Impegni (pagina SRI, voce AE6 sotto Calendario).
	5. Funzioni: ufnServizi_get_Orario (nuova), ufnEventi_get_List.
	6. Stored procedure di Servizi, Servizi assegnati, Scadenze, Fatture e scadenziario (elenco in fondo alla verifica).

	In fondo la verifica: colonna, vincolo, indice, menu, funzioni e procedure con data di modifica e QUOTED_IDENTIFIER.
*/

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

-- ===== 1. servizi_durata_colonna (tools/servizi_durata_colonna.sql)
-- Servizi: durata del servizio in minuti (tblServizi.Durata), facoltativa. NULL = durata non indicata: il servizio
-- occupa la sola cella dell'ora di inizio, come prima del 2026-11-21. Il servizio termina entro la mezzanotte del
-- giorno di inizio (controllo in uspServizi_upd e uspServiziAssegnati_upd), quindi la durata non supera le 24 ore.
-- Da installare prima delle SP uspServizi_* che leggono o scrivono la colonna. Si può rilanciare.

IF COL_LENGTH('dbo.tblServizi', 'Durata') IS NULL
	ALTER TABLE dbo.tblServizi ADD Durata INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_tblServizi_Durata')
	ALTER TABLE dbo.tblServizi WITH CHECK ADD CONSTRAINT CK_tblServizi_Durata CHECK (Durata > 0 AND Durata <= 1440);
GO
GO

-- ===== 2. ricorrenze_eccezioni_indice_idevento (tools/ricorrenze_eccezioni_indice_idevento.sql)
-- Indice sull'occorrenza modificata (tblRicorrenzeEccezioni.IdEvento, il sostituto dell'eccezione): lo cercano per ogni
-- riga gli elenchi di Servizi e Scadenze (serie dell'occorrenza modificata, "Tutta la serie") e uspEventi_get_Ricorrenza.
-- Prova del 2026-11-21 con 15.000 servizi e 300 serie: Elenco di un anno da 13,6 s a 3,1 s, di un mese da 1,8 s a 0,8 s
-- (poi la paginazione sulle chiavi in uspServizi_get_List). Si può rilanciare.

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RicorrenzeEccezioni_IdEvento' AND object_id = OBJECT_ID('dbo.tblRicorrenzeEccezioni'))
	CREATE NONCLUSTERED INDEX IX_RicorrenzeEccezioni_IdEvento ON dbo.tblRicorrenzeEccezioni (IdEvento) INCLUDE (Lock);
GO
GO

-- ===== 3. servizi_calendario_menu_funzione (tools/servizi_calendario_menu_funzione.sql)
SET NOCOUNT ON;

-- Servizi > Calendario: la voce di menu (tblMenu AE1) usava la pagina CAL, la stessa di Scadenze > Calendario, con la
-- funzione SCD: la vedeva chi ha le Scadenze, non chi ha i Servizi. Ora usa la pagina SRV (funzione SRV, gia'
-- presente senza Url), con lo stesso indirizzo 'calendario/settimana'. Scadenze > Calendario (AD1) resta su CAL.
-- Rieseguibile. Eseguito su dev il 2026-11-20. NON ancora eseguito in produzione.

UPDATE dbo.tblPagine
SET [Url] = 'calendario/settimana'
WHERE
	Id = 'SRV'
	AND IdFunzione = 'SRV'
	AND [Url] IS NULL;

UPDATE dbo.tblMenu
SET IdPagina = 'SRV'
WHERE
	Id = 'AE1'
	AND IdParent = 'AE0'
	AND IdPagina = 'CAL'
	AND EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'SRV' AND IdFunzione = 'SRV' AND [Url] = 'calendario/settimana');

SELECT m.Id, m.IdParent, m.Pos, p.Id AS IdPagina, p.Nome, p.[Url], p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.Id IN ('AD1', 'AE1');
GO
GO

-- ===== 4. servizi_impegni_menu (tools/servizi_impegni_menu.sql)
SET NOCOUNT ON;

-- Servizi > Impegni: voce di menu sotto "Calendario" (funzione SRV, nessuna funzione nuova).
-- Pagina /servizi/impegni/{giorno|settimana|mese}: la voce apre la vista settimanale (Url 'impegni/settimana',
-- come 'calendario/settimana' del Calendario). Rieseguibile.
-- Eseguito su dev il 2026-11-20. NON ancora eseguito in produzione.

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'SRI')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('SRI', 'SRV', 'Impegni', 'impegni/settimana', NULL);

-- Posizione: subito dopo Calendario (AE1, Pos 0); le voci successive scendono di uno
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AE6')
BEGIN
	UPDATE dbo.tblMenu SET Pos = Pos + 1 WHERE IdParent = 'AE0' AND Pos >= 1;
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AE6', 'AE0', NULL, 'SRI', 1);
END

SELECT m.Id, m.Pos, p.Nome, p.Url, p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent = 'AE0'
ORDER BY m.Pos;
GO
GO

-- ===== 5. ufnServizi_get_Orario (sql/functions/ufnServizi_get_Orario.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnServizi_get_Orario]
(
	@Data SMALLDATETIME,
	@InGiornata BIT,
	@Durata INT
)
RETURNS VARCHAR(30)
WITH SCHEMABINDING
AS
BEGIN
	/*
	*   Orario del servizio per i testi di calendario, Impegni, elenco e stampa:
	*   - con l'ora e la durata          "09:00-11:30" (fine alla mezzanotte = "24:00")
	*   - con l'ora, senza durata        "09:00"
	*   - in giornata, con la durata     "In giornata (4:00)"
	*   - in giornata, senza durata      "In giornata"
	*/
	DECLARE @durataTesto VARCHAR(10) = IIF(@Durata IS NULL, NULL,
		CAST(@Durata / 60 AS VARCHAR(5)) + ':' + RIGHT('0' + CAST(@Durata % 60 AS VARCHAR(2)), 2));

	IF ISNULL(@InGiornata, 0) = 1
		RETURN 'In giornata' + ISNULL(' (' + @durataTesto + ')', '');

	DECLARE @fine DATETIME = DATEADD(MINUTE, @Durata, CAST(@Data AS DATETIME));

	RETURN CONVERT(VARCHAR(5), @Data, 108)
		+ ISNULL('-' + IIF(CAST(@fine AS DATE) > CAST(@Data AS DATE), '24:00', CONVERT(VARCHAR(5), @fine, 108)), '');
END;
GO
GO

-- ===== 6. ufnEventi_get_List (sql/functions/ufnEventi_get_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_List] (
	@DallaData SMALLDATETIME,
	@AllaData SMALLDATETIME,
	@IdCalendario tvpId_char_16 READONLY,
	@IdTipo tvpId_char_1 READONLY)
RETURNS TABLE
-- WITH SCHEMABINDING non applicabile: dipende da TVP (tvpId_char_16, tvpId_char_1)
-- che non sono oggetti schema-bound
AS
RETURN
(
	WITH cteEventi AS (
		SELECT
			e.Id,
			e.IdTipo,
			e.IdCalendario,
			c.IdSede,
			s.IdAziendaInterna,
			e.IdStato,
			Stato = t.Nome,
			e.[Data],
			e.InGiornata,
			-- Ricorre: true se esiste una riga in tblRicorrenze
			Ricorre = CAST(IIF(r.Id IS NULL, 0, 1) AS BIT),
			e.AvvisoAnticipo,
			-- Avviso: true se e' stato impostato un anticipo
			Avviso = CAST(IIF(e.AvvisoAnticipo IS NULL, 0, 1) AS BIT),
			AvvisoTesto = e.Avviso,
			e.Etichette,
			e.Email,
			r.IdIntervallo,
			r.Frequenza,
			r.DataFine,
			r.Ripetizioni,
			r.Relativo,
			-- Eccezione: true se l'evento ricorrente ha almeno un'eccezione attiva
			Eccezione = CAST(IIF(z.Id IS NULL, 0, 1) AS BIT),
			IdEventoEccezione = z.IdEvento,
			IdEccezione = z.Id,
			e.Lock,
			-- NumberMax: numero massimo di occorrenze da generare con GENERATE_SERIES.
			-- FIX: limitato al minimo tra il valore "originale" (DataFine/
			-- Ripetizioni) e il numero di occorrenze sufficienti a coprire
			-- @AllaData, cosi' GENERATE_SERIES non genera oltre il necessario
			-- per la finestra richiesta da QUESTA query. Un solo DATEDIFF
			-- (parametrizzato per unita' tramite il CASE, che e' l'unica
			-- parte che deve necessariamente variare per intervallo, dato
			-- che DATEDIFF non accetta l'unita' come variabile in T-SQL),
			-- poi si deriva sia il valore originale sia quello di finestra.
			NumberMax = IIF(r.Id IS NULL, 0,
				IIF(nm.NumberMaxOriginale <= nm.NumberMaxFinestra,
					nm.NumberMaxOriginale,
					nm.NumberMaxFinestra))
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblEventiStati t ON e.IdStato = t.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			-- Ricorrenza: NULL per eventi singoli
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			-- Eccezione: cerca le eccezioni dell'evento originale (z.Id = evento originale).
			-- FIX: OUTER APPLY con TOP (1) invece di LEFT JOIN, perche' una serie con piu'
			-- eccezioni attive restituiva ogni sua occorrenza una volta per eccezione
			-- (doppioni nei calendari, negli elenchi e nei conteggi); serve solo sapere
			-- se la serie ha eccezioni, le date escluse sono filtrate in fondo (x)
			OUTER APPLY (
				SELECT TOP (1)
					z1.Id,
					z1.IdEvento
				FROM dbo.tblRicorrenzeEccezioni z1
				WHERE
					z1.Id = e.Id
					AND z1.Lock = 0
				ORDER BY z1.[Data]
			) z
			-- FIX NumberMax: calcola una sola volta il DATEDIFF nell'unita'
			-- corretta, poi deriva da esso sia il NumberMax originale sia
			-- quello di finestra
			OUTER APPLY (
				SELECT Diff = CASE r.IdIntervallo
					WHEN 'DD' THEN DATEDIFF(DAY, e.[Data], @AllaData)
					WHEN 'WK' THEN DATEDIFF(WEEK, e.[Data], @AllaData)
					WHEN 'MM' THEN DATEDIFF(MONTH, e.[Data], @AllaData)
					WHEN 'YY' THEN DATEDIFF(YEAR, e.[Data], @AllaData)
					ELSE 0
				END
			) d
			OUTER APPLY (
				SELECT
					NumberMaxOriginale = IIF(r.Id IS NULL, 0,
						dbo.ufnEventi_get_NumberMax(e.[Data], r.DataFine, r.IdIntervallo, r.Frequenza, r.Ripetizioni)),
					NumberMaxFinestra = IIF(r.Id IS NULL OR r.Frequenza IS NULL OR r.Frequenza <= 0, 0,
						d.Diff / r.Frequenza)
			) nm
		WHERE
			e.IdCalendario IN (SELECT Id FROM @IdCalendario)
			AND e.IdTipo IN (SELECT Id FROM @IdTipo)
			AND
				(
				r.DataFine IS NULL
				OR r.DataFine >= @DallaData
				)
			AND e.Lock = 0
	)
	SELECT
		t.*,
		AvvisoData = DATEADD(MINUTE, t.AvvisoAnticipo * -1, t.[Data])
	FROM (
		-- Ramo 1: eventi non ricorrenti
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			e.[Data], e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		WHERE e.Ricorre = 0
		UNION ALL -- rami mutualmente esclusivi per Ricorre + IdIntervallo + Relativo

		-- Ramo 2: ricorrenti ogni N giorni
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(DAY, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'DD'
		UNION ALL

		-- Ramo 3: ricorrenti ogni N settimane
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(WEEK, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'WK'
		UNION ALL

		-- Ramo 4: ricorrenti ogni N mesi (giorno fisso)
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(MONTH, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'MM'
			AND e.Relativo = 0
		UNION ALL

		-- Ramo 5: ricorrenti ogni N mesi (giorno relativo es. "terzo lunedì del mese")
		SELECT
			t.Id, t.IdCalendario, t.IdStato, t.Stato, t.IdTipo,
			t.[Data], t.InGiornata, t.Avviso, t.AvvisoTesto, t.AvvisoAnticipo,
			t.Etichette, t.Ricorre, t.Eccezione, t.IdEccezione
		FROM (
			SELECT
				e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
				[Data] = dbo.ufnDate_get_GiornoDelMeseRelativo(
							 e.[Data],
							 DATEADD(MONTH, n.Number * e.Frequenza, e.[Data]),
							 e.Relativo),
				e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
				e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione,
				e.DataFine
			FROM cteEventi e
			CROSS APPLY (SELECT Number = [value]
				 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
			WHERE
				e.Ricorre = 1
				AND e.IdIntervallo = 'MM'
				AND e.Relativo > 0
		) t
		WHERE t.[Data] < t.DataFine
		UNION ALL

		-- Ramo 6: ricorrenti ogni N anni
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(YEAR, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'YY'
	) t
	-- Esclude le date per cui esiste un'eccezione di ricorrenza attiva
		LEFT JOIN dbo.tblRicorrenzeEccezioni x
		ON t.Id = x.Id
		AND t.[Data] = x.[Data]
		AND x.Lock = 0
	WHERE
		x.Id IS NULL
		AND t.[Data] BETWEEN @DallaData AND @AllaData
);
GO

-- ===== 7. uspFatture_get_Esportazione (sql/procedures/uspFatture_get_Esportazione.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture clienti (@Tipo = C) e fornitori (@Tipo = F): righe per l'esportazione dell'elenco in Excel e in CSV
-- (Azioni > Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file:
-- l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per
-- cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse fatture e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspFatture_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Pagato = quote dei pagamenti attivi sulle rate della fattura; Residuo = quanto resta da pagare delle rate
-- (vuoto se la fattura non ha rate). Avviso = lo stato di avviso dell'elenco.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@Amministratore VARCHAR(50) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdStato CHAR(1) = NULL,
	@MaxRighe INT = NULL
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
		SET @Amministratore = dbo.ufnStringhe_get_SenzaSpazi(@Amministratore, 0, 1);
		SET @IdTipo = NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4));
		SET @IdStato = NULLIF(NULLIF(LTRIM(RTRIM(@IdStato)), ''), '0');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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

		-- Fatture della ricerca, nell'ordine dell'elenco (stesso WHERE e stesso ORDER BY di uspFatture_get_List)
		DECLARE @fatture TABLE (
			Pos INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT @fatture (Id)
		SELECT TOP (@MaxRighe + 1) f.Id
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
			-- Amministratore (fatture clienti): solo i clienti amministrati da un amministratore attivo dell'azienda
			-- della fattura il cui nome contiene il testo, senza guardare le date dell'incarico (come Anagrafica > Soggetti)
			AND
				(
				@Amministratore IS NULL
				OR EXISTS (
					SELECT 1
					FROM
						dbo.tblAmministratoriSedi ax
						INNER JOIN dbo.tblAmministratori am ON ax.Id = am.Id
						INNER JOIN dbo.tblSedi ams ON am.IdSede = ams.Id
					WHERE
						ax.IdSede = c.IdSede
						AND am.IdAziendaInterna = f.IdSede
						AND am.Lock = 0
						AND ams.NomeCompleto LIKE '%' + @Amministratore + '%'
					)
				)
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
		OPTION (RECOMPILE);

		IF @Tipo = 'C'
			SELECT
				[Numero] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Data] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Stato] = a.Nome,
				[Cliente] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Imponibile] = t.Imponibile,
				[IVA] = t.Iva,
				[Ritenuta] = t.Ritenuta,
				[Totale] = t.Totale,
				[Netto a pagare] = t.NettoAPagare,
				[Incassato] = z.Pagato,
				[Residuo] = z.Residuo,
				[Pagamento tramite] = m.Nome,
				[Banca o cassa] = b.Nome,
				[Bollo] = NULLIF(f.Bollo, 0),
				[Split payment] = ISNULL(f.SplitPayment, 0),
				[Causale] = f.Causale,
				[Ordine] = f.Ordine,
				[Data ordine] = f.DataOrdine,
				[CIG] = f.CodiceCig,
				[CUP] = f.CodiceCup,
				[Fattura di riferimento] = CAST(rf.Numero AS VARCHAR(12)) + ISNULL('/' + rf.Sezionale, ''),
				[Sola lettura] = ISNULL(f.SolaLettura, 0),
				[File XML generato il] = f.DataXml,
				[Avviso] =
					CASE
						WHEN t.Totale = 0 THEN 'Fattura senza importi'
						WHEN z.Numero > 0 AND z.Importo <> t.NettoAPagare THEN 'Le rate non corrispondono al netto a pagare'
					END
			FROM
				@fatture x
				INNER JOIN dbo.tblFatture f ON x.Id = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblFattureStati a ON f.IdStato = a.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
				OUTER APPLY
					(
						SELECT
							Numero = COUNT(*),
							Importo = ISNULL(SUM(q.Importo), 0),
							Pagato = CAST(NULLIF(SUM(g.Pagato), 0) AS DECIMAL(18, 2)),
							Residuo = CAST(SUM(IIF(ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato > 0, ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato, 0)) AS DECIMAL(18, 2))
						FROM
							dbo.tblFattureRate q
							CROSS APPLY
								(
									SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
									FROM
										dbo.tblFattureRatePagamenti rp
										INNER JOIN dbo.tblPagamenti k ON rp.IdPagamento = k.Id
									WHERE
										rp.IdRata = q.Id
										AND k.Lock = 0
								) g
						WHERE q.IdFattura = f.Id
					) z
			ORDER BY x.Pos;
		ELSE
			SELECT
				[Protocollo] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Data registrazione] = f.DataRegistrazione,
				[Numero fornitore] = f.NumeroFornitore,
				[Data fattura] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Fornitore] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Imponibile] = t.Imponibile,
				[IVA] = t.Iva,
				[Ritenuta] = t.Ritenuta,
				[Totale] = t.Totale,
				[Netto a pagare] = t.NettoAPagare,
				[Pagato] = z.Pagato,
				[Residuo] = z.Residuo,
				[Pagamento tramite] = m.Nome,
				[IBAN del fornitore] = f.Iban,
				[Banca o cassa] = b.Nome,
				[Bollo] = NULLIF(f.Bollo, 0),
				[Split payment] = ISNULL(f.SplitPayment, 0),
				[Causale] = f.Causale,
				[Ordine] = f.Ordine,
				[Data ordine] = f.DataOrdine,
				[CIG] = f.CodiceCig,
				[CUP] = f.CodiceCup,
				[Fattura di riferimento] = ISNULL(NULLIF(rf.NumeroFornitore, ''), CAST(rf.Numero AS VARCHAR(12)) + ISNULL('/' + rf.Sezionale, '')),
				[Sola lettura] = ISNULL(f.SolaLettura, 0),
				[Caricata da file XML il] = f.DataXml,
				[Avviso] =
					CASE
						WHEN t.Totale = 0 THEN 'Fattura senza importi'
						WHEN z.Numero > 0 AND z.Importo <> t.NettoAPagare THEN 'Le rate non corrispondono al netto a pagare'
					END
			FROM
				@fatture x
				INNER JOIN dbo.tblFatture f ON x.Id = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
				OUTER APPLY
					(
						SELECT
							Numero = COUNT(*),
							Importo = ISNULL(SUM(q.Importo), 0),
							Pagato = CAST(NULLIF(SUM(g.Pagato), 0) AS DECIMAL(18, 2)),
							Residuo = CAST(SUM(IIF(ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato > 0, ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato, 0)) AS DECIMAL(18, 2))
						FROM
							dbo.tblFattureRate q
							CROSS APPLY
								(
									SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
									FROM
										dbo.tblFattureRatePagamenti rp
										INNER JOIN dbo.tblPagamenti k ON rp.IdPagamento = k.Id
									WHERE
										rp.IdRata = q.Id
										AND k.Lock = 0
								) g
						WHERE q.IdFattura = f.Id
					) z
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

-- ===== 8. uspFatture_get_List (sql/procedures/uspFatture_get_List.sql)
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
	@Amministratore VARCHAR(50) = NULL,
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
		SET @Amministratore = dbo.ufnStringhe_get_SenzaSpazi(@Amministratore, 0, 1);
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
				-- Amministratore (fatture clienti): solo i clienti amministrati da un amministratore attivo dell'azienda
				-- della fattura il cui nome contiene il testo, senza guardare le date dell'incarico (come Anagrafica > Soggetti)
				AND
					(
					@Amministratore IS NULL
					OR EXISTS (
						SELECT 1
						FROM
							dbo.tblAmministratoriSedi ax
							INNER JOIN dbo.tblAmministratori am ON ax.Id = am.Id
							INNER JOIN dbo.tblSedi ams ON am.IdSede = ams.Id
						WHERE
							ax.IdSede = c.IdSede
							AND am.IdAziendaInterna = f.IdSede
							AND am.Lock = 0
							AND ams.NomeCompleto LIKE '%' + @Amministratore + '%'
						)
					)
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

-- ===== 9. uspFattureRate_get_Scadenzario_Esportazione (sql/procedures/uspFattureRate_get_Scadenzario_Esportazione.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scadenziario clienti (@Tipo = C) e fornitori (@Tipo = F): righe per l'esportazione dell'elenco in Excel e in
-- CSV (Azioni > Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel
-- file: l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per
-- cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse rate e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspFattureRate_get_Scadenzario_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al
-- massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Come nell'elenco, gli importi della rata di una nota di credito hanno il segno meno (importo da restituire).
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_Scadenzario_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@Amministratore VARCHAR(50) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@Stato CHAR(1) = NULL,
	@MaxRighe INT = NULL
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
		SET @Amministratore = dbo.ufnStringhe_get_SenzaSpazi(@Amministratore, 0, 1);
		SET @Stato = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@Stato)), '')), 'A');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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

		-- Rate della ricerca, nell'ordine dell'elenco (stessi criteri e stesso ORDER BY di
		-- uspFattureRate_get_Scadenzario_List), con pagato, residuo e stato già calcolati
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);
		DECLARE @rate TABLE (
			Pos INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			Pagato DECIMAL(18, 2) NOT NULL,
			Residuo DECIMAL(18, 2) NOT NULL
		);

		WITH rate AS (
			SELECT
				r.Id,
				r.DataScadenza,
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
				-- Amministratore (fatture clienti): solo i clienti amministrati da un amministratore attivo dell'azienda
				-- della fattura il cui nome contiene il testo, senza guardare le date dell'incarico (come Anagrafica > Soggetti)
				AND
					(
					@Amministratore IS NULL
					OR EXISTS (
						SELECT 1
						FROM
							dbo.tblAmministratoriSedi ax
							INNER JOIN dbo.tblAmministratori am ON ax.Id = am.Id
							INNER JOIN dbo.tblSedi ams ON am.IdSede = ams.Id
						WHERE
							ax.IdSede = c.IdSede
							AND am.IdAziendaInterna = f.IdSede
							AND am.Lock = 0
							AND ams.NomeCompleto LIKE '%' + @Amministratore + '%'
						)
					)
				AND
					(
					@Numero IS NULL
					OR CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '') LIKE @Numero + '%'
					OR f.NumeroFornitore LIKE '%' + @Numero + '%'
					)
				AND (@DataDa IS NULL OR r.DataScadenza >= @DataDa)
				AND (@DataA IS NULL OR r.DataScadenza <= @DataA)
		)
		INSERT @rate (Id, Pagato, Residuo)
		SELECT TOP (@MaxRighe + 1)
			t.Id,
			t.Pagato,
			t.Residuo
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
		OPTION (RECOMPILE);

		IF @Tipo = 'C'
			SELECT
				[Scadenza] = r.DataScadenza,
				[Stato] = CASE WHEN x.Residuo = 0 THEN 'Saldata' WHEN r.DataScadenza < @oggi THEN 'Scaduta' ELSE 'Da pagare' END,
				[Importo] = CAST(g.Segno * ISNULL(r.Importo, 0) AS DECIMAL(18, 2)),
				[Abbuono] = CAST(g.Segno * NULLIF(r.Abbuono, 0) AS DECIMAL(18, 2)),
				[Incassato] = CAST(g.Segno * NULLIF(x.Pagato, 0) AS DECIMAL(18, 2)),
				[Residuo] = CAST(g.Segno * x.Residuo AS DECIMAL(18, 2)),
				[Fattura] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Data fattura] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Cliente] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Pagamento tramite] = m.Nome,
				[Banca o cassa] = b.Nome
			FROM
				@rate x
				INNER JOIN dbo.tblFattureRate r ON x.Id = r.Id
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				CROSS APPLY (SELECT Segno = IIF(f.IdTipo = 'TD04', -1, 1)) g
			ORDER BY x.Pos;
		ELSE
			SELECT
				[Scadenza] = r.DataScadenza,
				[Stato] = CASE WHEN x.Residuo = 0 THEN 'Saldata' WHEN r.DataScadenza < @oggi THEN 'Scaduta' ELSE 'Da pagare' END,
				[Importo] = CAST(g.Segno * ISNULL(r.Importo, 0) AS DECIMAL(18, 2)),
				[Abbuono] = CAST(g.Segno * NULLIF(r.Abbuono, 0) AS DECIMAL(18, 2)),
				[Pagato] = CAST(g.Segno * NULLIF(x.Pagato, 0) AS DECIMAL(18, 2)),
				[Residuo] = CAST(g.Segno * x.Residuo AS DECIMAL(18, 2)),
				[Protocollo] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Numero fornitore] = f.NumeroFornitore,
				[Data fattura] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Fornitore] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Pagamento tramite] = m.Nome,
				[IBAN del fornitore] = f.Iban,
				[Banca o cassa] = b.Nome
			FROM
				@rate x
				INNER JOIN dbo.tblFattureRate r ON x.Id = r.Id
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				CROSS APPLY (SELECT Segno = IIF(f.IdTipo = 'TD04', -1, 1)) g
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

-- ===== 10. uspFattureRate_get_Scadenzario_List (sql/procedures/uspFattureRate_get_Scadenzario_List.sql)
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
	@Amministratore VARCHAR(50) = NULL,
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
		SET @Amministratore = dbo.ufnStringhe_get_SenzaSpazi(@Amministratore, 0, 1);
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
				-- Amministratore (fatture clienti): solo i clienti amministrati da un amministratore attivo dell'azienda
				-- della fattura il cui nome contiene il testo, senza guardare le date dell'incarico (come Anagrafica > Soggetti)
				AND
					(
					@Amministratore IS NULL
					OR EXISTS (
						SELECT 1
						FROM
							dbo.tblAmministratoriSedi ax
							INNER JOIN dbo.tblAmministratori am ON ax.Id = am.Id
							INNER JOIN dbo.tblSedi ams ON am.IdSede = ams.Id
						WHERE
							ax.IdSede = c.IdSede
							AND am.IdAziendaInterna = f.IdSede
							AND am.Lock = 0
							AND ams.NomeCompleto LIKE '%' + @Amministratore + '%'
						)
					)
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
			f.IdClienteFornitore,
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

-- ===== 11. uspScadenze_get_ByData_List (sql/procedures/uspScadenze_get_ByData_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_ByData_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		DECLARE @AllaData SMALLDATETIME = CASE
			-- '1H' = la cella dell'ora delle viste Giorno e Settimana (hh:00-hh:59)
			WHEN @IdIntervallo = '1H' THEN DATEADD(MINUTE, 59, @DallaData)
			-- '30' = vecchia cella di mezz'ora: resta finche' l'applicazione non passa '1H'
			WHEN @IdIntervallo = '30' THEN DATEADD(MINUTE, 30, @DallaData)
			WHEN @IdIntervallo = '1D' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData))
			ELSE @DallaData
		END;

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		;WITH tbl AS (
			SELECT
				s.Id,
				StatoValore = CASE
					WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 1
					WHEN e.IdStato = 'A' THEN 2
					ELSE 0
				END,
				StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
				IdSerie = ISNULL(s2.Id, s.Id),
				Descrizione = e.AvvisoTesto,
				s.IdEvento,
				e.[Data],
				e.Ricorre,
				e.Eccezione
			FROM
				dbo.tblScadenze s
				INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
					ON s.IdEvento = e.Id
				-- Serie dell'occorrenza modificata (sostituto di un'eccezione): "Tutta la serie" apre la serie, non la sola occorrenza
				OUTER APPLY (
					SELECT TOP (1) s3.Id
					FROM dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblScadenze s3 ON zs.Id = s3.IdEvento
					WHERE
						zs.IdEvento = s.IdEvento
						AND zs.Lock = 0
						AND e.Ricorre = 0
				) s2
		)
		SELECT
			tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
			tbl.IdSerie, tbl.Descrizione, tbl.IdEvento,
			tbl.[Data], tbl.Ricorre, tbl.Eccezione,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		ORDER BY tbl.[Data]
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

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

-- ===== 12. uspScadenze_get_Calendario_Eventi_List (sql/procedures/uspScadenze_get_Calendario_Eventi_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_Calendario_Eventi_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@AllaData SMALLDATETIME = NULL
AS
-- Scadenze del calendario del contesto da @DallaData (compresa) ad @AllaData (esclusa), una per riga, comprese le
-- occorrenze delle serie e le annullate: la pagina le dispone come il calendario a blocchi dei Servizi (S4.7.7,
-- gemella di uspServizi_get_Calendario_Eventi_List) al posto della tabella a celle di uspScadenze_get_Calendario*_List.
-- Le scadenze non hanno durata (righe compatte) ne' richiedente: Descrizione = il testo dell'avviso (tipo e
-- descrizione). Stato: S scaduta, D da eseguire o in esecuzione, E eseguita, A annullata. IdSerie come in
-- uspScadenze_get_ByData_List (S5.8)
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL OR @AllaData IS NULL OR @AllaData <= @DallaData
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il periodo indicato non è valido';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		-- Fine esclusa: ufnEventi_get_List prende gli estremi compresi
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, @AllaData);

		SELECT
			s.Id,
			s.IdEvento,
			IdSerie = ISNULL(s2.Id, s.Id),
			e.[Data],
			e.InGiornata,
			Durata = CAST(NULL AS INT),
			Stato = CASE
				WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 'S'
				WHEN e.IdStato IN ('D', 'I') THEN 'D'
				ELSE e.IdStato
			END,
			StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, NULL),
			Descrizione = ISNULL(e.AvvisoTesto, ''),
			Indirizzo = CAST(NULL AS VARCHAR(200)),
			Risorse = r.Risorse,
			e.Ricorre,
			e.Eccezione
		FROM
			dbo.tblScadenze s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @fine, @IdCalendario, @IdTipo) e ON s.IdEvento = e.Id
			-- Serie dell'occorrenza modificata (come uspScadenze_get_ByData_List)
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM dbo.tblRicorrenzeEccezioni zs
				INNER JOIN dbo.tblScadenze s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = s.IdEvento
					AND zs.Lock = 0
					AND e.Ricorre = 0
			) s2
			-- Soggetti, persone e oggetti collegati, per il testo della riga
			OUTER APPLY (
				SELECT Risorse = STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY o.Tipo, n.Nome)
				FROM
					dbo.tblScadenzeOsepe so
					INNER JOIN dbo.tblOsepe o ON so.IdOsepe = o.Id
					CROSS APPLY (
						SELECT Nome = d.NomeCompleto FROM dbo.tblSedi d WHERE d.Id = so.IdOsepe AND o.Tipo = 'S'
						UNION ALL
						SELECT Nome = p.NomeCompleto FROM dbo.tblPersone p WHERE p.Id = so.IdOsepe AND o.Tipo = 'P'
						UNION ALL
						SELECT Nome = g.Nome FROM dbo.tblOggetti g WHERE g.Id = so.IdOsepe AND o.Tipo = 'O'
					) n
				WHERE so.Id = s.Id
			) r
		ORDER BY e.[Data], s.Id;

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

-- ===== 13. uspScadenze_get_CalendarioGiorno_List (sql/procedures/uspScadenze_get_CalendarioGiorno_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_CalendarioGiorno_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData));

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			AvvisoTesto = e.AvvisoTesto
		INTO #tEventi
		FROM dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				[Data] = DATEADD(HOUR, value, @DallaData),
				-- Fine della cella: hh:59 (con SMALLDATETIME equivale a < hh+1:00), cosi' anche
				-- le scadenze con i minuti fra 31 e 59 cadono nella cella della loro ora
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 23, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblScadenze s ON t.IdEvento = s.IdEvento
		)
		SELECT
			t0.Ora,
			Dati = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.Eventi AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t0.[Data], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t0.Scaduti,0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t0.Eseguiti,0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t0.Annullati,0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t0.Testo,''), '"', '\"') + '"}'
		FROM (
			SELECT [Data], Ora,
				Eventi = COUNT(Id),
				Scaduti = SUM(ISNULL(Scaduto, 0)),
				Eseguiti = SUM(ISNULL(Eseguito, 0)),
				Annullati = SUM(ISNULL(Annullato, 0)),
				Testo = MAX(AvvisoTesto)
			FROM cteDati
			GROUP BY [Data], Ora
		) t0
		ORDER BY t0.[Data];

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

-- ===== 14. uspScadenze_get_CalendarioMese_List (sql/procedures/uspScadenze_get_CalendarioMese_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_CalendarioMese_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, DATEADD(DAY, 42, @DallaData));

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			AvvisoTesto = FORMAT(e.[Data], 'HH:mm') + ' - ' + e.AvvisoTesto
		INTO #tEventi
		FROM dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				Settimana = value / 7,
				[Data] = DATEADD(DAY, value, @DallaData),
				-- Fine della cella: 23:59 del giorno, cosi' anche le scadenze dopo le 23:30 cadono nel loro giorno
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(DAY, value, @DallaData))),
				Giorno = DATEPART(DW, DATEADD(DAY, value, @DallaData))
			FROM GENERATE_SERIES(0, 41, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Giorno, c.Settimana, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblScadenze s ON t.IdEvento = s.IdEvento
		)
		SELECT
			Riferimento = t0.Settimana,
			Lun = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[1] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[1], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[1],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[1],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[1],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[1],''), '"', '\"') + '"}',
			Mar = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[2] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[2], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[2],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[2],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[2],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[2],''), '"', '\"') + '"}',
			Mer = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[3] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[3], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[3],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[3],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[3],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[3],''), '"', '\"') + '"}',
			Gio = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[4] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[4], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[4],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[4],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[4],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[4],''), '"', '\"') + '"}',
			Ven = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[5] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[5], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[5],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[5],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[5],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[5],''), '"', '\"') + '"}',
			Sab = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[6] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[6], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[6],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[6],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[6],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[6],''), '"', '\"') + '"}',
			Dom = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[7] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[7], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[7],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[7],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[7],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[7],''), '"', '\"') + '"}'
		FROM
			(SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Id
			FROM cteDati) t PIVOT (COUNT(Id) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t0
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,[Data]
			FROM cteDati) t PIVOT (MAX([Data]) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t1 ON t0.Settimana=t1.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Scaduto=ISNULL(Scaduto,0)
			FROM cteDati) t PIVOT (SUM(Scaduto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t2 ON t0.Settimana=t2.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Eseguito=ISNULL(Eseguito,0)
			FROM cteDati) t PIVOT (SUM(Eseguito) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t3 ON t0.Settimana=t3.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Annullato=ISNULL(Annullato,0)
			FROM cteDati) t PIVOT (SUM(Annullato) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t5 ON t0.Settimana=t5.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,AvvisoTesto
			FROM cteDati) t PIVOT (MAX(AvvisoTesto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t4 ON t0.Settimana=t4.Settimana
		ORDER BY t0.Settimana;

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

-- ===== 15. uspScadenze_get_CalendarioSettimana_List (sql/procedures/uspScadenze_get_CalendarioSettimana_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_CalendarioSettimana_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 8, @DallaData);

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			AvvisoTesto = e.AvvisoTesto
		INTO #tEventi
		FROM dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				[Data] = DATEADD(HOUR, value, @DallaData),
				-- Fine della cella: hh:59 (con SMALLDATETIME equivale a < hh+1:00), cosi' anche
				-- le scadenze con i minuti fra 31 e 59 cadono nella cella della loro ora
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, value, @DallaData)),
				Giorno = DATEPART(DW, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 167, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Giorno, c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblScadenze s ON t.IdEvento = s.IdEvento
		)
		SELECT
			Riferimento = t0.Ora,
			Lun = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[1] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[1], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[1],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[1],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[1],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[1],''), '"', '\"') + '"}',
			Mar = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[2] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[2], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[2],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[2],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[2],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[2],''), '"', '\"') + '"}',
			Mer = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[3] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[3], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[3],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[3],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[3],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[3],''), '"', '\"') + '"}',
			Gio = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[4] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[4], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[4],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[4],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[4],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[4],''), '"', '\"') + '"}',
			Ven = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[5] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[5], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[5],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[5],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[5],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[5],''), '"', '\"') + '"}',
			Sab = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[6] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[6], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[6],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[6],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[6],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[6],''), '"', '\"') + '"}',
			Dom = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[7] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[7], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[7],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[7],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[7],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[7],''), '"', '\"') + '"}'
		FROM
			(SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Id
			FROM cteDati) t PIVOT (COUNT(Id) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t0
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,[Data]
			FROM cteDati) t PIVOT (MAX([Data]) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t1 ON t0.Ora=t1.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Scaduto=ISNULL(Scaduto,0)
			FROM cteDati) t PIVOT (SUM(Scaduto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t2 ON t0.Ora=t2.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Eseguito=ISNULL(Eseguito,0)
			FROM cteDati) t PIVOT (SUM(Eseguito) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t3 ON t0.Ora=t3.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Annullato=ISNULL(Annullato,0)
			FROM cteDati) t PIVOT (SUM(Annullato) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t5 ON t0.Ora=t5.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,AvvisoTesto
			FROM cteDati) t PIVOT (MAX(AvvisoTesto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t4 ON t0.Ora=t4.Ora
		ORDER BY t0.Ora;

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

-- ===== 16. uspScadenze_get_List (sql/procedures/uspScadenze_get_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);

		-- Periodo esatto: dalla data (00:00) per l'intervallo, fine esclusa (1 giorno = il solo giorno della data,
		-- 1 settimana = 7 giorni), come uspServizi_get_Impegni_Elenco_List. Fino al 2026-11-22 arrivava alla fine
		-- del giorno dopo l'intervallo (docs/regole/scadenze-servizi.md S4.7.5)
		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, CASE
			WHEN @IdIntervallo = '1W' THEN DATEADD(WEEK, 1, @DallaData)
			WHEN @IdIntervallo = '2W' THEN DATEADD(WEEK, 2, @DallaData)
			WHEN @IdIntervallo = '1M' THEN DATEADD(MONTH, 1, @DallaData)
			WHEN @IdIntervallo = '2M' THEN DATEADD(MONTH, 2, @DallaData)
			WHEN @IdIntervallo = '6M' THEN DATEADD(MONTH, 6, @DallaData)
			WHEN @IdIntervallo = '1Y' THEN DATEADD(YEAR, 1, @DallaData)
			ELSE DATEADD(DAY, 1, @DallaData)
		END);

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage  INT,
            @Offset       INT,
            @IdSessione   CHAR(16),
            @IdIntervallo CHAR(2),
            @DallaData    SMALLDATETIME,
            @AllaData     SMALLDATETIME,
            @Stato        CHAR(1),
            @Etichetta    VARCHAR(50),
            @Search       VARCHAR(50),
            @IdCalendario tvpId_char_16 READONLY,
            @IdTipo       tvpId_char_1  READONLY';

		SET @stmt = N'
        WITH tbl AS (
            SELECT
                s.Id,
                StatoValore = CASE
                    WHEN e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE() THEN 1
                    WHEN e.IdStato = ''A''                                      THEN 2
                    ELSE 0
                END,
                StatoDescrizione = e.Stato + IIF(e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE(), '' - Scaduto'', ''''),
                IdSerie          = ISNULL(s2.Id, s.Id),
                s.Descrizione,
                s.IdEvento,
                e.[Data],
                e.Ricorre,
                e.Eccezione,
                Tipo             = t.Nome,
                e.Etichette
            FROM
                dbo.tblScadenze s
                INNER JOIN dbo.tblTipi t ON s.IdTipo = t.Id
                INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
                    ON s.IdEvento = e.Id
                -- Serie della occorrenza modificata (sostituto di una eccezione): con Tutta la serie si apre la serie
                OUTER APPLY (
                    SELECT TOP (1) s3.Id
                    FROM dbo.tblRicorrenzeEccezioni zs
                    INNER JOIN dbo.tblScadenze s3 ON zs.Id = s3.IdEvento
                    WHERE zs.IdEvento = s.IdEvento AND zs.Lock = 0 AND e.Ricorre = 0
                ) s2
            WHERE 1 = 1';

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.IdEvento IN (
                    SELECT t.Id FROM dbo.tblEventiEtichette t
                    INNER JOIN dbo.tblEtichette e ON t.IdEtichetta = e.Id
                    WHERE e.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Search IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.Descrizione LIKE ''%'' + @Search + ''%''';

		IF @Stato <> 'T'
		BEGIN
			IF @Stato = 'S'
				SET @stmt = @stmt + N'
                    AND (e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE())';
			ELSE
				SET @stmt = @stmt + N'
                    AND e.IdStato = @Stato';
		END

		SET @stmt = @stmt + N'
        ),
        tblCount AS (SELECT COUNT(*) AS RowsCount FROM tbl)
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.IdSerie, tbl.Descrizione, tbl.IdEvento,
            tbl.[Data], tbl.Ricorre, tbl.Eccezione,
            tbl.Tipo, tbl.Etichette,
            tblCount.RowsCount
        FROM tbl
        CROSS JOIN tblCount
        ORDER BY tbl.[Data]
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY;';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Stato = @Stato,
			@Etichetta = @Etichetta,
			@Search = @Search,
			@IdCalendario = @IdCalendario,
			@IdTipo = @IdTipo;

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

-- ===== 17. uspScadenze_ins (sql/procedures/uspScadenze_ins.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_ins]
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL,
	@OccorrenzaESuccessive BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro obbligatorio
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (SCD = Gestione Scadenze)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Legge il calendario: dalla sessione per nuove scadenze, dall'evento per ricorrenti
		DECLARE @idCalendario CHAR(16);
		IF @IdEvento IS NULL
			SELECT @idCalendario = s.IdCalendario
			FROM dbo.tblSessioni s
			INNER JOIN dbo.tblCalendari c ON s.IdCalendario = c.Id
											   AND c.IdModulo = 'SCD'
			WHERE s.Id = @IdSessione;
		ELSE
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblEventi e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
						   ON c.IdSede = i.Id
				WHERE e.Id = @IdEvento)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			SELECT @idCalendario = IdCalendario
			FROM dbo.tblEventi
			WHERE Id = @IdEvento;
		END

		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END

		-- Genera i nuovi Id FUORI dalla transazione:
		-- uspId_get gestisce la propria transazione internamente
		DECLARE @returnIdEvento CHAR(16) = NULL;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			IF @IdEvento IS NULL
			BEGIN
				-- Nuova scadenza da zero
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Lock)
				VALUES
					(@returnIdEvento, @idCalendario, 'D', 'S', @Data, 0, 0, 2);

				INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo)
				VALUES (@returnId, @returnIdEvento, @IdTipo);
			END
			ELSE
			BEGIN
				-- Nuova occorrenza da evento ricorrente esistente: copia i dati
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Etichette, Lock)
				SELECT
					@returnIdEvento, @idCalendario, 'D', 'S', @Data,
					InGiornata, AvvisoAnticipo, Email, Etichette, 2
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				-- Copia le proprieta' dell'evento originale (come uspServizi_ins: fino al 2026-11-23 non venivano
				-- copiate e l'occorrenza modificata perdeva i valori delle proprieta' del tipo)
				INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @returnIdEvento, IdProprieta, Valore
				FROM dbo.tblEventiProprieta
				WHERE Id = @IdEvento;

				-- Copia le etichette dell'evento originale
				INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
				SELECT @returnIdEvento, IdEtichetta
				FROM dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				IF @OccorrenzaESuccessive = 1
				BEGIN
					-- Copia la ricorrenza dell'evento originale
					-- Con un numero di ripetizioni la nuova serie ha solo quelle rimaste: si tolgono le occorrenze della
					-- serie originale prima di @Data (n = posizione dell'occorrenza), altrimenti la serie si allungherebbe
					INSERT INTO dbo.tblRicorrenze
						(Id, IdParent, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
					SELECT
						@returnIdEvento, @IdEvento,
						r.IdIntervallo, r.Frequenza, r.DataFine,
						IIF(r.Ripetizioni > 0, IIF(r.Ripetizioni - n.Precedenti < 1, 1, r.Ripetizioni - n.Precedenti), r.Ripetizioni),
						r.Relativo
					FROM
						dbo.tblRicorrenze r
						INNER JOIN dbo.tblEventi e ON r.Id = e.Id
						CROSS APPLY (
							SELECT Precedenti = ISNULL(CASE r.IdIntervallo
								WHEN 'DD' THEN DATEDIFF(DAY, e.[Data], @Data) / NULLIF(r.Frequenza, 0)
								WHEN 'WK' THEN DATEDIFF(DAY, e.[Data], @Data) / NULLIF(7 * r.Frequenza, 0)
								WHEN 'MM' THEN DATEDIFF(MONTH, e.[Data], @Data) / NULLIF(r.Frequenza, 0)
								WHEN 'YY' THEN DATEDIFF(YEAR, e.[Data], @Data) / NULLIF(r.Frequenza, 0)
								ELSE 0
							END, 0)
						) n
					WHERE r.Id = @IdEvento;
				END
				ELSE
				BEGIN
					-- Aggiunge un'eccezione per questa singola occorrenza
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE
						Id = @IdEvento
						AND [Data] = @Data;

					INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
					VALUES (@IdEvento, @Data, @returnIdEvento, 2);
				END

				-- Copia la scadenza originale
				INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo, Descrizione)
				SELECT @returnId, @returnIdEvento, IdTipo, Descrizione
				FROM dbo.tblScadenze
				WHERE IdEvento = @IdEvento;

				-- Copia gli Osepe associati alla scadenza originale
				INSERT INTO dbo.tblScadenzeOsepe (Id, IdOsepe)
				SELECT @returnId, o.IdOsepe
				FROM dbo.tblScadenze s
				INNER JOIN dbo.tblScadenzeOsepe o ON s.Id = o.Id
				WHERE s.IdEvento = @IdEvento;
			END

		COMMIT TRANSACTION;

		SELECT @returnId AS Id;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
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

-- ===== 18. uspScadenze_upd (sql/procedures/uspScadenze_upd.sql)
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Ricorre BIT = 0,
	@Avviso BIT = 0,
	@AvvisoAnticipo INT = 0,
	@Email VARCHAR(1000) = NULL,
	@IdEtichette VARCHAR(50) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@Frequenza INT = NULL,
	@DataFine SMALLDATETIME = NULL,
	@Ripetizioni INT = NULL,
	@Relativo INT = 0,
	@OccorrenzaESuccessive BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @permesso TINYINT;
	DECLARE @frequenzaMax INT = 0;
	DECLARE @minuti INT = 0;
	DECLARE @idEventoParent CHAR(16);
	DECLARE @dataFineParent SMALLDATETIME;
	DECLARE @idTipo CHAR(16);

	BEGIN TRY

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

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
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblScadenze s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE
				s.Id = @Id
				AND e.Id = @IdEvento
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Normalizzazione parametri VARCHAR opzionali
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @Email = dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1);

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblScadenze
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Limiti della serie: le date ammesse dall'applicazione (ufnDate_get_Min / _Max = Constants.SQL.MinDate / MaxDate)
		IF @Ricorre = 1 AND @Data < dbo.ufnDate_get_Min()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data minima per le scadenze ricorrenti è il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND @DataFine IS NOT NULL AND @DataFine < @Data
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine della serie non può essere inferiore alla data di inizio';
			GOTO BRANCH_END;
		END

		IF @IdIntervallo = 'YY'
		BEGIN
			SET @frequenzaMax = DATEDIFF(YEAR, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' anni';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @IdIntervallo = 'MM'
		BEGIN
			SET @frequenzaMax = DATEDIFF(MONTH, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' mesi';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;

			IF (EXISTS (SELECT 1
			FROM dbo.tblRicorrenze
			WHERE Id = @IdEvento))
			   AND @OccorrenzaESuccessive = 0
			BEGIN
				IF @Ricorre = 0
				BEGIN
					DELETE dbo.tblRicorrenze
					WHERE Id = @IdEvento;
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE Id = @IdEvento;
				END
				ELSE
				BEGIN
					IF EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenze
						WHERE
							Id = @IdEvento
							AND
								(
								IdIntervallo <> @IdIntervallo
								OR Frequenza <> @Frequenza
								OR Relativo <> @Relativo
								)
					)
					BEGIN
						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @IdEvento
							AND IdEvento IS NULL;
					END

					SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
					FROM dbo.tblEventi
					WHERE Id = @IdEvento;

					IF ISNULL(@minuti, 0) <> 0
						UPDATE dbo.tblRicorrenzeEccezioni
						SET [Data] = DATEADD(MINUTE, @minuti, [Data])
						WHERE Id = @IdEvento;

					UPDATE dbo.tblRicorrenze
					SET
						IdIntervallo = @IdIntervallo,
						Frequenza = @Frequenza,
						DataFine = @DataFine,
						Ripetizioni = @Ripetizioni,
						Relativo = @Relativo
					WHERE Id = @IdEvento;
				END
			END
			ELSE IF @Ricorre = 1 AND @OccorrenzaESuccessive = 0
			BEGIN
				INSERT dbo.tblRicorrenze
					(Id, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
				VALUES
					(@IdEvento, @IdIntervallo, @Frequenza, @DataFine, @Ripetizioni, @Relativo);
			END
			ELSE IF @OccorrenzaESuccessive = 1
			BEGIN
				SELECT @idEventoParent = IdParent
				FROM dbo.tblRicorrenze
				WHERE Id = @IdEvento;

				-- La serie originale finisce il giorno prima dell'occorrenza scelta (la data della nuova serie
				-- prima del salvataggio, scritta da uspScadenze_ins), anche se la nuova serie viene spostata
				SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				SET @dataFineParent =
					DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
						DATEADD(DAY, DATEDIFF(DAY, 0, DATEADD(MINUTE, -ISNULL(@minuti, 0), @Data)), -1)));

				UPDATE dbo.tblRicorrenze
				SET
					DataFine = @dataFineParent,
					Ripetizioni = 0
				WHERE Id = @idEventoParent;

				UPDATE dbo.tblRicorrenze
				SET
					IdIntervallo = @IdIntervallo,
					Frequenza = @Frequenza,
					DataFine = @DataFine,
					Ripetizioni = @Ripetizioni,
					Relativo = @Relativo
				WHERE Id = @IdEvento;

				-- Le occorrenze cancellate o modificate della serie originale dalla data scelta in poi passano alla
				-- nuova serie, spostate come la nuova serie (stessa regola della modifica di tutta la serie):
				-- cancellate, una cancellata ricomparirebbe e una modificata sarebbe doppia. Se cambia la frequenza
				-- le date non coincidono piu': passano solo le occorrenze modificate (eventi a se', S5.4)
				INSERT dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				SELECT @IdEvento, DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data]), z.IdEvento, z.Lock
				FROM
					dbo.tblRicorrenzeEccezioni z
					INNER JOIN dbo.tblRicorrenze p ON z.Id = p.Id
				WHERE
					z.Id = @idEventoParent
					AND z.[Data] > @dataFineParent
					AND
						(
						z.IdEvento IS NOT NULL
						OR
							(
							p.IdIntervallo = @IdIntervallo
							AND p.Frequenza = @Frequenza
							AND p.Relativo = @Relativo
							)
						)
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenzeEccezioni y
						WHERE
							y.Id = @IdEvento
							AND y.[Data] = DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data])
					);

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @idEventoParent
					AND [Data] > @dataFineParent;
			END

			-- Sblocca l'eccezione di ricorrenza che referenzia questo evento come sostituto
			-- (occorrenza singola modificata): senza questo sblocco l'occorrenza originale
			-- resta visibile in calendario insieme a quella modificata. No-op se @IdEvento
			-- non e' il sostituto di nessuna eccezione.
			UPDATE dbo.tblRicorrenzeEccezioni
			SET Lock = 0
			WHERE
				IdEvento = @IdEvento
				AND Lock <= 2;

			UPDATE dbo.tblScadenze
			SET Descrizione = ISNULL(@Descrizione, Descrizione)
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Scadenza non trovata o già eliminata';
				GOTO BRANCH_END;
			END

			DELETE dbo.tblEventiEtichette
			WHERE Id = @IdEvento;

			INSERT dbo.tblEventiEtichette (Id, IdEtichetta)
			SELECT TOP 3
				@IdEvento,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value
			WHERE v.value <> '';

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				AvvisoAnticipo = IIF(@Avviso = 0, NULL, @AvvisoAnticipo),
				Email = IIF(@Avviso = 0, NULL, @Email),
				Avviso = dbo.ufnStringhe_get_Compatta( t.Nome + ' - ' + @Descrizione, 200, default),
				Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c.Hex, c.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblEventiEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c ON et.IdColore = c.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH ),
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblScadenze s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			WHERE
				e.Id = @IdEvento
				AND e.Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Evento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

-- ===== 19. uspScadenze_upd_Data (sql/procedures/uspScadenze_upd_Data.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_upd_Data]
	@IdSessione CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@DataOccorrenza SMALLDATETIME = NULL,
	@DataCella SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
-- Sposta una scadenza su un'altra ora o un altro giorno (trascinamento nel calendario, S4.7.6, gemella di
-- uspServizi_upd_Data): cambia solo la data. @IdEvento e @DataOccorrenza (la data della scadenza o dell'occorrenza)
-- sono quelli della riga trascinata; @DataCella e' l'inizio della cella di arrivo, @IdIntervallo la sua ampiezza:
-- '1H' l'ora delle viste Giorno e Settimana (nuova ora = ora della cella con i minuti della scadenza), '1D' il giorno
-- (vista Mese e fascia In giornata: cambia solo il giorno), '30' la mezz'ora (viste Giorno e Settimana dal 2026-11-23:
-- @DataCella e' il nuovo inizio, su :00 o :30, come nell'anteprima del trascinamento). La scadenza "In giornata" cambia sempre solo il giorno.
-- Per un'occorrenza di una serie ricorrente si sposta la sola occorrenza, che diventa un'occorrenza modificata
-- (come "Solo questa occorrenza" della scheda, S5.3); la serie non si sposta mai trascinando. Si spostano solo le
-- scadenze da eseguire o in esecuzione. Le scadenze non hanno durata. Restituisce l'Id della scadenza spostata
-- (la nuova, per un'occorrenza).
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;
		DECLARE @ricorre BIT = 0;
		DECLARE @idStato CHAR(1);
		DECLARE @inGiornata BIT;
		DECLARE @dataEvento SMALLDATETIME;
		DECLARE @dataPartenza SMALLDATETIME;
		DECLARE @data SMALLDATETIME;
		DECLARE @idCalendario CHAR(16);
		DECLARE @idScadenza CHAR(16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataCella IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL OR @IdIntervallo NOT IN ('1H', '1D', '30')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END
		-- Mezz'ora: la cella parte alle :00 o alle :30
		IF @IdIntervallo = '30' AND DATEPART(MINUTE, @DataCella) NOT IN (0, 30)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non è l''inizio di una mezz''ora';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			@idScadenza = s.Id,
			@idStato = e.IdStato,
			@inGiornata = e.InGiornata,
			@dataEvento = e.[Data],
			@idCalendario = e.IdCalendario,
			@ricorre = IIF(r.Id IS NULL, 0, 1)
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblScadenze s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
		WHERE
			e.Id = @IdEvento
			AND e.Lock = 0;

		IF @idScadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Scadenza non trovata o già eliminata';
			GOTO BRANCH_END;
		END

		IF @ricorre = 1 AND @DataOccorrenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataOccorrenza non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @idStato NOT IN ('D', 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si spostano solo le scadenze da eseguire o in esecuzione: per le altre modificare la data nella scheda';
			GOTO BRANCH_END;
		END

		-- Nuova data: il giorno della cella di arrivo con l'ora della scadenza (vista Mese e scadenze In giornata),
		-- oppure l'ora della cella con i minuti della scadenza (viste Giorno e Settimana)
		SET @dataPartenza = IIF(@ricorre = 1, @DataOccorrenza, @dataEvento);

		IF @IdIntervallo = '1D' OR @inGiornata = 1
			SET @data = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST(CAST(@dataPartenza AS DATE) AS SMALLDATETIME), @dataPartenza),
				CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME));
		ELSE IF @IdIntervallo = '30'
			-- Mezz'ora (anteprima del trascinamento): l'inizio e' quello della cella
			SET @data = @DataCella;
		ELSE
			SET @data = DATEADD(MINUTE, DATEPART(MINUTE, @dataPartenza),
				DATEADD(HOUR, DATEDIFF(HOUR, CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME), @DataCella), CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME)));

		IF @data < dbo.ufnDate_get_Min() OR @data > dbo.ufnDate_get_Max()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data deve essere compresa fra il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy') + ' e il ' + FORMAT(dbo.ufnDate_get_Max(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		-- Nessuno spostamento: rilasciato nella cella da cui e' partito
		IF @data = @dataPartenza
		BEGIN
			SELECT @idScadenza AS Id;
			GOTO BRANCH_END;
		END

		IF @ricorre = 0
		BEGIN
			UPDATE dbo.tblEventi
			SET [Data] = @data
			WHERE
				Id = @IdEvento
				AND Lock = 0;

			SET @returnId = @idScadenza;
		END
		ELSE
		BEGIN
			-- Occorrenza di una serie: la data deve essere un'occorrenza vera (non cancellata ne' gia' modificata)
			DECLARE @calendari tvpId_char_16;
			INSERT INTO @calendari (Id) VALUES (@idCalendario);
			DECLARE @tipi tvpId_char_1;
			INSERT INTO @tipi (Id) VALUES ('S');

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.ufnEventi_get_List(@DataOccorrenza, @DataOccorrenza, @calendari, @tipi) e
				WHERE
					e.Id = @IdEvento
					AND e.[Data] = @DataOccorrenza
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Occorrenza non trovata: aggiornare il calendario';
				GOTO BRANCH_END;
			END

			-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione), come in uspScadenze_ins
			DECLARE @returnIdEvento CHAR(16) = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

			BEGIN TRANSACTION;

				-- Copia dell'occorrenza come in uspScadenze_ins (ramo della singola occorrenza), gia' alla nuova data e
				-- senza bozza (Lock = 0): non passa dalla scheda. Proprieta' del tipo comprese
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
				SELECT
					@returnIdEvento, IdCalendario, 'D', 'S', @data,
					InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, 0
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @returnIdEvento, IdProprieta, Valore
				FROM dbo.tblEventiProprieta
				WHERE Id = @IdEvento;

				INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
				SELECT @returnIdEvento, IdEtichetta
				FROM dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @IdEvento
					AND [Data] = @DataOccorrenza;

				INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				VALUES (@IdEvento, @DataOccorrenza, @returnIdEvento, 0);

				INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo, Descrizione)
				SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, Descrizione
				FROM dbo.tblScadenze
				WHERE IdEvento = @IdEvento;

				INSERT INTO dbo.tblScadenzeOsepe (Id, IdOsepe)
				SELECT @returnId, o.IdOsepe
				FROM dbo.tblScadenzeOsepe o
				WHERE o.Id = @idScadenza;

			COMMIT TRANSACTION;
		END

		EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnId AS Id;

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

-- ===== 20. uspServizi_get (sql/procedures/uspServizi_get.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get]
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
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			WHERE
				s.Id = @Id
				AND e.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Servizio non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			s.IdTipo,
			IdRichiedente = ISNULL(s.IdRichiedente, ''),
			IdEvento = ISNULL(s.IdEvento, ''),
			Descrizione = ISNULL(s.Descrizione, ''),
			DataRichiesta = ISNULL(s.DataRichiesta, GETDATE()),
			IdStato = ISNULL(e.IdStato, 'D'),
			[Data] = ISNULL(e.[Data], DATEADD(MINUTE, ((DATEDIFF(MINUTE, 0, GETDATE()) / 30) * 30), 0)),
			InGiornata = ISNULL(e.InGiornata, 0),
			s.Durata,
			Ricorre = CAST(IIF(r.Id IS NULL, 0, 1) AS BIT),
			Avviso = CAST(IIF(e.AvvisoAnticipo IS NULL, 0, 1) AS BIT),
			Email = ISNULL(e.Email, ''),
			AvvisoAnticipo = ISNULL(e.AvvisoAnticipo, 0),
			IdIntervallo = ISNULL(r.IdIntervallo, 'DD'),
			Frequenza = ISNULL(r.Frequenza, 1),
			Ripetizioni = ISNULL(r.Ripetizioni, 0),
			Relativo = ISNULL(r.Relativo, 0),
			Eccezione = CAST(IIF(z.IdEvento IS NULL, 0, 1) AS BIT),
			DataFine = ISNULL(r.DataFine, '2050-12-31 23:59:00'),
			RicorrenzaTermine = CASE
				WHEN r.Ripetizioni > 0 THEN 2
				WHEN r.DataFine < '2050-12-31 23:59:00' THEN 1
				ELSE 0
			END,
			e.Lock,
			Proprieta = dbo.ufnEventi_get_TipoProprieta(s.IdEvento, s.IdTipo),
			FirmaRichiedente = fr.Firma
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.IdEvento
													 AND z.Lock <= 2
			LEFT JOIN dbo.tblEventiFirme er ON e.Id = er.Id
													 AND er.IdTipo = 'R'
			LEFT JOIN dbo.tblFirme fr ON er.IdFirma = fr.Id
		WHERE
			s.Id = @Id
			AND e.Lock <= 2;

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

-- ===== 21. uspServizi_get_ByData_List (sql/procedures/uspServizi_get_ByData_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_ByData_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		DECLARE @AllaData SMALLDATETIME = CASE
			-- '1H' = la cella dell'ora delle viste Giorno e Settimana (hh:00-hh:59)
			WHEN @IdIntervallo = '1H' THEN DATEADD(MINUTE, 59, @DallaData)
			-- '30' = vecchia cella di mezz'ora: resta finche' l'applicazione non passa '1H'
			WHEN @IdIntervallo = '30' THEN DATEADD(MINUTE, 30, @DallaData)
			WHEN @IdIntervallo = '1D' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData))
			ELSE @DallaData
		END;

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		;WITH tbl AS (
			SELECT
				s.Id,
				StatoValore = CASE
					WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 1
					WHEN e.IdStato = 'A' THEN 2
					ELSE 0
				END,
				StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
				IdSerie = ISNULL(s2.Id, s.Id),
				Descrizione = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - ' + ISNULL(e.AvvisoTesto, ''),
				s.IdEvento,
				e.[Data],
				e.Ricorre,
				e.Eccezione
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
					ON s.IdEvento = e.Id
				-- Serie dell'occorrenza modificata (sostituto di un'eccezione): "Tutta la serie" apre la serie, non la sola occorrenza
				OUTER APPLY (
					SELECT TOP (1) s3.Id
					FROM dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
					WHERE
						zs.IdEvento = s.IdEvento
						AND zs.Lock = 0
						AND e.Ricorre = 0
				) s2
		)
		SELECT
			tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
			tbl.IdSerie, tbl.Descrizione, tbl.IdEvento,
			tbl.[Data], tbl.Ricorre, tbl.Eccezione,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		ORDER BY tbl.[Data]
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

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

-- ===== 22. uspServizi_get_Calendario_Eventi_List (sql/procedures/uspServizi_get_Calendario_Eventi_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Calendario_Eventi_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@AllaData SMALLDATETIME = NULL
AS
-- Servizi del calendario del contesto da @DallaData (compresa) ad @AllaData (esclusa), uno per riga, comprese le
-- occorrenze delle serie e gli annullati: la pagina li dispone a blocchi (Servizi > Calendario a blocchi, S4.7.7),
-- al posto della tabella a celle di uspServizi_get_Calendario*_List. Stato: S scaduto (da eseguire o in esecuzione
-- con la data passata), D da eseguire o in esecuzione, E eseguito, A annullato. IdSerie come in
-- uspServizi_get_ByData_List (S5.8): per l'occorrenza modificata e' la serie di cui e' il sostituto
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL OR @AllaData IS NULL OR @AllaData <= @DallaData
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il periodo indicato non è valido';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		-- Fine esclusa: ufnEventi_get_List prende gli estremi compresi
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, @AllaData);

		SELECT
			s.Id,
			s.IdEvento,
			IdSerie = ISNULL(s2.Id, s.Id),
			e.[Data],
			e.InGiornata,
			s.Durata,
			Stato = CASE
				WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 'S'
				WHEN e.IdStato IN ('D', 'I') THEN 'D'
				ELSE e.IdStato
			END,
			StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			-- Nel blocco solo tipo e richiedente (leggibile anche stretto); l'indirizzo va nel tooltip e nell'elenco
			Descrizione = ISNULL(NULLIF(CONCAT_WS(' - ', t.Nome, r0.NomeCompleto), ''), ISNULL(e.AvvisoTesto, '')),
			Indirizzo = r0.IndirizzoCompleto,
			Risorse = r.Risorse,
			e.Ricorre,
			e.Eccezione
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @fine, @IdCalendario, @IdTipo) e ON s.IdEvento = e.Id
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblSedi r0 ON s.IdRichiedente = r0.Id
			-- Serie dell'occorrenza modificata (come uspServizi_get_ByData_List)
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM dbo.tblRicorrenzeEccezioni zs
				INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = s.IdEvento
					AND zs.Lock = 0
					AND e.Ricorre = 0
			) s2
			-- Persone e oggetti impiegati, per il testo del blocco
			OUTER APPLY (
				SELECT Risorse = STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY o.Tipo, n.Nome)
				FROM
					dbo.tblServiziOsepe so
					INNER JOIN dbo.tblOsepe o ON so.IdOsepe = o.Id
					CROSS APPLY (
						SELECT Nome = p.NomeCompleto FROM dbo.tblPersone p WHERE p.Id = so.IdOsepe AND o.Tipo = 'P'
						UNION ALL
						SELECT Nome = g.Nome FROM dbo.tblOggetti g WHERE g.Id = so.IdOsepe AND o.Tipo = 'O'
					) n
				WHERE so.Id = s.Id
			) r
		ORDER BY e.[Data], s.Id;

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

-- ===== 23. uspServizi_get_CalendarioGiorno_List (sql/procedures/uspServizi_get_CalendarioGiorno_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_CalendarioGiorno_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData));

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			-- Il servizio sta nella cella dell'ora di inizio anche con la durata: il testo ne mostra l'orario
			AvvisoTesto = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - ' + ISNULL(e.AvvisoTesto, '')
		INTO #tEventi
		FROM
			dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
			LEFT JOIN dbo.tblServizi s ON e.Id = s.IdEvento;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				[Data] = DATEADD(HOUR, value, @DallaData),
				-- Fine della cella: hh:59 (con SMALLDATETIME equivale a < hh+1:00), cosi' anche
				-- i servizi con i minuti fra 31 e 59 cadono nella cella della loro ora
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 23, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblServizi s ON t.IdEvento = s.IdEvento
		)
		SELECT
			t0.Ora,
			Dati = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.Eventi AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t0.[Data], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t0.Scaduti,0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t0.Eseguiti,0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t0.Annullati,0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t0.Testo,''), '"', '\"') + '"}'
		FROM (
			SELECT [Data], Ora,
				Eventi = COUNT(Id),
				Scaduti = SUM(ISNULL(Scaduto, 0)),
				Eseguiti = SUM(ISNULL(Eseguito, 0)),
				Annullati = SUM(ISNULL(Annullato, 0)),
				Testo = MAX(AvvisoTesto)
			FROM cteDati
			GROUP BY [Data], Ora
		) t0
		ORDER BY t0.[Data];

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

-- ===== 24. uspServizi_get_CalendarioMese_List (sql/procedures/uspServizi_get_CalendarioMese_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_CalendarioMese_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, DATEADD(DAY, 42, @DallaData));

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			-- Orario del servizio (inizio e fine con la durata, "In giornata" senza ora)
			AvvisoTesto = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - ' + ISNULL(e.AvvisoTesto, '')
		INTO #tEventi
		FROM
			dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
			LEFT JOIN dbo.tblServizi s ON e.Id = s.IdEvento;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				Settimana = value / 7,
				[Data] = DATEADD(DAY, value, @DallaData),
				-- Fine della cella: 23:59 del giorno, cosi' anche i servizi dopo le 23:30 cadono nel loro giorno
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(DAY, value, @DallaData))),
				Giorno = DATEPART(DW, DATEADD(DAY, value, @DallaData))
			FROM GENERATE_SERIES(0, 41, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Giorno, c.Settimana, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblServizi s ON t.IdEvento = s.IdEvento
		)
		SELECT
			Riferimento = t0.Settimana,
			Lun = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[1] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[1], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[1],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[1],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[1],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[1],''), '"', '\"') + '"}',
			Mar = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[2] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[2], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[2],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[2],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[2],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[2],''), '"', '\"') + '"}',
			Mer = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[3] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[3], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[3],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[3],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[3],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[3],''), '"', '\"') + '"}',
			Gio = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[4] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[4], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[4],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[4],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[4],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[4],''), '"', '\"') + '"}',
			Ven = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[5] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[5], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[5],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[5],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[5],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[5],''), '"', '\"') + '"}',
			Sab = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[6] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[6], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[6],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[6],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[6],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[6],''), '"', '\"') + '"}',
			Dom = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[7] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[7], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[7],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[7],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[7],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[7],''), '"', '\"') + '"}'
		FROM
			(SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Id
			FROM cteDati) t PIVOT (COUNT(Id) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t0
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,[Data]
			FROM cteDati) t PIVOT (MAX([Data]) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t1 ON t0.Settimana=t1.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Scaduto=ISNULL(Scaduto,0)
			FROM cteDati) t PIVOT (SUM(Scaduto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t2 ON t0.Settimana=t2.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Eseguito=ISNULL(Eseguito,0)
			FROM cteDati) t PIVOT (SUM(Eseguito) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t3 ON t0.Settimana=t3.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,Annullato=ISNULL(Annullato,0)
			FROM cteDati) t PIVOT (SUM(Annullato) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t5 ON t0.Settimana=t5.Settimana
			LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Settimana,AvvisoTesto
			FROM cteDati) t PIVOT (MAX(AvvisoTesto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t4 ON t0.Settimana=t4.Settimana
		ORDER BY t0.Settimana;

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

-- ===== 25. uspServizi_get_CalendarioSettimana_List (sql/procedures/uspServizi_get_CalendarioSettimana_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_CalendarioSettimana_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 8, @DallaData);

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			-- Il servizio sta nella cella dell'ora di inizio anche con la durata: il testo ne mostra l'orario
			AvvisoTesto = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - ' + ISNULL(e.AvvisoTesto, '')
		INTO #tEventi
		FROM
			dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
			LEFT JOIN dbo.tblServizi s ON e.Id = s.IdEvento;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				[Data] = DATEADD(HOUR, value, @DallaData),
				-- Fine della cella: hh:59 (con SMALLDATETIME equivale a < hh+1:00), cosi' anche
				-- i servizi con i minuti fra 31 e 59 cadono nella cella della loro ora
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, value, @DallaData)),
				Giorno = DATEPART(DW, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 167, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Giorno, c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblServizi s ON t.IdEvento = s.IdEvento
		)
		SELECT
			Riferimento = t0.Ora,
			Lun = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[1] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[1], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[1],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[1],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[1],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[1],''), '"', '\"') + '"}',
			Mar = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[2] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[2], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[2],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[2],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[2],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[2],''), '"', '\"') + '"}',
			Mer = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[3] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[3], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[3],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[3],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[3],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[3],''), '"', '\"') + '"}',
			Gio = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[4] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[4], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[4],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[4],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[4],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[4],''), '"', '\"') + '"}',
			Ven = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[5] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[5], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[5],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[5],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[5],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[5],''), '"', '\"') + '"}',
			Sab = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[6] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[6], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[6],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[6],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[6],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[6],''), '"', '\"') + '"}',
			Dom = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[7] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[7], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[7],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[7],0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t5.[7],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[7],''), '"', '\"') + '"}'
		FROM
			(SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Id
			FROM cteDati) t PIVOT (COUNT(Id) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t0
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,[Data]
			FROM cteDati) t PIVOT (MAX([Data]) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t1 ON t0.Ora=t1.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Scaduto=ISNULL(Scaduto,0)
			FROM cteDati) t PIVOT (SUM(Scaduto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t2 ON t0.Ora=t2.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Eseguito=ISNULL(Eseguito,0)
			FROM cteDati) t PIVOT (SUM(Eseguito) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t3 ON t0.Ora=t3.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Annullato=ISNULL(Annullato,0)
			FROM cteDati) t PIVOT (SUM(Annullato) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t5 ON t0.Ora=t5.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,AvvisoTesto
			FROM cteDati) t PIVOT (MAX(AvvisoTesto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t4 ON t0.Ora=t4.Ora
		ORDER BY t0.Ora;

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

-- ===== 26. uspServizi_get_Esportazione (sql/procedures/uspServizi_get_Esportazione.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Servizi: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspServizi_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspServizi_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: a parità di data vale l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IdSerie CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Tipo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			Richiedente VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NULL,
			Ricorre BIT NULL,
			Eccezione BIT NULL,
			Etichette VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			Durata INT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, IdSerie, Tipo, Descrizione, Richiedente, IdEvento, [Data], Ricorre, Eccezione, Etichette, Durata, RowsCount)
		EXEC dbo.uspServizi_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@Stato = @Stato,
			@Etichetta = @Etichetta,
			@Search = @Search;

		SELECT
			[Data] = [Data],
			-- Durata in ore (numero, 2:30 = 2,5), vuota se non indicata (esportazione.md, E3.5)
			[Durata (ore)] = CAST(Durata / 60.0 AS DECIMAL(6, 2)),
			[Tipo] = Tipo,
			[Descrizione] = Descrizione,
			[Richiedente] = Richiedente,
			[Stato] = StatoDescrizione,
			[Ricorrente] = IIF(Ricorre = 1, 'Sì', 'No'),
			[Etichette] =(SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(IIF(ISJSON(Etichette) = 1, Etichette, NULL)) WITH (Nome VARCHAR(50) '$.Nome') j)
		FROM #righe
		ORDER BY [Data], Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
GO

-- ===== 27. uspServizi_get_Impegni_ByData_List (sql/procedures/uspServizi_get_Impegni_ByData_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_ByData_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdOsepe CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOsepe = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdOsepe IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdOsepe non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo NOT IN ('1H', 'IG', '1D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La risorsa deve essere tra le righe di Servizi > Impegni (stesso filtro di
		-- uspServizi_get_Impegni_List): persona o oggetto impiegabile dell'azienda del calendario
		-- del contesto, o condiviso tramite le Aree
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
				CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
			WHERE
				e.Id = @IdSessione
				AND u.Id = @IdOsepe
				AND
					(
						(
						u.IdDominio = e.IdDominio
						AND u.Condivisa = 1
						)
					OR u.IdSede = s.IdAziendaInterna
					)
				AND u.Tipo IN ('P', 'O')
				AND u.Disabilitata = 0
				AND u.ImpiegabileServizi = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		/*
		*   Cella di Servizi > Impegni
		*   1H = ora della vista Giorno (hh:00-hh:59), senza i servizi "In giornata"
		*   IG = colonna "In giornata" della vista Giorno
		*   1D = giorno delle viste Settimana e Mese, tutti i servizi del giorno
		*/
		-- Si leggono i servizi che iniziano nel giorno della cella: con la durata un servizio iniziato
		-- prima dell'ora della cella puo' occuparla (termina sempre entro la mezzanotte, uspServizi_upd)
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@DallaData AS DATE) AS SMALLDATETIME);
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @inizio));
		-- Ora della cella (1H): hh:00-hh:59
		DECLARE @oraInizio SMALLDATETIME = DATEADD(HOUR, DATEPART(HOUR, @DallaData), @inizio);
		DECLARE @oraFine SMALLDATETIME = DATEADD(HOUR, 1, @oraInizio);

		-- Solo i calendari delle sedi accessibili all'utente in cui la risorsa e' impiegata:
		-- i servizi degli altri calendari compaiono nella cella come "Occupato" ma non si elencano
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT DISTINCT e.IdCalendario
		FROM
			dbo.tblServiziOsepe o
			INNER JOIN dbo.tblServizi s ON o.Id = s.Id
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			o.IdOsepe = @IdOsepe
			AND e.IdTipo = 'V'
			AND e.Lock = 0;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		;WITH tbl AS (
			SELECT
				s.Id,
				StatoValore = CASE
					WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 1
					WHEN e.IdStato = 'A' THEN 2
					ELSE 0
				END,
				StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
				IdSerie = ISNULL(s2.Id, s.Id),
				Descrizione = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - ' + ISNULL(e.AvvisoTesto, ''),
				s.IdEvento,
				e.[Data],
				e.Ricorre,
				e.Eccezione
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.ufnEventi_get_List(@inizio, @fine, @IdCalendario, @IdTipo) e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
				-- Serie dell'occorrenza modificata (sostituto di un'eccezione): "Tutta la serie" apre la serie, non la sola occorrenza
				OUTER APPLY (
					SELECT TOP (1) s3.Id
					FROM dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
					WHERE
						zs.IdEvento = s.IdEvento
						AND zs.Lock = 0
						AND e.Ricorre = 0
				) s2
			WHERE
				o.IdOsepe = @IdOsepe
				AND e.IdStato <> 'A'
				AND
					(
					@IdIntervallo = '1D'
					OR
						(
						@IdIntervallo = '1H'
						AND ISNULL(e.InGiornata, 0) = 0
						-- Il servizio occupa l'ora se inizia prima della sua fine e finisce dopo il suo inizio;
						-- senza durata conta il solo minuto di inizio
						AND e.[Data] < @oraFine
						AND DATEADD(MINUTE, ISNULL(s.Durata, 1), e.[Data]) > @oraInizio
						)
					OR
						(
						@IdIntervallo = 'IG'
						AND ISNULL(e.InGiornata, 0) = 1
						)
					)
		)
		SELECT
			tbl.Id,
			tbl.StatoValore,
			tbl.StatoDescrizione,
			tbl.IdSerie,
			tbl.Descrizione,
			tbl.IdEvento,
			tbl.[Data],
			tbl.Ricorre,
			tbl.Eccezione,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		ORDER BY tbl.[Data], tbl.Id
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

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

-- ===== 28. uspServizi_get_Impegni_Elenco_List (sql/procedures/uspServizi_get_Impegni_Elenco_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_Elenco_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdOsepe CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Stato = ISNULL(NULLIF(LTRIM(RTRIM(@Stato)), ''), 'T');
		SET @IdOsepe = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo NOT IN ('1D', '1W', '2W', '1M', '2M', '6M', '1Y')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		/*
		*   Periodo: dalla data (00:00) per l'intervallo scelto, fine esclusa (1 giorno = il solo giorno della
		*   data, 1 settimana = 7 giorni). Il servizio termina entro la mezzanotte del giorno di inizio
		*   (uspServizi_upd): basta leggere i servizi che iniziano nel periodo
		*/
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@DallaData AS DATE) AS SMALLDATETIME);
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, CASE @IdIntervallo
			WHEN '1D' THEN DATEADD(DAY, 1, @inizio)
			WHEN '1W' THEN DATEADD(WEEK, 1, @inizio)
			WHEN '2W' THEN DATEADD(WEEK, 2, @inizio)
			WHEN '1M' THEN DATEADD(MONTH, 1, @inizio)
			WHEN '2M' THEN DATEADD(MONTH, 2, @inizio)
			WHEN '6M' THEN DATEADD(MONTH, 6, @inizio)
			ELSE DATEADD(YEAR, 1, @inizio)
		END);

		-- Azienda del calendario del contesto: senza calendario nessuna riga
		DECLARE @idAziendaInterna CHAR(16);
		SELECT @idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Risorse: le righe di Servizi > Impegni (stesso filtro di uspServizi_get_Impegni_List), eventualmente
		-- la sola risorsa indicata. Una risorsa che non e' tra queste non da' righe
		SELECT
			u.Id,
			u.Tipo,
			Risorsa = MAX(u.[Text])
		INTO #tRisorse
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
		WHERE
			e.Id = @IdSessione
			AND @idAziendaInterna IS NOT NULL
			AND (@IdOsepe IS NULL OR u.Id = @IdOsepe)
			AND
				(
					(
					u.IdDominio = e.IdDominio
					AND u.Condivisa = 1
					)
				OR u.IdSede = @idAziendaInterna
				)
			AND u.Tipo IN ('P', 'O')
			AND u.Disabilitata = 0
			AND u.ImpiegabileServizi = 1
		GROUP BY u.Id, u.Tipo;

		CREATE UNIQUE CLUSTERED INDEX IX_tRisorse_Id ON #tRisorse (Id);

		-- Calendari in cui le risorse sono impiegate, anche di sedi non accessibili all'utente: i loro servizi
		-- compaiono come "Occupato", senza descrizione, tipo ed etichette (come nelle celle degli Impegni)
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT DISTINCT e.IdCalendario
		FROM
			#tRisorse r
			INNER JOIN dbo.tblServiziOsepe o ON r.Id = o.IdOsepe
			INNER JOIN dbo.tblServizi s ON o.Id = s.Id
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE
			e.IdTipo = 'V'
			AND e.Lock = 0
			AND e.IdCalendario IS NOT NULL;

		-- Calendari con il dettaglio visibile: quelli delle sedi interne accessibili all'utente
		SELECT DISTINCT c.Id
		INTO #tCalendariVisibili
		FROM
			dbo.tblCalendari c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id IN (SELECT Id FROM @IdCalendario);

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		/*
		*   Una riga per risorsa e occorrenza del servizio, annullati esclusi (S9.3), in ordine di data e risorsa.
		*   Descrizione ed etichette si cercano solo nei servizi dei calendari visibili: un servizio "Occupato"
		*   non deve rivelare il suo contenuto attraverso la ricerca. Prima la pagina sulle chiavi, poi i dettagli
		*   (come uspServizi_get_List). Per le occorrenze generate stato ed etichette sono quelli della serie
		*/
		;WITH tbl AS (
			SELECT
				IdOsepe = r.Id,
				r.Risorsa,
				s.Id,
				IdEvento = e.Id,
				e.[Data],
				e.IdStato,
				e.Stato,
				e.InGiornata,
				e.Ricorre,
				e.Eccezione,
				e.Etichette,
				Visibile = IIF(v.Id IS NULL, 0, 1)
			FROM
				dbo.ufnEventi_get_List(@inizio, @fine, @IdCalendario, @IdTipo) e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
				INNER JOIN #tRisorse r ON o.IdOsepe = r.Id
				LEFT JOIN #tCalendariVisibili v ON e.IdCalendario = v.Id
			WHERE
				e.IdStato <> 'A'
				AND
					(
					@Stato = 'T'
					OR (@Stato = 'S' AND e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE())
					OR e.IdStato = @Stato
					)
				AND
					(
					@Search IS NULL
					OR (v.Id IS NOT NULL AND s.Descrizione LIKE '%' + @Search + '%')
					)
				AND
					(
					@Etichetta IS NULL
					OR
						(
						v.Id IS NOT NULL
						AND s.IdEvento IN (
							SELECT t.Id
							FROM
								dbo.tblEventiEtichette t
								INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id
							WHERE et.Nome LIKE '%' + @Etichetta + '%'
							)
						)
					)
		),
		pagina AS (
			SELECT
				tbl.*,
				RowsCount = COUNT(*) OVER ()
			FROM tbl
			ORDER BY tbl.[Data], tbl.Risorsa, tbl.IdOsepe, tbl.Id
			OFFSET @Offset ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
		)
		SELECT
			p.IdOsepe,
			TipoRisorsa = r.Tipo,
			p.Risorsa,
			p.Id,
			StatoValore = CASE
				WHEN p.IdStato IN ('D', 'I') AND p.[Data] < GETDATE() THEN 1
				ELSE 0
			END,
			StatoDescrizione = p.Stato + IIF(p.IdStato IN ('D', 'I') AND p.[Data] < GETDATE(), ' - Scaduto', ''),
			IdSerie = ISNULL(s2.Id, p.Id),
			p.IdEvento,
			p.[Data],
			InGiornata = CAST(ISNULL(p.InGiornata, 0) AS BIT),
			s.Durata,
			o.Quantita,
			Tipo = IIF(p.Visibile = 1, t.Nome, NULL),
			Descrizione = IIF(p.Visibile = 1, s.Descrizione, 'Occupato'),
			Etichette = IIF(p.Visibile = 1, p.Etichette, NULL),
			Visibile = CAST(p.Visibile AS BIT),
			p.Ricorre,
			p.Eccezione,
			p.RowsCount
		FROM
			pagina p
			INNER JOIN #tRisorse r ON p.IdOsepe = r.Id
			INNER JOIN dbo.tblServizi s ON p.Id = s.Id
			INNER JOIN dbo.tblServiziOsepe o ON p.Id = o.Id AND p.IdOsepe = o.IdOsepe
			INNER JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			-- Serie dell'occorrenza modificata (sostituto di un'eccezione): "Tutta la serie" apre la serie
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM
					dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = p.IdEvento
					AND zs.Lock = 0
					AND p.Ricorre = 0
			) s2
		ORDER BY p.[Data], p.Risorsa, p.IdOsepe, p.Id
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

-- ===== 29. uspServizi_get_Impegni_Eventi_List (sql/procedures/uspServizi_get_Impegni_Eventi_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_Eventi_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@AllaData SMALLDATETIME = NULL,
	@TipoRisorsa CHAR(1) = NULL,
	@Risorsa VARCHAR(50) = NULL,
	@PageNumber INT = NULL,
	@RowsPerPage INT = NULL
AS
-- Servizi > Impegni a blocchi (S9.9): una riga per risorsa e servizio da @DallaData (compresa) ad @AllaData (esclusa),
-- con i campi del calendario a blocchi (uspServizi_get_Calendario_Eventi_List). Stesse risorse e stessi servizi di
-- uspServizi_get_Impegni_Elenco_List (S9.2, S9.3): persone e oggetti impiegabili dell'azienda del calendario del
-- contesto, servizi di tutti i calendari in cui sono impiegate, annullati esclusi; quelli dei calendari non visibili
-- all'utente sono "Occupato" (Visibile = 0), senza descrizione, risorse e serie. Risorse = le altre persone e oggetti
-- del servizio (la risorsa della riga e' la colonna della vista). Le colonne (anche le risorse senza servizi) le da'
-- uspServizi_get_Impegni_List
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Filtro della finestra Cerca degli Impegni (S9.12): tipo di risorsa (P persone, O oggetti) e testo contenuto nel nome
		SET @TipoRisorsa = NULLIF(LTRIM(RTRIM(@TipoRisorsa)), '');
		SET @Risorsa = dbo.ufnStringhe_get_SenzaSpazi(@Risorsa, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL OR @AllaData IS NULL OR @AllaData <= @DallaData
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il periodo indicato non è valido';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Fine esclusa: ufnEventi_get_List prende gli estremi compresi
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, @AllaData);

		-- Azienda del calendario del contesto: senza calendario nessuna riga
		DECLARE @idAziendaInterna CHAR(16);
		SELECT @idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Risorse: le righe di Servizi > Impegni (stesso filtro di uspServizi_get_Impegni_List)
		SELECT
			u.Id,
			u.Tipo,
			Risorsa = MAX(u.[Text])
		INTO #tRisorse
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
		WHERE
			e.Id = @IdSessione
			AND @idAziendaInterna IS NOT NULL
			AND
				(
					(
					u.IdDominio = e.IdDominio
					AND u.Condivisa = 1
					)
				OR u.IdSede = @idAziendaInterna
				)
			AND u.Tipo IN ('P', 'O')
			AND u.Disabilitata = 0
			AND u.ImpiegabileServizi = 1
			AND (@TipoRisorsa IS NULL OR u.Tipo = @TipoRisorsa)
			AND (@Risorsa IS NULL OR u.[Text] LIKE '%' + @Risorsa + '%')
		GROUP BY u.Id, u.Tipo;

		-- Paracadute (S9.13): le risorse a pagine, @RowsPerPage per pagina nello stesso ordine delle righe (prima le
		-- persone, poi gli oggetti, per nome); senza @RowsPerPage tutte. Le altre si tolgono qui, prima di leggere i
		-- servizi, cosi' il carico e' quello della sola pagina
		DECLARE @risorseCount INT = (SELECT COUNT(*) FROM #tRisorse);
		IF ISNULL(@RowsPerPage, 0) > 0
		BEGIN
			SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
			DELETE r
			FROM
				#tRisorse r
				INNER JOIN (
					SELECT Id, Numero = ROW_NUMBER() OVER (ORDER BY IIF(Tipo = 'P', 0, 1), Risorsa, Id)
					FROM #tRisorse
				) n ON r.Id = n.Id
			WHERE n.Numero NOT BETWEEN (@PageNumber - 1) * @RowsPerPage + 1 AND @PageNumber * @RowsPerPage;
		END
		CREATE UNIQUE CLUSTERED INDEX IX_tRisorse_Id ON #tRisorse (Id);

		-- Calendari in cui le risorse sono impiegate, anche di sedi non accessibili all'utente ("Occupato")
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT DISTINCT e.IdCalendario
		FROM
			#tRisorse r
			INNER JOIN dbo.tblServiziOsepe o ON r.Id = o.IdOsepe
			INNER JOIN dbo.tblServizi s ON o.Id = s.Id
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE
			e.IdTipo = 'V'
			AND e.Lock = 0
			AND e.IdCalendario IS NOT NULL;

		-- Calendari con il dettaglio visibile: quelli delle sedi interne accessibili all'utente
		SELECT DISTINCT c.Id
		INTO #tCalendariVisibili
		FROM
			dbo.tblCalendari c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id IN (SELECT Id FROM @IdCalendario);

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SELECT
			IdOsepe = r.Id,
			TipoRisorsa = r.Tipo,
			r.Risorsa,
			s.Id,
			s.IdEvento,
			IdSerie = IIF(v.Id IS NULL, NULL, ISNULL(s2.Id, s.Id)),
			e.[Data],
			InGiornata = CAST(ISNULL(e.InGiornata, 0) AS BIT),
			s.Durata,
			Stato = CASE
				WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 'S'
				WHEN e.IdStato IN ('D', 'I') THEN 'D'
				ELSE e.IdStato
			END,
			StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			Descrizione = IIF(v.Id IS NULL, 'Occupato', ISNULL(NULLIF(CONCAT_WS(' - ', t.Nome, r0.NomeCompleto), ''), ISNULL(e.AvvisoTesto, ''))),
			Indirizzo = IIF(v.Id IS NULL, NULL, r0.IndirizzoCompleto),
			Risorse = IIF(v.Id IS NULL, NULL, a.Risorse),
			o.Quantita,
			Visibile = CAST(IIF(v.Id IS NULL, 0, 1) AS BIT),
			e.Ricorre,
			e.Eccezione
		FROM
			dbo.ufnEventi_get_List(@DallaData, @fine, @IdCalendario, @IdTipo) e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
			INNER JOIN #tRisorse r ON o.IdOsepe = r.Id
			LEFT JOIN #tCalendariVisibili v ON e.IdCalendario = v.Id
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblSedi r0 ON s.IdRichiedente = r0.Id
			-- Serie dell'occorrenza modificata (come uspServizi_get_ByData_List)
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM
					dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = s.IdEvento
					AND zs.Lock = 0
					AND e.Ricorre = 0
			) s2
			-- Le altre persone e oggetti del servizio (la risorsa della riga e' la colonna)
			OUTER APPLY (
				SELECT Risorse = STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY x.Tipo, n.Nome)
				FROM
					dbo.tblServiziOsepe so
					INNER JOIN dbo.tblOsepe x ON so.IdOsepe = x.Id
					CROSS APPLY (
						SELECT Nome = p.NomeCompleto FROM dbo.tblPersone p WHERE p.Id = so.IdOsepe AND x.Tipo = 'P'
						UNION ALL
						SELECT Nome = g.Nome FROM dbo.tblOggetti g WHERE g.Id = so.IdOsepe AND x.Tipo = 'O'
					) n
				WHERE
					so.Id = s.Id
					AND so.IdOsepe <> o.IdOsepe
			) a
		WHERE e.IdStato <> 'A'
		ORDER BY r.Risorsa, r.Id, e.[Data], s.Id
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

-- ===== 30. uspServizi_get_Impegni_List (sql/procedures/uspServizi_get_Impegni_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdVista CHAR(1) = NULL,
	@TipoRisorsa CHAR(1) = NULL,
	@Risorsa VARCHAR(50) = NULL,
	@PageNumber INT = NULL,
	@RowsPerPage INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Filtro della finestra Cerca degli Impegni (S9.12): tipo di risorsa (P persone, O oggetti) e testo contenuto nel nome
		SET @TipoRisorsa = NULLIF(LTRIM(RTRIM(@TipoRisorsa)), '');
		SET @Risorsa = dbo.ufnStringhe_get_SenzaSpazi(@Risorsa, 0, 1);
		SET @IdVista = NULLIF(LTRIM(RTRIM(@IdVista)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdVista IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdVista non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdVista NOT IN ('G', 'S', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdVista non è valido';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		/*
		*   Periodo della vista
		*   G = Giorno     → dalle 00:00 alle 23:59 del giorno, una colonna per ora + "In giornata"
		*   S = Settimana  → dal lunedi' alla domenica della settimana della data, una colonna per giorno
		*   M = Mese       → dal primo all'ultimo giorno del mese della data, una colonna per giorno
		*/
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@DallaData AS DATE) AS SMALLDATETIME);
		IF @IdVista = 'S'
			SET @inizio = DATEADD(DAY, 1 - DATEPART(DW, @inizio), @inizio);
		ELSE IF @IdVista = 'M'
			SET @inizio = DATEFROMPARTS(YEAR(@inizio), MONTH(@inizio), 1);

		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, CASE @IdVista
			WHEN 'G' THEN DATEADD(DAY, 1, @inizio)
			WHEN 'S' THEN DATEADD(DAY, 7, @inizio)
			ELSE DATEADD(MONTH, 1, @inizio)
		END);

		-- Azienda del calendario del contesto: senza calendario nessuna riga
		DECLARE @idAziendaInterna CHAR(16);
		SELECT @idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Risorse (righe): persone e oggetti impiegabili nei servizi dell'azienda del calendario,
		-- compresi quelli condivisi tramite le Aree (stesso filtro di uspOsepe_get_SelectList
		-- con @Contesto = 5 e @ImpiegabileServizi = 1)
		SELECT
			u.Id,
			u.Tipo,
			Risorsa = MAX(u.[Text])
		INTO #tRisorse
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
		WHERE
			e.Id = @IdSessione
			AND @idAziendaInterna IS NOT NULL
			AND
				(
					(
					u.IdDominio = e.IdDominio
					AND u.Condivisa = 1
					)
				OR u.IdSede = @idAziendaInterna
				)
			AND u.Tipo IN ('P', 'O')
			AND u.Disabilitata = 0
			AND u.ImpiegabileServizi = 1
			AND (@TipoRisorsa IS NULL OR u.Tipo = @TipoRisorsa)
			AND (@Risorsa IS NULL OR u.[Text] LIKE '%' + @Risorsa + '%')
		GROUP BY u.Id, u.Tipo;

		-- Paracadute (S9.13): le risorse a pagine, @RowsPerPage per pagina nello stesso ordine delle righe (prima le
		-- persone, poi gli oggetti, per nome); senza @RowsPerPage tutte. Le altre si tolgono qui, prima di leggere i
		-- servizi, cosi' il carico e' quello della sola pagina
		DECLARE @risorseCount INT = (SELECT COUNT(*) FROM #tRisorse);
		IF ISNULL(@RowsPerPage, 0) > 0
		BEGIN
			SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
			DELETE r
			FROM
				#tRisorse r
				INNER JOIN (
					SELECT Id, Numero = ROW_NUMBER() OVER (ORDER BY IIF(Tipo = 'P', 0, 1), Risorsa, Id)
					FROM #tRisorse
				) n ON r.Id = n.Id
			WHERE n.Numero NOT BETWEEN (@PageNumber - 1) * @RowsPerPage + 1 AND @PageNumber * @RowsPerPage;
		END
		CREATE UNIQUE CLUSTERED INDEX IX_tRisorse_Id ON #tRisorse (Id);

		-- Calendari in cui le risorse sono impiegate: tutti, anche quelli di sedi non accessibili
		-- all'utente, perche' l'impegno della risorsa sia completo (i servizi di quei calendari
		-- contano come "Occupato", senza descrizione)
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT DISTINCT e.IdCalendario
		FROM
			#tRisorse r
			INNER JOIN dbo.tblServiziOsepe o ON r.Id = o.IdOsepe
			INNER JOIN dbo.tblServizi s ON o.Id = s.Id
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE
			e.IdTipo = 'V'
			AND e.Lock = 0
			AND e.IdCalendario IS NOT NULL;

		-- Calendari con il dettaglio visibile: quelli delle sedi interne accessibili all'utente
		SELECT DISTINCT c.Id
		INTO #tCalendariVisibili
		FROM
			dbo.tblCalendari c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id IN (SELECT Id FROM @IdCalendario);

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		-- Servizi del periodo per risorsa, annullati esclusi. La colonna (Data) e' l'inizio della
		-- cella: l'ora (hh:00) nella vista Giorno, il giorno (00:00) nelle viste Settimana e Mese;
		-- nella vista Giorno i servizi "In giornata" vanno nella colonna dedicata (InGiornata = 1).
		-- Durata (minuti, facoltativa): nella vista Giorno il servizio occupa ogni ora che tocca, dall'ora
		-- di inizio a quella dell'ultimo minuto (h); senza durata la sola ora di inizio. Il servizio
		-- termina entro la mezzanotte del giorno di inizio (uspServizi_upd), quindi resta nel suo giorno e
		-- basta leggere i servizi che iniziano nel periodo. Durata del servizio di una serie: e' quella
		-- della serie (s.IdEvento = e.Id, l'Id della serie per le occorrenze generate)
		SELECT
			IdOsepe = r.Id,
			[Data] = CASE
				WHEN @IdVista = 'G' AND ISNULL(e.InGiornata, 0) = 0
					THEN DATEADD(HOUR, h.value, CAST(CAST(e.[Data] AS DATE) AS SMALLDATETIME))
				ELSE CAST(CAST(e.[Data] AS DATE) AS SMALLDATETIME)
			END,
			InGiornata = CAST(IIF(@IdVista = 'G' AND ISNULL(e.InGiornata, 0) = 1, 1, 0) AS BIT),
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Minuti = ISNULL(s.Durata, 0),
			Testo = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - '
				+ IIF(v.Id IS NULL, 'Occupato', ISNULL(e.AvvisoTesto, '')),
			-- Occorrenza del servizio (le occorrenze generate di una serie hanno lo stesso servizio e date diverse)
			-- con l'orario vero, per le sovrapposizioni: senza durata conta il solo minuto di inizio;
			-- i servizi "In giornata" non hanno un'ora e non si confrontano (Oraria = 0)
			IdServizio = s.Id,
			Inizio = e.[Data],
			Fine = DATEADD(MINUTE, ISNULL(s.Durata, 1), e.[Data]),
			Oraria = IIF(ISNULL(e.InGiornata, 0) = 0, 1, 0),
			Sovrapposto = 0
		INTO #tEventi
		FROM
			dbo.ufnEventi_get_List(@inizio, @fine, @IdCalendario, @IdTipo) e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
			INNER JOIN #tRisorse r ON o.IdOsepe = r.Id
			LEFT JOIN #tCalendariVisibili v ON e.IdCalendario = v.Id
			-- Ore occupate nella vista Giorno (una riga per ora); nelle altre viste e per "In giornata" una sola riga
			CROSS APPLY GENERATE_SERIES(
				DATEPART(HOUR, e.[Data]),
				IIF(@IdVista = 'G' AND ISNULL(e.InGiornata, 0) = 0 AND s.Durata IS NOT NULL,
					DATEPART(HOUR, DATEADD(MINUTE, s.Durata - 1, e.[Data])),
					DATEPART(HOUR, e.[Data]))) h
		WHERE e.IdStato <> 'A';

		-- Sovrapposizioni vere: nella stessa cella un servizio e' sovrapposto se un altro servizio della risorsa
		-- inizia prima della sua fine e finisce dopo il suo inizio. Due servizi in fila nella stessa ora
		-- (09:00-09:30 e 09:30-10:00) contano come 2 eventi ma non sono sovrapposti
		UPDATE a
		SET Sovrapposto = 1
		FROM #tEventi a
		WHERE
			a.Oraria = 1
			AND EXISTS (
				SELECT 1
				FROM #tEventi b
				WHERE
					b.IdOsepe = a.IdOsepe
					AND b.[Data] = a.[Data]
					AND b.InGiornata = a.InGiornata
					AND b.Oraria = 1
					AND NOT (b.IdServizio = a.IdServizio AND b.Inizio = a.Inizio)
					AND b.Inizio < a.Fine
					AND a.Inizio < b.Fine
			);

		SELECT
			r.Id AS IdOsepe,
			r.Tipo,
			r.Risorsa,
			d.[Data],
			InGiornata = ISNULL(d.InGiornata, CAST(0 AS BIT)),
			Eventi = ISNULL(d.Eventi, 0),
			Scaduti = ISNULL(d.Scaduti, 0),
			Eseguiti = ISNULL(d.Eseguiti, 0),
			Minuti = ISNULL(d.Minuti, 0),
			Sovrapposti = ISNULL(d.Sovrapposti, 0),
			d.Testo,
			-- Tutte le risorse del filtro, per l'indicatore delle pagine
			RisorseCount = @risorseCount
		FROM
			#tRisorse r
			LEFT JOIN (
				SELECT
					IdOsepe,
					[Data],
					InGiornata,
					Eventi = COUNT(*),
					Scaduti = SUM(Scaduto),
					Eseguiti = SUM(Eseguito),
					-- Somma delle durate indicate (viste Settimana e Mese: ore impegnate nel giorno)
					Minuti = SUM(Minuti),
					-- Servizi della cella che si accavallano davvero con un altro
					Sovrapposti = SUM(Sovrapposto),
					-- Usato dalla cella solo quando c'e' un servizio
					Testo = MAX(Testo)
				FROM #tEventi
				GROUP BY IdOsepe, [Data], InGiornata
			) d ON r.Id = d.IdOsepe
		ORDER BY IIF(r.Tipo = 'P', 0, 1), r.Risorsa, r.Id, d.InGiornata DESC, d.[Data];

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

-- ===== 31. uspServizi_get_List (sql/procedures/uspServizi_get_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);

		-- Periodo esatto: dalla data (00:00) per l'intervallo, fine esclusa (1 giorno = il solo giorno della data,
		-- 1 settimana = 7 giorni), come uspServizi_get_Impegni_Elenco_List. Fino al 2026-11-22 arrivava alla fine
		-- del giorno dopo l'intervallo (docs/regole/scadenze-servizi.md S4.7.5)
		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, CASE
			WHEN @IdIntervallo = '1W' THEN DATEADD(WEEK, 1, @DallaData)
			WHEN @IdIntervallo = '2W' THEN DATEADD(WEEK, 2, @DallaData)
			WHEN @IdIntervallo = '1M' THEN DATEADD(MONTH, 1, @DallaData)
			WHEN @IdIntervallo = '2M' THEN DATEADD(MONTH, 2, @DallaData)
			WHEN @IdIntervallo = '6M' THEN DATEADD(MONTH, 6, @DallaData)
			WHEN @IdIntervallo = '1Y' THEN DATEADD(YEAR, 1, @DallaData)
			ELSE DATEADD(DAY, 1, @DallaData)
		END);

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage  INT,
            @Offset       INT,
            @IdSessione   CHAR(16),
            @IdIntervallo CHAR(2),
            @DallaData    SMALLDATETIME,
            @AllaData     SMALLDATETIME,
            @Stato        CHAR(1),
            @Etichetta    VARCHAR(50),
            @Search       VARCHAR(50),
            @IdCalendario tvpId_char_16 READONLY,
            @IdTipo       tvpId_char_1  READONLY';

		/*
		*   Prima la pagina, poi i dettagli: la ricerca (tbl) e la paginazione (pagina) usano solo le chiavi
		*   dell'occorrenza (servizio, evento, data); stato, tipo, richiedente, etichette e serie si leggono solo
		*   per le righe della pagina. Con molte serie un anno di occorrenze sono decine di migliaia di righe
		*   (prova del 2026-11-21: 78.000 occorrenze da circa 4 s a circa 1,4 s). Per le occorrenze generate stato,
		*   ricorrenza ed etichette sono quelli dell'evento della serie (IdEvento), come in ufnEventi_get_List.
		*   Ordine stabile per data e Id, cosi le pagine non ripetono e non saltano righe con la stessa data.
		*/
		SET @stmt = N'
        WITH tbl AS (
            SELECT
                s.Id,
                s.IdEvento,
                e.[Data]
            FROM
                dbo.tblServizi s
                INNER JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
                INNER JOIN dbo.tblTipi t ON s.IdTipo        = t.Id
                INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
                    ON s.IdEvento = e.Id
            WHERE 1 = 1';

		IF @Search IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.Descrizione LIKE ''%'' + @Search + ''%''';

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.IdEvento IN (
                    SELECT t.Id FROM dbo.tblEventiEtichette t
                    INNER JOIN dbo.tblEtichette e ON t.IdEtichetta = e.Id
                    WHERE e.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Stato <> 'T'
		BEGIN
			IF @Stato = 'S'
				SET @stmt = @stmt + N'
                    AND (e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE())';
			ELSE
				SET @stmt = @stmt + N'
                    AND e.IdStato = @Stato';
		END

		SET @stmt = @stmt + N'
        ),
        pagina AS (
            SELECT
                tbl.Id,
                tbl.IdEvento,
                tbl.[Data],
                RowsCount = COUNT(*) OVER ()
            FROM tbl
            ORDER BY tbl.[Data], tbl.Id
            OFFSET @Offset ROWS
            FETCH NEXT @RowsPerPage ROWS ONLY
        )
        SELECT
            p.Id,
            StatoValore = CASE
                WHEN ev.IdStato IN (''D'', ''I'') AND p.[Data] < GETDATE() THEN 1
                WHEN ev.IdStato = ''A''                                      THEN 2
                ELSE 0
            END,
            StatoDescrizione = st.Nome + IIF(ev.IdStato IN (''D'', ''I'') AND p.[Data] < GETDATE(), '' - Scaduto'', ''''),
            IdSerie          = ISNULL(s2.Id, p.Id),
            Tipo             = t.Nome,
            s.Descrizione,
            Richiedente      = r.NomeCompleto + '' - '' + r.IndirizzoCompleto,
            p.IdEvento,
            p.[Data],
            Ricorre          = CAST(IIF(ri.Id IS NULL, 0, 1) AS BIT),
            Eccezione        = CAST(IIF(EXISTS (
                                   SELECT 1
                                   FROM dbo.tblRicorrenzeEccezioni z
                                   WHERE z.Id = p.IdEvento AND z.Lock = 0
                               ), 1, 0) AS BIT),
            -- Copia delle etichette sull evento (tblEventi.Etichette, come nelle Scadenze), non la funzione per ogni riga
            Etichette        = ev.Etichette,
            s.Durata,
            p.RowsCount
        FROM
            pagina p
            INNER JOIN dbo.tblServizi s ON p.Id = s.Id
            INNER JOIN dbo.tblEventi ev ON p.IdEvento = ev.Id
            INNER JOIN dbo.tblEventiStati st ON ev.IdStato = st.Id
            INNER JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
            INNER JOIN dbo.tblTipi t ON s.IdTipo = t.Id
            LEFT JOIN dbo.tblRicorrenze ri ON p.IdEvento = ri.Id
            -- Serie della occorrenza modificata (sostituto di una eccezione): con Tutta la serie si apre la serie
            OUTER APPLY (
                SELECT TOP (1) s3.Id
                FROM dbo.tblRicorrenzeEccezioni zs
                INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
                WHERE zs.IdEvento = p.IdEvento AND zs.Lock = 0 AND ri.Id IS NULL
            ) s2
        ORDER BY p.[Data], p.Id;';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Stato = @Stato,
			@Etichetta = @Etichetta,
			@Search = @Search,
			@IdCalendario = @IdCalendario,
			@IdTipo = @IdTipo;

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

-- ===== 32. uspServizi_get_Stampa (sql/procedures/uspServizi_get_Stampa.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stampa del servizio (Rapporto di intervento): dati del servizio con il layout di stampa dell'azienda della sede del
-- calendario (ufnSediReport_get_Layout). Si stampa con la funzione SRV (Servizi, dalle pagine del calendario)
-- oppure, con la sola SRA (Servizi assegnati), solo un servizio assegnato all'utente della sessione. Si stampa il
-- servizio salvato, non la bozza né la serie ricorrente (si stampa l'occorrenza modificata, come per l'esecuzione).
-- "Eseguito da" sono gli utenti assegnati. Proprietà del tipo e persone e oggetti collegati sono in
-- uspServizi_get_Stampa_Proprieta e uspServizi_get_Stampa_Collegati
CREATE OR ALTER PROCEDURE dbo.uspServizi_get_Stampa
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @assegnato BIT;
		DECLARE @lock TINYINT;
		DECLARE @idEvento CHAR(16);

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

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		-- Servizio assegnato all'utente della sessione: con la sola SRA si stampano solo questi
		SET @assegnato = IIF(EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventiUtenti u ON s.IdEvento = u.Id
				INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente
			WHERE
				s.Id = @Id
				AND ss.Id = @IdSessione
		), 1, 0);

		-- Calendario di una sede accessibile e permesso SRV, oppure SRA sul servizio assegnato
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		   OR NOT (@permessoSrv >= 1 OR (@permessoSra >= 1 AND @assegnato = 1))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			@lock = e.Lock,
			@idEvento = e.Id
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE s.Id = @Id;

		IF @lock > 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Servizio non trovato o già eliminato';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio non è ancora salvato: salvarlo prima di stamparlo';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM dbo.tblRicorrenze
		WHERE Id = @idEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio ricorrente non si stampa: per stampare un''occorrenza, modificare la sola occorrenza';
			GOTO BRANCH_END;
		END

		SELECT
			Tipo = t.Nome,
			e.[Data],
			e.InGiornata,
			s.Durata,
			s.DataRichiesta,
			Stato = st.Nome,
			s.Descrizione,
			RichiedenteNome = sr.NomeCompleto,
			RichiedenteIndirizzo = sr.IndirizzoCompleto,
			RichiedenteCodiceFiscale = sr.CodiceFiscale,
			RichiedentePartitaIva = sr.PartitaIva,
			-- Nome e cognome dell'utente, oppure l'email se non li ha (come nella finestra Assegna)
			EseguitoDa = (
				SELECT STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY n.Nome)
				FROM
					dbo.tblEventiUtenti eu
					INNER JOIN dbo.tblUtenti ut ON eu.IdUtente = ut.Id
					CROSS APPLY (SELECT Nome = ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(ut.Nome, '') + ' ' + ISNULL(ut.Cognome, ''))), ''), ut.Email)) n
				WHERE eu.Id = e.Id),
			FirmaRichiedente = (
				SELECT f.Firma
				FROM
					dbo.tblEventiFirme ef
					INNER JOIN dbo.tblFirme f ON ef.IdFirma = f.Id
				WHERE
					ef.Id = e.Id
					AND ef.IdTipo = 'R'
			),
			r.IdLayout,
			r.Intestazione,
			r.PiePagina,
			r.IntestazioneColore,
			r.IntestazioneFontSize,
			r.IntestazioneAllineamento,
			r.PiePaginaColore,
			r.PiePaginaFontSize,
			r.PiePaginaAllineamento,
			r.Logo
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			CROSS APPLY dbo.ufnSediReport_get_Layout(ISNULL(sc.IdParent, sc.Id)) r
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblEventiStati st ON e.IdStato = st.Id
			LEFT JOIN dbo.tblSedi sr ON s.IdRichiedente = sr.Id
		WHERE s.Id = @Id;

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

-- ===== 33. uspServizi_ins (sql/procedures/uspServizi_ins.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_ins]
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL,
	@OccorrenzaESuccessive BIT = 0
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
			SET @returnMessage = 'Il parametro @IdSessione non puo'' essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (SRV = Gestione Servizi)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Legge il calendario: dalla sessione per nuovi servizi, dall'evento per ricorrenti
		DECLARE @idCalendario CHAR(16);
		IF @IdEvento IS NULL
			SELECT @idCalendario = s.IdCalendario
			FROM dbo.tblSessioni s
			INNER JOIN dbo.tblCalendari c ON s.IdCalendario = c.Id
											   AND c.IdModulo = 'SRV'
			WHERE s.Id = @IdSessione;
		ELSE
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblEventi e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
						   ON c.IdSede = i.Id
				WHERE e.Id = @IdEvento)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			SELECT @idCalendario = IdCalendario
			FROM dbo.tblEventi
			WHERE Id = @IdEvento;
		END

		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END

		-- Genera i nuovi Id FUORI dalla transazione:
		-- uspId_get gestisce la propria transazione internamente
		DECLARE @returnIdEvento CHAR(16) = NULL;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			IF @IdEvento IS NULL
			BEGIN
				-- Nuovo servizio da zero
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Lock)
				VALUES
					(@returnIdEvento, @idCalendario, 'D', 'V', @Data, 0, 0, 2);

				INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo)
				VALUES (@returnId, @returnIdEvento, @IdTipo);
			END
			ELSE
			BEGIN
				-- Nuova occorrenza da evento ricorrente esistente: copia i dati
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Etichette, Lock)
				SELECT
					@returnIdEvento, @idCalendario, 'D', 'V', @Data,
					InGiornata, AvvisoAnticipo, Email, Etichette, 2
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				-- Copia le proprieta dell'evento originale
				INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @returnIdEvento, IdProprieta, Valore
				FROM dbo.tblEventiProprieta
				WHERE Id = @IdEvento;

				-- Copia le etichette dell'evento originale
				INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
				SELECT @returnIdEvento, IdEtichetta
				FROM dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				IF @OccorrenzaESuccessive = 1
				BEGIN
					-- Copia la ricorrenza dell'evento originale
					-- Con un numero di ripetizioni la nuova serie ha solo quelle rimaste: si tolgono le occorrenze della
					-- serie originale prima di @Data (n = posizione dell'occorrenza), altrimenti la serie si allungherebbe
					-- (7 volte dall'8 divisa al 12 = 12, 13, 14, non 7 volte dal 12)
					INSERT INTO dbo.tblRicorrenze
						(Id, IdParent, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
					SELECT
						@returnIdEvento, @IdEvento,
						r.IdIntervallo, r.Frequenza, r.DataFine,
						IIF(r.Ripetizioni > 0, IIF(r.Ripetizioni - n.Precedenti < 1, 1, r.Ripetizioni - n.Precedenti), r.Ripetizioni),
						r.Relativo
					FROM
						dbo.tblRicorrenze r
						INNER JOIN dbo.tblEventi e ON r.Id = e.Id
						CROSS APPLY (
							SELECT Precedenti = ISNULL(CASE r.IdIntervallo
								WHEN 'DD' THEN DATEDIFF(DAY, e.[Data], @Data) / NULLIF(r.Frequenza, 0)
								WHEN 'WK' THEN DATEDIFF(DAY, e.[Data], @Data) / NULLIF(7 * r.Frequenza, 0)
								WHEN 'MM' THEN DATEDIFF(MONTH, e.[Data], @Data) / NULLIF(r.Frequenza, 0)
								WHEN 'YY' THEN DATEDIFF(YEAR, e.[Data], @Data) / NULLIF(r.Frequenza, 0)
								ELSE 0
							END, 0)
						) n
					WHERE r.Id = @IdEvento;
				END
				ELSE
				BEGIN
					-- Aggiunge un'eccezione per questa singola occorrenza
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE
						Id = @IdEvento
						AND [Data] = @Data;

					INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
					VALUES (@IdEvento, @Data, @returnIdEvento, 2);
				END

				-- Copia il servizio originale (TOP 1: relazione 1:1 evento-servizio)
				INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata)
				SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata
				FROM dbo.tblServizi
				WHERE IdEvento = @IdEvento;

				-- Copia gli Osepe del servizio originale con la loro quantità (serve al prezzo per risorsa)
				INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
				SELECT @returnId, o.IdOsepe, o.Quantita
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
				WHERE s.IdEvento = @IdEvento;
			END

		COMMIT TRANSACTION;

		SELECT @returnId AS Id;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
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

-- ===== 34. uspServizi_ins_Osepe (sql/procedures/uspServizi_ins_Osepe.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_ins_Osepe]
	@Id CHAR(16) = NULL,
	@IdOsepe CHAR(16) = NULL,
	@Quantita DECIMAL(18,4) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdOsepe = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdOsepe IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdOsepe non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Quantita non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (SRV = Gestione Servizi)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La risorsa deve essere tra quelle che la scheda propone (uspOsepe_get_SelectList con @Contesto = 5 e
		-- @ImpiegabileServizi = 1): persona o oggetto impiegabile nei servizi, non disabilitato, dell'azienda del
		-- calendario del servizio o condiviso tramite le Aree. Una risorsa gia' nel servizio resta modificabile
		-- (quantita') anche se nel frattempo non e' piu' impiegabile
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServiziOsepe
			WHERE
				Id = @Id
				AND IdOsepe = @IdOsepe
		)
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.tblSedi d ON c.IdSede = d.Id
				CROSS JOIN dbo.tblSessioni n
				CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(n.IdUtente) u
			WHERE
				s.Id = @Id
				AND n.Id = @IdSessione
				AND u.Id = @IdOsepe
				AND
					(
						(
						u.IdDominio = n.IdDominio
						AND u.Condivisa = 1
						)
					OR u.IdSede = d.IdAziendaInterna
					)
				AND u.Tipo IN ('P', 'O')
				AND u.Disabilitata = 0
				AND u.ImpiegabileServizi = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La persona o l''oggetto indicato non è impiegabile nei servizi';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Upsert: DELETE + INSERT per evitare duplicati su PK (Id, IdOsepe)
			DELETE dbo.tblServiziOsepe
			WHERE
				Id = @Id
				AND IdOsepe = @IdOsepe;

			INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
			VALUES (@Id, @IdOsepe, @Quantita);
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione: uspId_upd gestisce la propria transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
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

-- ===== 35. uspServizi_upd (sql/procedures/uspServizi_upd.sql)
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@DataRichiesta SMALLDATETIME = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@FirmaRichiedente IMAGE = NULL,
	@FirmaEsecutore IMAGE = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Durata INT = NULL,
	@Ricorre BIT = 0,
	@Avviso BIT = 0,
	@AvvisoAnticipo INT = 0,
	@Email VARCHAR(1000) = NULL,
	@IdEtichette VARCHAR(50) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@Frequenza INT = NULL,
	@DataFine SMALLDATETIME = NULL,
	@Ripetizioni INT = NULL,
	@Relativo INT = 0,
	@OccorrenzaESuccessive BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;
		DECLARE @frequenzaMax INT = 0;
		DECLARE @minuti INT;
		DECLARE @idEventoParent CHAR(16);
		DECLARE @dataFineParent SMALLDATETIME;
		DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
		DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;
		DECLARE @idTipo CHAR(16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdRichiedente = NULLIF(LTRIM(RTRIM(@IdRichiedente)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @Email = dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1);

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
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE
				s.Id = @Id
				AND e.Id = @IdEvento
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblServizi
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Durata in minuti, facoltativa (NULL = non indicata): il servizio termina entro la mezzanotte del giorno di
		-- inizio, cosi' non occupa il giorno successivo (vale anche per le occorrenze della serie, alla stessa ora).
		-- "In giornata" non ha un'ora precisa: la durata arriva a 24 ore, qualunque sia l'ora rimasta nella data
		IF @Durata IS NOT NULL AND @Durata <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La durata del servizio deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @Durata IS NOT NULL
		   AND DATEADD(MINUTE, @Durata, IIF(ISNULL(@InGiornata, 0) = 1, CAST(CAST(@Data AS DATE) AS DATETIME), CAST(@Data AS DATETIME)))
			   > DATEADD(DAY, 1, CAST(CAST(@Data AS DATE) AS DATETIME))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: ridurre la durata o anticipare l''ora';
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND EXISTS (SELECT 1
		FROM dbo.tblEventiUtenti
		WHERE Id = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio assegnato non può essere ricorrente';
			GOTO BRANCH_END;
		END

		-- Limiti della serie: le date ammesse dall'applicazione (ufnDate_get_Min / _Max = Constants.SQL.MinDate / MaxDate)
		IF @Ricorre = 1 AND @Data < dbo.ufnDate_get_Min()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data minima per i servizi ricorrenti è il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND @DataFine IS NOT NULL AND @DataFine < @Data
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine della serie non può essere inferiore alla data di inizio';
			GOTO BRANCH_END;
		END

		-- La serie è solo pianificazione: si esegue (e si fattura) l'occorrenza modificata, che è un
		-- servizio a sé. Serie = ricorrenza propria (casella Ricorre o "Questa e le successive"), mai
		-- l'occorrenza modificata, che è il sostituto di un'eccezione della serie
		IF @IdStato = 'E'
		   AND (@Ricorre = 1 OR @OccorrenzaESuccessive = 1)
		   AND NOT EXISTS (SELECT 1
		FROM dbo.tblRicorrenzeEccezioni
		WHERE IdEvento = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio ricorrente non può essere eseguito: per segnare come eseguita un''occorrenza, modificare la sola occorrenza';
			GOTO BRANCH_END;
		END

		IF @IdIntervallo = 'YY'
		BEGIN
			SET @frequenzaMax = DATEDIFF(YEAR, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' anni';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @IdIntervallo = 'MM'
		BEGIN
			SET @frequenzaMax = DATEDIFF(MONTH, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' mesi';
				GOTO BRANCH_END;
			END
		END

		IF @FirmaRichiedente IS NOT NULL
			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

		IF @FirmaEsecutore IS NOT NULL
			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

		BEGIN TRANSACTION;

			-- Gestione ricorrenze
			IF EXISTS (SELECT 1
			FROM dbo.tblRicorrenze
			WHERE Id = @IdEvento)
			   AND @OccorrenzaESuccessive = 0
			BEGIN
				IF @Ricorre = 0
				BEGIN
					DELETE dbo.tblRicorrenze
					WHERE Id = @IdEvento;
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE Id = @IdEvento;
				END
				ELSE
				BEGIN
					IF EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenze
						WHERE
							Id = @IdEvento
							AND
								(
								IdIntervallo <> @IdIntervallo
								OR Frequenza <> @Frequenza
								OR Relativo <> @Relativo
								)
					)
						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @IdEvento
							AND IdEvento IS NULL;

					SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
					FROM dbo.tblEventi
					WHERE Id = @IdEvento;

					IF ISNULL(@minuti, 0) <> 0
						UPDATE dbo.tblRicorrenzeEccezioni
						SET [Data] = DATEADD(MINUTE, @minuti, [Data])
						WHERE Id = @IdEvento;

					UPDATE dbo.tblRicorrenze
					SET
						IdIntervallo = @IdIntervallo,
						Frequenza = @Frequenza,
						DataFine = @DataFine,
						Ripetizioni = @Ripetizioni,
						Relativo = @Relativo
					WHERE Id = @IdEvento;
				END
			END
			ELSE IF @Ricorre = 1 AND @OccorrenzaESuccessive = 0
			BEGIN
				INSERT dbo.tblRicorrenze
					(Id, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
				VALUES
					(@IdEvento, @IdIntervallo, @Frequenza, @DataFine, @Ripetizioni, @Relativo);
			END
			ELSE IF @OccorrenzaESuccessive = 1
			BEGIN
				SELECT @idEventoParent = IdParent
				FROM dbo.tblRicorrenze
				WHERE Id = @IdEvento;

				-- La serie originale finisce il giorno prima dell'occorrenza scelta (la data della nuova serie
				-- prima del salvataggio, scritta da uspServizi_ins), anche se la nuova serie viene spostata
				SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				SET @dataFineParent =
					DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
						DATEADD(DAY, DATEDIFF(DAY, 0, DATEADD(MINUTE, -ISNULL(@minuti, 0), @Data)), -1)));

				UPDATE dbo.tblRicorrenze
				SET
					DataFine = @dataFineParent,
					Ripetizioni = 0
				WHERE Id = @idEventoParent;

				UPDATE dbo.tblRicorrenze
				SET
					IdIntervallo = @IdIntervallo,
					Frequenza = @Frequenza,
					DataFine = @DataFine,
					Ripetizioni = @Ripetizioni,
					Relativo = @Relativo
				WHERE Id = @IdEvento;

				-- Le occorrenze cancellate o modificate della serie originale dalla data scelta in poi passano alla
				-- nuova serie, spostate come la nuova serie (stessa regola della modifica di tutta la serie):
				-- cancellate, una cancellata ricomparirebbe e una modificata sarebbe doppia. Se cambia la frequenza
				-- le date non coincidono piu': passano solo le occorrenze modificate (eventi a se', S5.4)
				INSERT dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				SELECT @IdEvento, DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data]), z.IdEvento, z.Lock
				FROM
					dbo.tblRicorrenzeEccezioni z
					INNER JOIN dbo.tblRicorrenze p ON z.Id = p.Id
				WHERE
					z.Id = @idEventoParent
					AND z.[Data] > @dataFineParent
					AND
						(
						z.IdEvento IS NOT NULL
						OR
							(
							p.IdIntervallo = @IdIntervallo
							AND p.Frequenza = @Frequenza
							AND p.Relativo = @Relativo
							)
						)
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenzeEccezioni y
						WHERE
							y.Id = @IdEvento
							AND y.[Data] = DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data])
					);

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @idEventoParent
					AND [Data] > @dataFineParent;
			END

			-- Sblocca l'eccezione di ricorrenza che referenzia questo evento come sostituto
			-- (occorrenza singola modificata): senza questo sblocco l'occorrenza originale
			-- resta visibile in calendario insieme a quella modificata. No-op se @IdEvento
			-- non e' il sostituto di nessuna eccezione.
			UPDATE dbo.tblRicorrenzeEccezioni
			SET Lock = 0
			WHERE
				IdEvento = @IdEvento
				AND Lock <= 2;

			-- Gestione firma richiedente
			IF @FirmaRichiedente IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'R';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaRichiedente;
			END
			ELSE IF @idFirmaRichiedente IS NULL
			BEGIN
				SET @idFirmaRichiedente = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaRichiedente, @FirmaRichiedente);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaRichiedente, 'R');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaRichiedente
				WHERE Id = @idFirmaRichiedente;

			-- Gestione firma esecutore
			IF @FirmaEsecutore IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'E';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaEsecutore;
			END
			ELSE IF @idFirmaEsecutore IS NULL
			BEGIN
				SET @idFirmaEsecutore = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaEsecutore, @FirmaEsecutore);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaEsecutore, 'E');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaEsecutore
				WHERE Id = @idFirmaEsecutore;

			UPDATE dbo.tblServizi
			SET
				IdRichiedente = @IdRichiedente,
				DataRichiesta = @DataRichiesta,
				Descrizione = @Descrizione,
				Durata = @Durata
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Servizio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			DELETE dbo.tblEventiEtichette
			WHERE Id = @IdEvento;

			INSERT dbo.tblEventiEtichette (Id, IdEtichetta)
			SELECT TOP 3 @IdEvento, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value
			WHERE v.value <> '';

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				AvvisoAnticipo = IIF(@Avviso = 0, NULL, @AvvisoAnticipo),
				Email = IIF(@Avviso = 0, NULL, @Email),
				Avviso = t.Nome + ' - ' + r.NomeCompleto + ' - ' + r.IndirizzoCompleto,
				Etichette = dbo.ufnEventi_get_Etichette(e.Id),
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			WHERE
				e.Id = @IdEvento
				AND e.Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Evento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

-- ===== 36. uspServizi_upd_Data (sql/procedures/uspServizi_upd_Data.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd_Data]
	@IdSessione CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@DataOccorrenza SMALLDATETIME = NULL,
	@DataCella SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@IdOsepeDa CHAR(16) = NULL,
	@IdOsepeA CHAR(16) = NULL
AS
-- Sposta un servizio nella cella di un'altra data e ora (trascinamento nel calendario, S4.7.6): cambia solo la data,
-- il resto del servizio resta com'e'. @IdEvento e @DataOccorrenza (la data del servizio o dell'occorrenza) sono quelli
-- del servizio trascinato; @DataCella e' l'inizio della cella di arrivo, @IdIntervallo la sua ampiezza: '1H' l'ora delle
-- viste Giorno e Settimana (nuova ora = ora della cella con i minuti del servizio), '1D' il giorno (vista Mese e fascia
-- In giornata: cambia solo il giorno), '30' la mezz'ora (viste Giorno e Settimana dal 2026-11-23:
-- @DataCella e' il nuovo inizio, su :00 o :30, come nell'anteprima del trascinamento). Il servizio "In giornata" cambia sempre solo il giorno.
-- Impegni per risorsa (S9.10): con @IdOsepeDa (risorsa della colonna di partenza) e @IdOsepeA (risorsa della colonna di
-- arrivo) diverse cambia anche la risorsa, nella stessa transazione: stesso tipo (persona con persona, oggetto con
-- oggetto), Da ancora nel servizio, A impiegabile come in uspServizi_ins_Osepe (S4.5.1); A prende la quantita' di Da,
-- oppure, se e' gia' nel servizio, si toglie solo Da.
-- Per un'occorrenza di una serie ricorrente si cambia la sola occorrenza, che diventa un'occorrenza modificata
-- (eccezione con un evento sostituto, come "Solo questa occorrenza" della scheda, S5.3): la serie non si cambia mai
-- trascinando. Si spostano solo i servizi da eseguire o in esecuzione. Restituisce l'Id del servizio (il nuovo, per
-- un'occorrenza) ed Esito: "Servizio spostato", "Risorsa cambiata" o "Servizio spostato e risorsa cambiata" (NULL se
-- non cambia niente).
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;
		DECLARE @ricorre BIT = 0;
		DECLARE @idStato CHAR(1);
		DECLARE @inGiornata BIT;
		DECLARE @durata INT;
		DECLARE @dataEvento SMALLDATETIME;
		DECLARE @dataPartenza SMALLDATETIME;
		DECLARE @data SMALLDATETIME;
		DECLARE @idCalendario CHAR(16);
		DECLARE @idServizio CHAR(16);
		DECLARE @cambioRisorsa BIT = 0;
		DECLARE @esito NVARCHAR(50) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @IdOsepeDa = NULLIF(LTRIM(RTRIM(@IdOsepeDa)), '');
		SET @IdOsepeA = NULLIF(LTRIM(RTRIM(@IdOsepeA)), '');
		SET @cambioRisorsa = IIF(@IdOsepeDa IS NOT NULL AND @IdOsepeA IS NOT NULL AND @IdOsepeDa <> @IdOsepeA, 1, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataCella IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL OR @IdIntervallo NOT IN ('1H', '1D', '30')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END
		-- Mezz'ora: la cella parte alle :00 o alle :30
		IF @IdIntervallo = '30' AND DATEPART(MINUTE, @DataCella) NOT IN (0, 30)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non è l''inizio di una mezz''ora';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			@idServizio = s.Id,
			@idStato = e.IdStato,
			@inGiornata = e.InGiornata,
			@durata = s.Durata,
			@dataEvento = e.[Data],
			@idCalendario = e.IdCalendario,
			@ricorre = IIF(r.Id IS NULL, 0, 1)
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
		WHERE
			e.Id = @IdEvento
			AND e.Lock = 0;

		IF @idServizio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Servizio non trovato o già eliminato';
			GOTO BRANCH_END;
		END

		IF @ricorre = 1 AND @DataOccorrenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataOccorrenza non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @idStato NOT IN ('D', 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si spostano solo i servizi da eseguire o in esecuzione: per gli altri modificare la data nella scheda';
			GOTO BRANCH_END;
		END

		-- Nuova data: il giorno della cella di arrivo con l'ora del servizio (vista Mese e servizi In giornata),
		-- oppure l'ora della cella con i minuti del servizio (viste Giorno e Settimana)
		SET @dataPartenza = IIF(@ricorre = 1, @DataOccorrenza, @dataEvento);

		IF @IdIntervallo = '1D' OR @inGiornata = 1
			SET @data = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST(CAST(@dataPartenza AS DATE) AS SMALLDATETIME), @dataPartenza),
				CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME));
		ELSE IF @IdIntervallo = '30'
			-- Mezz'ora (anteprima del trascinamento): l'inizio e' quello della cella
			SET @data = @DataCella;
		ELSE
			SET @data = DATEADD(MINUTE, DATEPART(MINUTE, @dataPartenza),
				DATEADD(HOUR, DATEDIFF(HOUR, CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME), @DataCella), CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME)));

		IF @data < dbo.ufnDate_get_Min() OR @data > dbo.ufnDate_get_Max()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data deve essere compresa fra il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy') + ' e il ' + FORMAT(dbo.ufnDate_get_Max(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		-- Stessa regola di uspServizi_upd (S6.7): il servizio termina entro la mezzanotte del giorno di inizio
		IF @durata IS NOT NULL
		   AND DATEADD(MINUTE, @durata, IIF(ISNULL(@inGiornata, 0) = 1, CAST(CAST(@data AS DATE) AS DATETIME), CAST(@data AS DATETIME)))
			   > DATEADD(DAY, 1, CAST(CAST(@data AS DATE) AS DATETIME))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: con la sua durata non può iniziare a quest''ora';
			GOTO BRANCH_END;
		END

		-- Cambio di risorsa (Impegni per risorsa): controlli prima di scrivere qualunque cosa
		IF @cambioRisorsa = 1
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblOsepe da
					INNER JOIN dbo.tblOsepe a ON a.Tipo = da.Tipo
				WHERE
					da.Id = @IdOsepeDa
					AND a.Id = @IdOsepeA
					AND da.Tipo IN ('P', 'O')
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Si sostituisce una persona con una persona e un oggetto con un oggetto';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe
				WHERE
					Id = @idServizio
					AND IdOsepe = @IdOsepeDa
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La persona o l''oggetto non è più nel servizio: aggiornare la pagina';
				GOTO BRANCH_END;
			END

			-- Stesso controllo di uspServizi_ins_Osepe (S4.5.1): impiegabile nei servizi, non disabilitato, dell'azienda
			-- del calendario del servizio o condiviso tramite le Aree; una risorsa gia' nel servizio va sempre bene
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe
				WHERE
					Id = @idServizio
					AND IdOsepe = @IdOsepeA
			)
			AND NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblCalendari c
					INNER JOIN dbo.tblSedi d ON c.IdSede = d.Id
					CROSS JOIN dbo.tblSessioni n
					CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(n.IdUtente) u
				WHERE
					c.Id = @idCalendario
					AND n.Id = @IdSessione
					AND u.Id = @IdOsepeA
					AND
						(
							(
							u.IdDominio = n.IdDominio
							AND u.Condivisa = 1
							)
						OR u.IdSede = d.IdAziendaInterna
						)
					AND u.Tipo IN ('P', 'O')
					AND u.Disabilitata = 0
					AND u.ImpiegabileServizi = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La persona o l''oggetto indicato non è impiegabile nei servizi';
				GOTO BRANCH_END;
			END
		END

		-- Nessuna modifica: rilasciato nella cella da cui e' partito, nella stessa risorsa
		IF @data = @dataPartenza AND @cambioRisorsa = 0
		BEGIN
			SELECT @idServizio AS Id, @esito AS Esito;
			GOTO BRANCH_END;
		END

		SET @esito = CASE
			WHEN @data <> @dataPartenza AND @cambioRisorsa = 1 THEN 'Servizio spostato e risorsa cambiata'
			WHEN @cambioRisorsa = 1 THEN 'Risorsa cambiata'
			ELSE 'Servizio spostato'
		END;

		IF @ricorre = 0
		BEGIN
			BEGIN TRANSACTION;

				UPDATE dbo.tblEventi
				SET [Data] = @data
				WHERE
					Id = @IdEvento
					AND Lock = 0;

				SET @returnId = @idServizio;

				IF @cambioRisorsa = 1
				BEGIN
					IF EXISTS (SELECT 1 FROM dbo.tblServiziOsepe WHERE Id = @returnId AND IdOsepe = @IdOsepeA)
						DELETE dbo.tblServiziOsepe
						WHERE
							Id = @returnId
							AND IdOsepe = @IdOsepeDa;
					ELSE
						UPDATE dbo.tblServiziOsepe
						SET IdOsepe = @IdOsepeA
						WHERE
							Id = @returnId
							AND IdOsepe = @IdOsepeDa;
				END

			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			-- Occorrenza di una serie: la data deve essere un'occorrenza vera (non cancellata ne' gia' modificata)
			DECLARE @calendari tvpId_char_16;
			INSERT INTO @calendari (Id) VALUES (@idCalendario);
			DECLARE @tipi tvpId_char_1;
			INSERT INTO @tipi (Id) VALUES ('V');

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.ufnEventi_get_List(@DataOccorrenza, @DataOccorrenza, @calendari, @tipi) e
				WHERE
					e.Id = @IdEvento
					AND e.[Data] = @DataOccorrenza
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Occorrenza non trovata: aggiornare il calendario';
				GOTO BRANCH_END;
			END

			-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione), come in uspServizi_ins
			DECLARE @returnIdEvento CHAR(16) = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

			BEGIN TRANSACTION;

				-- Copia dell'occorrenza come in uspServizi_ins (ramo della singola occorrenza), gia' alla nuova data e
				-- senza bozza (Lock = 0): non passa dalla scheda
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
				SELECT
					@returnIdEvento, IdCalendario, 'D', 'V', @data,
					InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, 0
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @returnIdEvento, IdProprieta, Valore
				FROM dbo.tblEventiProprieta
				WHERE Id = @IdEvento;

				INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
				SELECT @returnIdEvento, IdEtichetta
				FROM dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @IdEvento
					AND [Data] = @DataOccorrenza;

				INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				VALUES (@IdEvento, @DataOccorrenza, @returnIdEvento, 0);

				INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata)
				SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata
				FROM dbo.tblServizi
				WHERE IdEvento = @IdEvento;

				-- Risorse della serie; con il cambio di risorsa A prende il posto di Da (o, se c'e' gia', si toglie Da)
				INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
				SELECT @returnId, IIF(@cambioRisorsa = 1 AND o.IdOsepe = @IdOsepeDa, @IdOsepeA, o.IdOsepe), o.Quantita
				FROM dbo.tblServiziOsepe o
				WHERE
					o.Id = @idServizio
					AND NOT (
						@cambioRisorsa = 1
						AND o.IdOsepe = @IdOsepeDa
						AND EXISTS (SELECT 1 FROM dbo.tblServiziOsepe x WHERE x.Id = @idServizio AND x.IdOsepe = @IdOsepeA)
					);

			COMMIT TRANSACTION;
		END

		EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnId AS Id, @esito AS Esito;

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

-- ===== 37. uspServiziAssegnati_get (sql/procedures/uspServiziAssegnati_get.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_get]
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

		-- Controllo permesso: SRV (Gestione Servizi) O SRA (Servizi Assegnati)
		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 1 > @permessoSrv AND 1 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Verifica che il servizio appartenga a un calendario accessibile dalla sessione e sia assegnato all'utente
		-- della sessione: in Servizi > Assegnati ognuno vede e gestisce solo i propri servizi
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			INNER JOIN dbo.tblEventiUtenti u ON e.Id = u.Id
			INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente AND ss.Id = @IdSessione
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			s.IdTipo,
			IdRichiedente = ISNULL(s.IdRichiedente, ''),
			IdEvento = ISNULL(s.IdEvento, ''),
			Descrizione = ISNULL(s.Descrizione, ''),
			DataRichiesta = ISNULL(s.DataRichiesta, GETDATE()),
			IdStato = ISNULL(e.IdStato, 'D'),
			[Data] = ISNULL(e.[Data], DATEADD(MINUTE, ((DATEDIFF(MINUTE, 0, GETDATE()) / 30) * 30), 0)),
			InGiornata = ISNULL(e.InGiornata, 0),
			s.Durata,
			e.Lock,
			Proprieta = dbo.ufnEventi_get_TipoProprieta(s.IdEvento, s.IdTipo),
			FirmaRichiedente = fr.Firma
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			LEFT JOIN dbo.tblEventiFirme er ON e.Id = er.Id
												   AND er.IdTipo = 'R'
			LEFT JOIN dbo.tblFirme fr ON er.IdFirma = fr.Id
		WHERE
			s.Id = @Id
			AND e.Lock <= 2;

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

-- ===== 38. uspServiziAssegnati_get_List (sql/procedures/uspServiziAssegnati_get_List.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 1 > @permessoSrv AND 1 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdUtente CHAR(16);
		DECLARE @idCal CHAR(16);

		SELECT @IdUtente = IdUtente, @idCal = IdCalendario
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id) SELECT @idCal
		WHERE @idCal IS NOT NULL;

		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);

		-- Periodo esatto: dalla data (00:00) per l'intervallo, fine esclusa (1 giorno = il solo giorno della data,
		-- 1 settimana = 7 giorni), come uspServizi_get_Impegni_Elenco_List. Fino al 2026-11-22 arrivava alla fine
		-- del giorno dopo l'intervallo (docs/regole/scadenze-servizi.md S4.7.5)
		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, CASE
			WHEN @IdIntervallo = '1W' THEN DATEADD(WEEK, 1, @DallaData)
			WHEN @IdIntervallo = '2W' THEN DATEADD(WEEK, 2, @DallaData)
			WHEN @IdIntervallo = '1M' THEN DATEADD(MONTH, 1, @DallaData)
			WHEN @IdIntervallo = '2M' THEN DATEADD(MONTH, 2, @DallaData)
			WHEN @IdIntervallo = '6M' THEN DATEADD(MONTH, 6, @DallaData)
			WHEN @IdIntervallo = '1Y' THEN DATEADD(YEAR, 1, @DallaData)
			ELSE DATEADD(DAY, 1, @DallaData)
		END);

		-- Scaduti (da eseguire o in esecuzione con la data passata): tutti quelli rimasti indietro, senza Dalla data né
		-- intervallo, altrimenti con la partenza da oggi non comparirebbero mai (docs/regole/scadenze-servizi.md S7.1)
		IF @Stato = 'S'
		BEGIN
			SET @DallaData = '19000101';
			SET @AllaData = GETDATE();
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage  INT,
            @Offset       INT,
            @IdSessione   CHAR(16),
            @IdIntervallo CHAR(2),
            @DallaData    SMALLDATETIME,
            @AllaData     SMALLDATETIME,
            @Stato        CHAR(1),
            @Search       VARCHAR(50),
            @IdUtente     CHAR(16),
            @IdCalendario tvpId_char_16 READONLY';

		SET @stmt = N'
        WITH tbl AS (
            SELECT
                s.Id,
                s.IdEvento,
                e.[Data],
                StatoValore = CASE
                    WHEN e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE() THEN 1
                    WHEN e.IdStato = ''A''                                      THEN 2
                    ELSE 0
                END,
                StatoDescrizione = e.Stato + IIF(e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE(), '' - Scaduto'', ''''),
                Tipo             = t.Nome,
                s.Descrizione,
                Richiedente      = r.NomeCompleto + '' - '' + r.IndirizzoCompleto,
                -- Copia delle etichette sull evento (tblEventi.Etichette, come nelle Scadenze), non la funzione per ogni riga
                Etichette        = ev.Etichette
            FROM
                dbo.ufnEventi_get_Assegnati_List(@DallaData, @AllaData, @IdUtente, @IdCalendario) e
                INNER JOIN dbo.tblEventi  ev ON e.Id          = ev.Id
                INNER JOIN dbo.tblServizi s ON e.Id          = s.IdEvento
                INNER JOIN dbo.tblSedi    r ON s.IdRichiedente = r.Id
                INNER JOIN dbo.tblTipi    t ON s.IdTipo       = t.Id
            WHERE 1 = 1';

		IF @Search IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.Descrizione LIKE ''%'' + @Search + ''%''';

		IF @Stato <> 'T'
		BEGIN
			IF @Stato = 'S'
				SET @stmt = @stmt + N'
                    AND (e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE())';
			ELSE
				SET @stmt = @stmt + N'
                    AND e.IdStato = @Stato';
		END

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.IdEvento, tbl.[Data],
            tbl.StatoValore, tbl.StatoDescrizione,
            tbl.Tipo, tbl.Descrizione, tbl.Richiedente, tbl.Etichette,
            RowsCount = COUNT(*) OVER ()
        FROM tbl
        ORDER BY tbl.[Data]
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY;';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Stato = @Stato,
			@Search = @Search,
			@IdUtente = @IdUtente,
			@IdCalendario = @IdCalendario;

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

-- ===== 39. uspServiziAssegnati_upd (sql/procedures/uspServiziAssegnati_upd.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@DataRichiesta SMALLDATETIME = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@FirmaRichiedente IMAGE = NULL,
	@FirmaEsecutore IMAGE = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
		DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;
		DECLARE @idTipo CHAR(16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdRichiedente = NULLIF(LTRIM(RTRIM(@IdRichiedente)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

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
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Verifica che il servizio appartenga a un calendario accessibile dalla sessione e sia assegnato all'utente
		-- della sessione: in Servizi > Assegnati ognuno vede e gestisce solo i propri servizi
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			INNER JOIN dbo.tblEventiUtenti u ON e.Id = u.Id
			INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente AND ss.Id = @IdSessione
			WHERE
				s.Id = @Id
				AND e.Id = @IdEvento
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate. L'operatore le
		-- compila solo sui servizi assegnati a lui (controllo sopra)
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblServizi
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- La durata non si cambia da qui (la decide chi gestisce i Servizi), ma con la nuova data e ora il servizio
		-- deve ancora terminare entro la mezzanotte del giorno di inizio (regola di uspServizi_upd)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblServizi
			WHERE
				Id = @Id
				AND Durata IS NOT NULL
				AND ISNULL(@InGiornata, 0) = 0
				AND DATEADD(MINUTE, Durata, CAST(@Data AS DATETIME)) > DATEADD(DAY, 1, CAST(CAST(@Data AS DATE) AS DATETIME))
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: con la sua durata non può iniziare a quest''ora';
			GOTO BRANCH_END;
		END

		IF @FirmaRichiedente IS NOT NULL
			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

		IF @FirmaEsecutore IS NOT NULL
			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

		BEGIN TRANSACTION;

			-- Gestione firma richiedente
			IF @FirmaRichiedente IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'R';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaRichiedente;
			END
			ELSE IF @idFirmaRichiedente IS NULL
			BEGIN
				SET @idFirmaRichiedente = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaRichiedente, @FirmaRichiedente);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaRichiedente, 'R');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaRichiedente
				WHERE Id = @idFirmaRichiedente;

			-- Gestione firma esecutore
			IF @FirmaEsecutore IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'E';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaEsecutore;
			END
			ELSE IF @idFirmaEsecutore IS NULL
			BEGIN
				SET @idFirmaEsecutore = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaEsecutore, @FirmaEsecutore);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaEsecutore, 'E');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaEsecutore
				WHERE Id = @idFirmaEsecutore;

			UPDATE dbo.tblServizi
			SET
				IdRichiedente = @IdRichiedente,
				DataRichiesta = @DataRichiesta,
				Descrizione = @Descrizione
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Servizio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				Avviso = t.Nome + ' - ' + r.NomeCompleto + ' - ' + r.IndirizzoCompleto,
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			WHERE
				e.Id = @IdEvento
				AND e.Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Evento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

-- ===== Verifica
SELECT 'tblServizi.Durata' AS Oggetto, IIF(COL_LENGTH('dbo.tblServizi', 'Durata') IS NULL, 'MANCA', 'ok') AS Esito
UNION ALL SELECT 'CK_tblServizi_Durata', IIF(EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_tblServizi_Durata'), 'ok', 'MANCA')
UNION ALL SELECT 'IX_RicorrenzeEccezioni_IdEvento', IIF(EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RicorrenzeEccezioni_IdEvento'), 'ok', 'MANCA')
UNION ALL SELECT 'Menu AE1 -> SRV', IIF(EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AE1' AND IdPagina = 'SRV'), 'ok', 'DA CONTROLLARE')
UNION ALL SELECT 'Menu AE6 -> SRI', IIF(EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AE6' AND IdPagina = 'SRI'), 'ok', 'MANCA');

SELECT o.name, o.type_desc, o.modify_date, m.uses_quoted_identifier
FROM
	sys.objects o
	INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (N'ufnServizi_get_Orario', N'ufnEventi_get_List', N'uspFatture_get_Esportazione', N'uspFatture_get_List', N'uspFattureRate_get_Scadenzario_Esportazione', N'uspFattureRate_get_Scadenzario_List', N'uspScadenze_get_ByData_List', N'uspScadenze_get_Calendario_Eventi_List', N'uspScadenze_get_CalendarioGiorno_List', N'uspScadenze_get_CalendarioMese_List', N'uspScadenze_get_CalendarioSettimana_List', N'uspScadenze_get_List', N'uspScadenze_ins', N'uspScadenze_upd', N'uspScadenze_upd_Data', N'uspServizi_get', N'uspServizi_get_ByData_List', N'uspServizi_get_Calendario_Eventi_List', N'uspServizi_get_CalendarioGiorno_List', N'uspServizi_get_CalendarioMese_List', N'uspServizi_get_CalendarioSettimana_List', N'uspServizi_get_Esportazione', N'uspServizi_get_Impegni_ByData_List', N'uspServizi_get_Impegni_Elenco_List', N'uspServizi_get_Impegni_Eventi_List', N'uspServizi_get_Impegni_List', N'uspServizi_get_List', N'uspServizi_get_Stampa', N'uspServizi_ins', N'uspServizi_ins_Osepe', N'uspServizi_upd', N'uspServizi_upd_Data', N'uspServiziAssegnati_get', N'uspServiziAssegnati_get_List', N'uspServiziAssegnati_upd')
ORDER BY o.name;
GO