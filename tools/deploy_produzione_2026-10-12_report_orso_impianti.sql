/*
Deploy produzione 2026-10-12 - Rifiuti > Report: report "ORSO Impianti"

Da eseguire DOPO deploy_produzione_2026-10-11_report_rifiuti_soggetti.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I. Va pubblicata anche l'app (voce "ORSO Impianti" nella select dei report):
la SP si può eseguire prima dell'app, gli altri report non cambiano.
Regole: P3.10 - P3.14 di docs\regole\report.md (repo dell'app).

1. uspRifiutiRegistrazioni_get_Report: nuovo report OI "ORSO Impianti", i dati mensili per la scheda impianti
   di ORSO. Una riga per mese, operazione, EER e soggetto: ricevuti da terzi (T*) con il produttore, prodotti
   fuori dall'unità locale (RE), trattati internamente (I), consegnati a terzi (aT) con il destinatario, con
   comune e provincia del soggetto; in più la giacenza a fine mese per EER (residuo dei carichi DT, NP, RE
   all'ultimo giorno del mese), per i mesi conclusi.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

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
--   TT  Rifiuti trasportati da terzi                       aT, T*          + trasportatore
--   CT  Rifiuti consegnati a terzi (destinatari)           aT              + destinatario
--   IN  Rifiuti movimentati attraverso intermediari        aT, T*, T*aT, TR + intermediario
--   DG  Destinazione (R o D) dei rifiuti gestiti nell'unità locale   T*, I  + attività
--   DC  Destinazione (R o D) dei rifiuti consegnati a terzi          aT     + attività e destinatario
--   MV  Quantità rifiuti movimentati per CER               tutte, tranne M (materiali) e SI (stoccaggio istantaneo)
--   OI  ORSO Impianti                                      T*, RE, I, aT per mese e soggetto, più la giacenza a
--       fine mese: ramo a parte, con colonne e regole sue (descritte dove inizia)
-- Nei report con la colonna del soggetto (RT, TT, CT, IN, DC) entrano solo le registrazioni che lo indicano,
-- che sia una sede esterna o una sede dell'azienda: senza soggetto la registrazione non compare. Trasportatore
-- e intermediario sono il primo indicato sul movimento; il secondo e il terzo non contano.
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
		IF @Report IS NULL OR @Report NOT IN ('PR', 'PL', 'RT', 'TR', 'TT', 'CT', 'IN', 'DG', 'DC', 'MV', 'OI')
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

		-- ORSO Impianti: i dati mensili della scheda impianti di ORSO, per chi la compila. Una riga per mese,
		-- operazione, EER e soggetto: ricevuti da terzi (T*) con il produttore, prodotti fuori dall'unità locale
		-- (RE), trattati internamente (I), consegnati a terzi (aT) con il destinatario; per T* e I l'attività di
		-- recupero o smaltimento. Il soggetto ha comune e provincia (nazione se estero) e può mancare: la
		-- registrazione conta comunque. Gli stati fisici si sommano.
		-- In più la giacenza a fine mese, per EER: il residuo all'ultimo giorno del mese dei carichi di rifiuti
		-- non ricevuti da terzi (DT, NP, RE), cioè la quantità meno quanto prelevato dalle registrazioni fino a
		-- quel giorno (stesso calcolo di uspRifiutiGiacenze_get_Carichi_List). Solo per i mesi conclusi entro
		-- @DataA e non oltre oggi. I carichi ricevuti da terzi e i materiali non sono in questa giacenza.
		IF @Report = 'OI'
		BEGIN
			DECLARE @oggi DATE = GETDATE();
			DECLARE @fineUltima DATE = IIF(@DataA IS NULL OR @DataA > @oggi, @oggi, @DataA);
			DECLARE @fine DATE;

			-- I mesi partono da @DataDa, ma non prima della prima registrazione della sede (senza
			-- registrazioni nessun mese)
			SELECT @fine = EOMONTH(IIF(@DataDa > MIN(r.[Data]), @DataDa, MIN(r.[Data])))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			WHERE
				g.IdSede = @idSede
				AND r.Lock = 0;

			DECLARE @mesi TABLE (
				Fine DATE NOT NULL PRIMARY KEY
			);
			WHILE @fine <= @fineUltima
			BEGIN
				INSERT @mesi (Fine) VALUES (@fine);
				SET @fine = EOMONTH(DATEADD(MONTH, 1, @fine));
			END

			DECLARE @carichi TABLE (
				Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
				[Data] DATE NOT NULL,
				IdEer CHAR(6) COLLATE DATABASE_DEFAULT NULL,
				IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
				Quantita DECIMAL(18, 4) NOT NULL
			);
			INSERT @carichi (Id, [Data], IdEer, IdUnitaMisura, Quantita)
			SELECT
				r.Id,
				r.[Data],
				v.IdEer,
				v.IdUnitaMisura,
				v.Quantita
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			WHERE
				g.IdSede = @idSede
				AND r.Lock = 0
				AND v.IsRettifica = 0
				AND v.Quantita > 0
				AND m.IdOperazione IN ('C', 'M', 'F')
				AND r.[Data] <= @fineUltima
				AND
					(
					@IdRegistro IS NULL
					OR m.IdRegistro = @IdRegistro
					)
			OPTION (RECOMPILE);

			-- Quanto prelevato da ogni carico, con la data della registrazione che preleva: una registrazione
			-- annullata ha quantità effettiva zero e non consuma più il carico
			DECLARE @prelievi TABLE (
				Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
				[Data] DATE NOT NULL,
				Quantita DECIMAL(18, 4) NOT NULL
			);
			INSERT @prelievi (Id, [Data], Quantita)
			SELECT
				l.Id,
				p.[Data],
				l.Quantita
			FROM
				@carichi c
				INNER JOIN dbo.tblRifiutiRegistrazioniRelazioni l ON c.Id = l.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
			WHERE
				p.Lock = 0
				AND vp.Quantita > 0
				AND p.[Data] <= @fineUltima;

			WITH Movimenti AS (
				SELECT
					Mese = DATEFROMPARTS(YEAR(r.[Data]), MONTH(r.[Data]), 1),
					Ordine = CASE m.IdOperazione WHEN 'Z' THEN 1 WHEN 'F' THEN 2 WHEN 'R' THEN 3 ELSE 4 END,
					Operazione = CAST(o.Codice + ' - ' + o.Nome AS VARCHAR(110)),
					Eer = e.Nome,
					Descrizione = e.Descrizione,
					Attivita = IIF(m.IdOperazione IN ('Z', 'R'), a.Codice, NULL),
					IdSoggetto = s.Id,
					Soggetto = s.NomeCompleto,
					Comune = c.Nome,
					Provincia = CAST(IIF(pv.Id IS NULL, n.Nome, pv.Nome + ' (' + pv.Sigla + ')') AS VARCHAR(110)),
					Registrazioni = COUNT(*),
					Quantita = CAST(SUM(v.Quantita) AS DECIMAL(18, 2)),
					Unita = u.Codice
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
					INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
					LEFT JOIN dbo.tblUnitaMisura u ON v.IdUnitaMisura = u.Id
					LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
					LEFT JOIN dbo.tblSedi s ON s.Id =
						CASE m.IdOperazione
							WHEN 'Z' THEN m.IdSedeProduttoreDetentore
							WHEN 'S' THEN m.IdSedeDestinatario
						END
					LEFT JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
					LEFT JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
					LEFT JOIN dbo.tblComuni c ON i.IdComune = c.Id
					LEFT JOIN dbo.tblProvince pv ON c.IdProvincia = pv.Id
					LEFT JOIN dbo.tblNazioni n ON i.IdNazione = n.Id
				WHERE
					g.IdSede = @idSede
					AND r.Lock = 0
					AND v.IsRettifica = 0
					AND v.IsAnnullata = 0
					AND m.IdOperazione IN ('Z', 'F', 'R', 'S')
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
				GROUP BY
					DATEFROMPARTS(YEAR(r.[Data]), MONTH(r.[Data]), 1),
					m.IdOperazione,
					o.Codice,
					o.Nome,
					e.Nome,
					e.Descrizione,
					IIF(m.IdOperazione IN ('Z', 'R'), a.Codice, NULL),
					s.Id,
					s.NomeCompleto,
					c.Nome,
					pv.Id,
					pv.Nome,
					pv.Sigla,
					n.Nome,
					u.Codice
			),
			Residui AS (
				SELECT
					ms.Fine,
					c.IdEer,
					c.IdUnitaMisura,
					Residuo = c.Quantita - ISNULL(
						(SELECT SUM(p.Quantita)
						FROM @prelievi p
						WHERE
							p.Id = c.Id
							AND p.[Data] <= ms.Fine), 0)
				FROM
					@mesi ms
					INNER JOIN @carichi c ON c.[Data] <= ms.Fine
			),
			Giacenze AS (
				SELECT
					Mese = DATEFROMPARTS(YEAR(x.Fine), MONTH(x.Fine), 1),
					Ordine = 5,
					Operazione = CAST('Giacenza a fine mese' AS VARCHAR(110)),
					Eer = e.Nome,
					Descrizione = e.Descrizione,
					Attivita = CAST(NULL AS VARCHAR(3)),
					IdSoggetto = CAST(NULL AS CHAR(16)),
					Soggetto = CAST(NULL AS VARCHAR(200)),
					Comune = CAST(NULL AS VARCHAR(100)),
					Provincia = CAST(NULL AS VARCHAR(110)),
					Registrazioni = COUNT(*),
					Quantita = CAST(SUM(x.Residuo) AS DECIMAL(18, 2)),
					Unita = u.Codice
				FROM
					Residui x
					LEFT JOIN dbo.tblRifiutiEer e ON x.IdEer = e.Id
					LEFT JOIN dbo.tblUnitaMisura u ON x.IdUnitaMisura = u.Id
				WHERE x.Residuo > 0
				GROUP BY
					x.Fine,
					e.Nome,
					e.Descrizione,
					u.Codice
			)
			SELECT TOP (@MaxRighe + 1)
				[Mese] = RIGHT('0' + CAST(MONTH(x.Mese) AS VARCHAR(2)), 2) + '/' + CAST(YEAR(x.Mese) AS CHAR(4)),
				[Operazione] = x.Operazione,
				[EER] = x.Eer,
				[Descrizione] = x.Descrizione,
				[Attività] = x.Attivita,
				[Soggetto] = x.Soggetto,
				[Comune] = x.Comune,
				[Provincia] = x.Provincia,
				[Registrazioni] = x.Registrazioni,
				[Quantità] = x.Quantita,
				[Unità] = x.Unita
			FROM
				(SELECT * FROM Movimenti
				UNION ALL
				SELECT * FROM Giacenze) x
			ORDER BY
				x.Mese,
				x.Ordine,
				x.Eer,
				x.Attivita,
				x.Soggetto,
				x.IdSoggetto,
				x.Unita
			OPTION (RECOMPILE);

			GOTO BRANCH_END;
		END

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
			-- Report con la colonna del soggetto: solo le registrazioni che lo indicano, interno o esterno
			AND
				(
				@soggetto IS NULL
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
