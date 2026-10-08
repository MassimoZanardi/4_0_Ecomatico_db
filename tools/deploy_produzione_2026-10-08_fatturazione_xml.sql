/*
Deploy produzione 2026-10-08 - Fatturazione > Fatture clienti > Genera file XML (fattura elettronica)

Da eseguire DOPO deploy_produzione_2026-10-08_fatturazione_dati_fiscali.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

1. tblFatture.DataXml e ProgressivoXml (data e progressivo dell'ultimo file generato),
   tblFattureDatiFiscali.ProgressivoInvio (ultimo progressivo dell'azienda).
2. ufnFatture_get_XmlIntervallo: fatture clienti dell'intervallo scelto.
3. uspFatture_get_Xml_List: testate, righe e rate per il file.
4. uspFatture_upd_Xml: assegna i progressivi, segna la generazione e mette in sola lettura.

Va deployato insieme all'app: il file viene composto dall'applicazione (FatturaXmlService).

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'Colonne per la generazione del file XML';
GO
-- Fatturazione > Fatture clienti > Genera file XML (fattura elettronica): colonne che tracciano la generazione.
-- tblFatture.DataXml = quando è stato generato l'ultimo file della fattura; ProgressivoXml = progressivo del
-- file (5 caratteri, quello del nome del file e del blocco DatiTrasmissione).
-- tblFattureDatiFiscali.ProgressivoInvio = ultimo progressivo assegnato per l'azienda.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già le colonne.
SET NOCOUNT ON;
GO
IF COL_LENGTH('dbo.tblFatture', 'DataXml') IS NULL
	ALTER TABLE dbo.tblFatture ADD DataXml SMALLDATETIME NULL;
IF COL_LENGTH('dbo.tblFatture', 'ProgressivoXml') IS NULL
	ALTER TABLE dbo.tblFatture ADD ProgressivoXml VARCHAR(5) NULL;
IF COL_LENGTH('dbo.tblFattureDatiFiscali', 'ProgressivoInvio') IS NULL
	ALTER TABLE dbo.tblFattureDatiFiscali ADD ProgressivoInvio INT NULL;
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
-- stato generato il file (DataXml). Usata dalle uspFatture_get_Xml*_List, che devono vedere le stesse fatture.
CREATE OR ALTER FUNCTION dbo.ufnFatture_get_XmlIntervallo
(
	@IdSessione CHAR(16),
	@DalNumero INT,
	@AlNumero INT,
	@Anno INT,
	@Sezionale CHAR(1),
	@EscludiGenerate BIT
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
		AND f.Numero >= ISNULL(@DalNumero, 1)
		AND f.Numero <= ISNULL(@AlNumero, 2147483647)
		AND f.DataEmissione >= DATEFROMPARTS(@Anno, 1, 1)
		AND f.DataEmissione < DATEFROMPARTS(@Anno + 1, 1, 1)
		AND
			(
			@Sezionale IS NULL
			OR (@Sezionale = '0' AND f.Sezionale IS NULL)
			OR f.Sezionale = @Sezionale
			)
		AND (ISNULL(@EscludiGenerate, 0) = 0 OR f.DataXml IS NULL)
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
-- I controlli sui dati mancanti e la composizione del file sono nell'applicazione (FatturaXmlService).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Xml_List
	@IdSessione CHAR(16) = NULL,
	@Elenco CHAR(1) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@Sezionale CHAR(1) = NULL,
	@EscludiGenerate BIT = 0
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
		IF @Anno IS NULL OR @Anno < 1900 OR @Anno > 9998
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
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate) x
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
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate) x
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
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate) x
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

PRINT 'uspFatture_upd_Xml';
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
			-- Progressivi dell'azienda riservati con il blocco sulla riga dei dati fiscali
			UPDATE dbo.tblFattureDatiFiscali WITH (UPDLOCK, HOLDLOCK)
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

