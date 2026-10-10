/*
Deploy produzione 2026-10-10 - Report: Fatturazione > Report (fatturato per mese, per cliente o fornitore, per conto)
e Rifiuti > Report (riepiloghi delle registrazioni per operazione ed EER, con i valori operativi)

Da eseguire DOPO gli script del 2026-10-09 (posizioni del menu Fatturazione). Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

1. Pagine e voci di menu: Fatturazione > Report (funzione FTT, ultima voce del menu) e Rifiuti > Report
   (funzione RRG, in fondo al menu). Nessuna tabella e nessuna funzione nuova.
2. uspFatture_get_Fatturato: i sei report del fatturato.
3. uspRifiutiRegistrazioni_get_Report_Registri_SelectList: registri della sede per il filtro della ricerca.
4. uspRifiutiRegistrazioni_get_Report: i dieci report dei rifiuti.
5. uspDomini_get_Moduli_SelectList: nella scheda del dominio la select dei moduli da aggiungere mostra solo
   quelli non ancora assegnati (nuovi parametri @Id, il dominio, e @IdSessione: solo amministratori Master).

Le SP servono sia l'elenco a video sia l'esportazione in Excel e in CSV. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'report_menu_registration.sql';
GO
-- Report: pagine e voci di menu di Fatturazione > Report (funzione FTT, la stessa delle fatture) e di
-- Rifiuti > Report (funzione RRG, la stessa delle registrazioni). Nessuna tabella e nessuna funzione nuova.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTR', 'FTT', 'Report', 'report', NULL);

-- La voce è nata come "Fatturato": si chiama "Report", come quella dei rifiuti
UPDATE dbo.tblPagine SET Nome = 'Report', Url = 'report' WHERE Id = 'FTR' AND (Nome <> 'Report' OR ISNULL(Url, '') <> 'report');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'RRP')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('RRP', 'RRG', 'Report', 'report', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti, Scadenziario fornitori,
-- Prima nota, Conti, Banche e casse, Aliquote IVA, Dati fiscali, Report (ultima voce)
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJA')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJA', 'AJ0', NULL, 'FTR', 9);

UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AJ8' AND Pos <> 8;
UPDATE dbo.tblMenu SET Pos = 9 WHERE Id = 'AJA' AND Pos <> 9;

-- Menu Rifiuti: Report in coda, dopo Dichiarazioni MUD
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AFA')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AFA', 'AF0', NULL, 'RRP', 9);
GO

GO

PRINT 'uspFatture_get_Fatturato.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Report: report del fatturato dell'azienda del contesto in un anno, dalle fatture clienti
-- (@Tipo = C) o fornitori (@Tipo = F), raggruppato per mese (@Raggruppamento = M), per cliente o fornitore (S)
-- o per conto (C). La stessa SP serve l'elenco a video e l'esportazione in Excel e in CSV: il nome di ogni
-- colonna è l'intestazione, nell'ordine in cui le colonne vanno mostrate (pagina comune dei report).
-- Contano le fatture attive (Lock = 0: né bozze né cancellate) con data di emissione nell'anno (per un
-- fornitore è la data del suo documento), escluse le pre-fatture (TD00); le note di credito (TD04) contano
-- con il segno meno. Senza @Anno vale l'anno in corso.
-- Per mese (sempre 12 righe) e per cliente o fornitore gli importi sono i totali delle fatture
-- (ufnFatture_get_Totali: il totale comprende il bollo). Per conto si sommano gli imponibili delle righe,
-- perché il conto sta sulla riga: niente IVA né totale, e le righe senza conto vanno in "(Senza conto)".
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che il limite è superato).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Fatturato
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Raggruppamento CHAR(1) = NULL,
	@Anno INT = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Raggruppamento = UPPER(NULLIF(LTRIM(RTRIM(@Raggruppamento)), ''));
		SET @Anno = ISNULL(NULLIF(@Anno, 0), YEAR(GETDATE()));
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
		IF @Raggruppamento IS NULL OR @Raggruppamento NOT IN ('M', 'S', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Raggruppamento deve essere M (mese), S (cliente o fornitore) o C (conto)';
			GOTO BRANCH_END;
		END
		IF @Anno < 1900 OR @Anno > 2100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare un anno compreso tra 1900 e 2100';
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

		DECLARE @dataDa DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @dataA DATE = DATEFROMPARTS(@Anno, 12, 31);

		-- Fatture dell'anno, con il segno (meno per le note di credito) e i totali
		DECLARE @fatture TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Mese INT NOT NULL,
			Segno INT NOT NULL,
			Imponibile DECIMAL(18, 2) NOT NULL,
			Iva DECIMAL(18, 2) NOT NULL,
			Totale DECIMAL(18, 2) NOT NULL
		);

		INSERT @fatture (Id, IdClienteFornitore, Mese, Segno, Imponibile, Iva, Totale)
		SELECT
			f.Id,
			f.IdClienteFornitore,
			MONTH(f.DataEmissione),
			IIF(f.IdTipo = 'TD04', -1, 1),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Imponibile, 0),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Iva, 0),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Totale, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
		WHERE
			e.Id = @IdSessione
			AND f.Tipo = @Tipo
			AND f.Lock = 0
			AND f.DataEmissione >= @dataDa
			AND f.DataEmissione <= @dataA
			AND ISNULL(f.IdTipo, '') <> 'TD00';

		IF @Raggruppamento = 'M'
			SELECT
				[Mese] = n.Nome,
				[Documenti] = COUNT(f.Id),
				[Imponibile] = ISNULL(SUM(f.Imponibile), 0),
				[IVA] = ISNULL(SUM(f.Iva), 0),
				[Totale] = ISNULL(SUM(f.Totale), 0)
			FROM
				(VALUES (1, 'Gennaio'), (2, 'Febbraio'), (3, 'Marzo'), (4, 'Aprile'), (5, 'Maggio'), (6, 'Giugno'), (7, 'Luglio'), (8, 'Agosto'), (9, 'Settembre'), (10, 'Ottobre'), (11, 'Novembre'), (12, 'Dicembre')) n (Mese, Nome)
				LEFT JOIN @fatture f ON n.Mese = f.Mese
			-- Senza azienda nel contesto nessuna riga, come negli altri raggruppamenti
			WHERE EXISTS (SELECT 1 FROM dbo.tblSessioni e WHERE e.Id = @IdSessione AND NULLIF(e.IdAzienda, REPLICATE('0', 16)) IS NOT NULL)
			GROUP BY
				n.Mese,
				n.Nome
			ORDER BY n.Mese;
		ELSE IF @Raggruppamento = 'S' AND @Tipo = 'C'
			SELECT TOP (@MaxRighe + 1)
				[Cliente] = ISNULL(s.NomeCompleto, '(Senza cliente)'),
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Documenti] = COUNT(*),
				[Imponibile] = SUM(f.Imponibile),
				[IVA] = SUM(f.Iva),
				[Totale] = SUM(f.Totale)
			FROM
				@fatture f
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			GROUP BY
				s.Id,
				s.NomeCompleto,
				s.PartitaIva,
				s.CodiceFiscale
			ORDER BY
				SUM(f.Imponibile) DESC,
				s.NomeCompleto,
				s.Id;
		ELSE IF @Raggruppamento = 'S'
			SELECT TOP (@MaxRighe + 1)
				[Fornitore] = ISNULL(s.NomeCompleto, '(Senza fornitore)'),
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Documenti] = COUNT(*),
				[Imponibile] = SUM(f.Imponibile),
				[IVA] = SUM(f.Iva),
				[Totale] = SUM(f.Totale)
			FROM
				@fatture f
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			GROUP BY
				s.Id,
				s.NomeCompleto,
				s.PartitaIva,
				s.CodiceFiscale
			ORDER BY
				SUM(f.Imponibile) DESC,
				s.NomeCompleto,
				s.Id;
		ELSE
			SELECT TOP (@MaxRighe + 1)
				[Codice] = k.Codice,
				[Conto] = ISNULL(k.Nome, '(Senza conto)'),
				[Righe] = COUNT(*),
				[Imponibile] = SUM(f.Segno * CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2)))
			FROM
				@fatture f
				INNER JOIN dbo.tblFattureRighe r ON f.Id = r.IdFattura
				INNER JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				LEFT JOIN dbo.tblFattureConti k ON i.IdConto = k.Id
			GROUP BY
				k.Id,
				k.Codice,
				k.Nome
			ORDER BY
				IIF(k.Id IS NULL, 1, 0),
				k.Nome,
				k.Id;

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

PRINT 'uspRifiutiRegistrazioni_get_Report_Registri_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rifiuti > Report: registri della sede del contesto per il filtro "Registro" della ricerca. La prima voce
-- (sedici zeri) vale "tutti i registri della sede". Senza sede nel contesto resta solo quella.
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_Report_Registri_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede)
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, @idSediciZeri)
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			x.Id,
			x.[Text],
			x.Selected
		FROM
			(
				SELECT
					Id = @idSediciZeri,
					[Text] = CAST('(Tutti i registri della sede)' AS VARCHAR(500)),
					Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
					Pos = 0
				UNION ALL
				SELECT
					r.Id,
					[Text] = r.Nome,
					Selected = CAST(IIF(r.Id = @IdSelected, 1, 0) AS BIT),
					Pos = 1
				FROM dbo.tblRifiutiRegistri r
				WHERE
					r.IdSede = @idSede
					AND r.Lock = 0
			) x
		ORDER BY
			x.Pos,
			x.[Text];

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

PRINT 'uspRifiutiRegistrazioni_get_Report.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rifiuti > Report: riepiloghi delle registrazioni della sede del contesto, per operazione ed EER. La stessa
-- SP serve l'elenco a video e l'esportazione in Excel e in CSV: il nome di ogni colonna è l'intestazione,
-- nell'ordine in cui le colonne vanno mostrate (pagina comune dei report).
-- @Report sceglie le operazioni contate e le colonne in più:
--   PR  Rifiuti prodotti                                   DT, RE
--   PL  Rifiuti prodotti da lavorazione                    NP
--   RT  Rifiuti ricevuti da terzi                          T*              + produttore
--   TR  Rifiuti trasportati                                T*aT
--   TT  Rifiuti trasportati da terzi                       aT, T*          + trasportatore (solo se esterno)
--   CT  Rifiuti consegnati a terzi (destinatari)           aT              + destinatario
--   IN  Rifiuti movimentati attraverso intermediari        aT, T*, T*aT, TR + intermediario (solo se indicato)
--   DG  Destinazione (R o D) dei rifiuti gestiti nell'unità locale   T*, I  + attività
--   DC  Destinazione (R o D) dei rifiuti consegnati a terzi          aT     + attività e destinatario
--   MV  Quantità rifiuti movimentati per CER               tutte, tranne M (materiali) e SI (stoccaggio istantaneo)
-- La colonna Operazione (codice e nome della causale) distingue le righe quando il report conta più operazioni.
-- Valori OPERATIVI (viewRifiutiRegistrazioniEffettive: EER, stato fisico, unità di misura e quantità dopo le
-- rettifiche): contano le registrazioni confermate (Lock = 0), escluse le rettifiche e le registrazioni
-- annullate operativamente. Le quantità non si convertono: una riga per ogni unità di misura.
-- La sede è quella del contesto della sessione (senza sede nessuna riga); @IdRegistro restringe a un registro
-- della sede, @DataDa e @DataA alla data della registrazione.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che il limite è superato).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_Report
	@IdSessione CHAR(16) = NULL,
	@Report CHAR(2) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdRegistro CHAR(16) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Report = UPPER(NULLIF(LTRIM(RTRIM(@Report)), ''));
		SET @IdRegistro = NULLIF(NULLIF(LTRIM(RTRIM(@IdRegistro)), ''), REPLICATE('0', 16));
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Report IS NULL OR @Report NOT IN ('PR', 'PL', 'RT', 'TR', 'TT', 'CT', 'IN', 'DG', 'DC', 'MV')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Report non previsto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
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

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Operazioni contate dal report (tblRifiutiOperazioni.Id)
		DECLARE @operazioni TABLE (
			Id CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
		);
		INSERT @operazioni (Id)
		SELECT x.Id
		FROM
			(VALUES
				('PR', 'C'), ('PR', 'F'),
				('PL', 'M'),
				('RT', 'Z'),
				('TR', 'T'),
				('TT', 'S'), ('TT', 'Z'),
				('CT', 'S'),
				('IN', 'S'), ('IN', 'Z'), ('IN', 'T'), ('IN', 'I'),
				('DG', 'Z'), ('DG', 'R'),
				('DC', 'S'),
				('MV', 'C'), ('MV', 'F'), ('MV', 'M'), ('MV', 'Z'), ('MV', 'T'), ('MV', 'S'), ('MV', 'R'), ('MV', 'I')
			) x (Report, Id)
		WHERE x.Report = @Report;

		-- Soggetto in colonna: P produttore, D destinatario, T trasportatore, I intermediario
		DECLARE @soggetto CHAR(1) =
			CASE @Report
				WHEN 'RT' THEN 'P'
				WHEN 'TT' THEN 'T'
				WHEN 'CT' THEN 'D'
				WHEN 'IN' THEN 'I'
				WHEN 'DC' THEN 'D'
			END;
		DECLARE @conAttivita BIT = IIF(@Report IN ('DG', 'DC'), 1, 0);

		DECLARE @righe TABLE (
			Pos INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			Operazione VARCHAR(110) COLLATE DATABASE_DEFAULT NULL,
			Eer VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			StatoFisico VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Pericoloso BIT NULL,
			Attivita VARCHAR(3) COLLATE DATABASE_DEFAULT NULL,
			Soggetto VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Registrazioni INT NOT NULL,
			Quantita DECIMAL(18, 2) NULL,
			Unita VARCHAR(2) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT @righe (Operazione, Eer, Descrizione, StatoFisico, Pericoloso, Attivita, Soggetto, Registrazioni, Quantita, Unita)
		SELECT TOP (@MaxRighe + 1)
			o.Codice + ' - ' + o.Nome,
			e.Nome,
			e.Descrizione,
			sf.Nome,
			e.Pericoloso,
			IIF(@conAttivita = 1, a.Codice, NULL),
			s.NomeCompleto,
			COUNT(*),
			SUM(v.Quantita),
			u.Codice
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN @operazioni p ON m.IdOperazione = p.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici sf ON v.IdStatoFisico = sf.Id
			LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			LEFT JOIN dbo.tblSedi s ON s.Id =
				CASE @soggetto
					WHEN 'P' THEN m.IdSedeProduttoreDetentore
					WHEN 'D' THEN m.IdSedeDestinatario
					WHEN 'T' THEN m.IdSedeTrasportatore1
					WHEN 'I' THEN m.IdSedeIntermediario1
				END
		WHERE
			g.IdSede = @idSede
			AND r.Lock = 0
			AND v.IsRettifica = 0
			AND v.IsAnnullata = 0
			AND
				(
				@IdRegistro IS NULL
				OR m.IdRegistro = @IdRegistro
				)
			AND
				(
				@DataDa IS NULL
				OR r.[Data] >= @DataDa
				)
			AND (@DataA IS NULL OR r.[Data] <= @DataA)
			-- Trasportati da terzi: solo con un trasportatore esterno; attraverso intermediari: solo con l'intermediario
			AND
				(
				@Report <> 'TT'
				OR s.InternaEsterna = 'E'
				)
			AND
				(
				@Report <> 'IN'
				OR s.Id IS NOT NULL
				)
		GROUP BY
			o.Pos,
			o.Codice,
			o.Nome,
			e.Nome,
			e.Descrizione,
			sf.Nome,
			e.Pericoloso,
			IIF(@conAttivita = 1, a.Codice, NULL),
			s.Id,
			s.NomeCompleto,
			u.Codice
		ORDER BY
			o.Pos,
			e.Nome,
			sf.Nome,
			IIF(@conAttivita = 1, a.Codice, NULL),
			s.NomeCompleto,
			s.Id,
			u.Codice
		OPTION (RECOMPILE);

		-- Stesse righe, con le colonne del report
		IF @Report = 'DC'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Attività] = x.Attivita,
				[Destinatario] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @Report = 'DG'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Attività] = x.Attivita,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'P'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Produttore] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'D'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Destinatario] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'T'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Trasportatore] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE IF @soggetto = 'I'
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Intermediario] = x.Soggetto,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
			ORDER BY x.Pos;
		ELSE
			SELECT
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Stato fisico] = x.StatoFisico,
				[Pericoloso] = x.Pericoloso,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM @righe x
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

PRINT 'uspDomini_get_Moduli_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_Moduli_SelectList]
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

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso: solo Admin di dominio Master (come uspDomini_get_Moduli_List)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Restituisce i moduli selezionabili per un dominio
		-- escludendo BAS (Base) e IMP (Impostazioni) riservati al sistema.
		-- Con @Id (il dominio) solo quelli non ancora assegnati al dominio
		SELECT
			m.Id,
			[Text] = m.Nome,
			Selected = CAST(0 AS BIT)
		FROM dbo.tblModuli m
		WHERE
			m.Id NOT IN ('BAS', 'IMP')
			AND
				(
				@Id IS NULL
				OR NOT EXISTS (SELECT 1 FROM dbo.tblDominiModuli d WHERE d.Id = @Id AND d.IdModulo = m.Id)
				)
		ORDER BY m.Nome
		OPTION (RECOMPILE);

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

GO

