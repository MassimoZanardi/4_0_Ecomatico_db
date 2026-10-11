/*
Deploy produzione 2026-10-11 - Rifiuti > Report: soggetto in colonna

Da eseguire DOPO deploy_produzione_2026-10-11_registrazioni_numerazione.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I. Nessuna modifica all'app: si può deployare da solo.
Regola: P3.9 di docs\regole\report.md (repo dell'app).

1. uspRifiutiRegistrazioni_get_Report: nei report con la colonna del soggetto (ricevuti da terzi, trasportati
   da terzi, consegnati a terzi, attraverso intermediari, destinazione dei consegnati a terzi) entrano solo le
   registrazioni che indicano quel soggetto, che sia una sede esterna o una sede dell'azienda. "Trasportati da
   terzi" non richiede più un trasportatore esterno; senza soggetto la registrazione non compare.

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
GO
