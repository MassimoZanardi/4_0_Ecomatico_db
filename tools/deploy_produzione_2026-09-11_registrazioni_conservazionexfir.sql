/*
	Deploy produzione - 2026-09-11 - Conservazione sostitutiva xFIR (Rifiuti/Registrazioni/Index)

	Contenuto di questo script (solo 4_0_ecomatico):

	Motivazione: nuova azione "RENTRI - Conservazione sostitutiva xFIR" in Rifiuti/Registrazioni/Index,
	che porta in conservazione sostitutiva gli xFIR dei formulari digitali con stato Accettato/
	RespintoAccettatoParzialmente (FIR concluso) nell'intervallo di registrazioni indicato, con verifica
	della quota annua per Registro (tblRifiutiRegistri.ConservazioniXfirMax, vedi
	deploy_produzione_2026-09-11_registri_conservazionixfirmax.sql - presuppone che sia già stato
	eseguito). L'endpoint hub POST formulario-digitale/{app}/conservazione/{id}/{numero} esiste già in
	1_0_RentriApi (nessuna modifica lì): a differenza degli endpoint gemelli (DataCopia/DataTrasmissione)
	non scrive lo stato su 4_0_ecomatico, quindi lo fa l'app dopo ogni chiamata riuscita.

	1) ALTER TABLE dbo.tblRifiutiMovimenti ADD (idempotente, guardato con IF NOT EXISTS):
	   - RentriFormularioDataConservazione SMALLDATETIME NULL
	   - RentriFormularioInviiConservazione INT NULL

	2) CREATE OR ALTER PROCEDURE dbo.uspRentriFormulari_get_ConservazioneXfir_List: elenco dei movimenti
	   coinvolti (stato Accettato/RespintoAccettatoParzialmente, intervallo numero/anno, esclusione
	   opzionale dei già conservati). Nessun JOIN a tblRifiutiFormulari - includerebbe erroneamente solo
	   i movimenti con un proprio formulario, escludendo quelli IsIntegrazioneFir=1.

	3) CREATE OR ALTER PROCEDURE dbo.uspRentriFormulari_get_ConservazioneXfir_Limite: quota (Max/già
	   utilizzati) del Registro in contesto per l'anno indicato.

	4) CREATE OR ALTER PROCEDURE dbo.uspRifiutiMovimenti_upd_Conservazione: aggiornamento in blocco (via
	   OPENJSON su un array di Id) dei movimenti portati con successo in conservazione, un'unica chiamata
	   a fine loop lato C# invece di N round-trip separati.

	Verificato su DB dev: le 3 SP deployate senza errori di compilazione, CRLF/BOM verificati sull'oggetto
	deployato (accenti italiani controllati via UNICODE(), non solo a vista - il terminale usato in
	sviluppo non li renderizza sempre correttamente). Smoke test con sessione fittizia: diniego pulito su
	tutte e 3, nessun errore SQL. Sintassi OPENJSON verificata isolatamente. Round-trip completo (elenco/
	limite/update) con dati xFIR reali non testato: nessuna sessione con formulari digitali chiusi
	disponibile in dev al momento dello sviluppo - da verificare in UI prima o subito dopo il deploy.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-11_registrazioni_conservazionexfir.sql
	(il flag -f 65001 è obbligatorio per non corrompere gli accenti italiani)
*/
--------------------------------------------------------------------------------
-- 1) dbo.tblRifiutiMovimenti: aggiunge le colonne (idempotente)
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioDataConservazione')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioDataConservazione SMALLDATETIME NULL;
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioInviiConservazione')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioInviiConservazione INT NULL;
END
GO
--------------------------------------------------------------------------------
-- 2) dbo.uspRentriFormulari_get_ConservazioneXfir_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Elenco dei movimenti RENTRI coinvolti nella conservazione sostitutiva xFIR (Rifiuti/Registrazioni/
-- Index, azione "RENTRI - Conservazione sostitutiva xFIR"): FIR digitali con stato Accettato/
-- RespintoAccettatoParzialmente (stessi 2 stati di Constants.Rentri.FormularioStatiOk lato C#, gia'
-- usati con lo stesso significato in uspRentriFormulari_get_TrasmissioneMassiva_List - "ha concluso il
-- suo ciclo di vita" per Accettato), filtrati per intervallo di numero di registrazione nell'anno
-- indicato. Nessun JOIN a tblRifiutiFormulari (a differenza di TrasmissioneMassiva_List): i campi
-- Rentri* vivono su tblRifiutiMovimenti proprio per coprire anche i movimenti IsIntegrazioneFir=1
-- senza un proprio formulario (vedi RentriFormularioStato spostato da tblRifiutiFormulari), un JOIN a
-- f li escluderebbe. Nessun filtro RentriFormularioDataCopia (non e' valorizzato per i movimenti
-- IsIntegrazioneFir=1 lato integrazione): lo stato Accettato/RespintoAccettatoParzialmente basta da
-- solo a indicare il FIR concluso. Nessun filtro sulla pericolosita' del rifiuto (a differenza di
-- uspRentriFormulari_get_TrasmissioneMassiva_List): la conservazione riguarda il documento digitale,
-- non l'obbligo di trasmissione dei soli pericolosi.
-- @EscludiGiaConservati: se 1 (default), esclude i formulari con RentriFormularioDataConservazione
-- gia' valorizzata. Riusata sia per il conteggio (COUNT sul risultato) sia per l'invio in
-- conservazione sia per il download del pacchetto xFIR (loop lato C# su Id/FormularioNumero - Id e'
-- l'Id del MOVIMENTO, non del formulario: usato poi da uspRifiutiMovimenti_upd_Conservazione).
-- TOP (101): il limite applicativo per singola tranche e' 100 (Constants.Rentri.ConservazioneXfirMaxTranche
-- lato C#) - la 101a riga, se presente, serve solo a segnalare che ce ne sono altri oltre ai 100
-- effettivamente lavorati (RentriFormularioService taglia sempre a 100), senza una seconda query di COUNT.
-- exec dbo.uspRentriFormulari_get_ConservazioneXfir_List @IdSessione='...', @DalNumero=1, @AlNumero=999, @Anno=2026, @EscludiGiaConservati=1
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFormulari_get_ConservazioneXfir_List]
	@IdSessione CHAR(16) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@EscludiGiaConservati BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @EscludiGiaConservati = ISNULL(@EscludiGiaConservati, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''intervallo di numero e l''anno';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (101)
			m.Id,
			m.IdRegistro,
			FormularioNumero = m.FormularioNumero
		FROM
			dbo.tblRifiutiMovimenti m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON r.IdMovimento = m.Id AND r.Lock < 2
		WHERE
			e.Id = @IdSessione
			AND m.RentriFormularioStato IN ('Accettato', 'RespintoAccettatoParzialmente')
			AND (@EscludiGiaConservati = 0 OR m.RentriFormularioDataConservazione IS NULL)
			AND r.Numero BETWEEN @DalNumero AND @AlNumero
			AND YEAR(r.[Data]) = @Anno
		ORDER BY r.Numero;

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

END
GO
--------------------------------------------------------------------------------
-- 3) dbo.uspRentriFormulari_get_ConservazioneXfir_Limite
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Quota di conservazioni xFIR per il Registro in contesto (Rifiuti/Registrazioni/Index, azione
-- "RENTRI - Conservazione sostitutiva xFIR"): Max = tblRifiutiRegistri.ConservazioniXfirMax (limite
-- annuo configurato in Rentri/Registri/Edit), GiaUtilizzati = somma di
-- tblRifiutiMovimenti.RentriFormularioInviiConservazione gia' consumata nello stesso anno solare
-- indicato (@Anno), sullo stesso Registro. Il confronto con l'esito di
-- uspRentriFormulari_get_ConservazioneXfir_List (nuovi xFIR coinvolti) resta lato C#.
-- exec dbo.uspRentriFormulari_get_ConservazioneXfir_Limite @IdSessione='...', @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFormulari_get_ConservazioneXfir_Limite]
	@IdSessione CHAR(16) = NULL,
	@Anno INT = NULL
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
		IF @Anno IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''anno';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Max = ISNULL(g.ConservazioniXfirMax, 0),
			GiaUtilizzati = ISNULL((
				SELECT SUM(m.RentriFormularioInviiConservazione)
				FROM
					dbo.tblRifiutiMovimenti m
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
				WHERE
					m.IdRegistro = g.Id
					AND r.Lock < 2
					AND YEAR(r.[Data]) = @Anno
			), 0)
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
		WHERE e.Id = @IdSessione;

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

END
GO

--------------------------------------------------------------------------------
-- 4) dbo.uspRifiutiMovimenti_upd_Conservazione
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Aggiornamento in blocco dei movimenti portati con successo in conservazione sostitutiva xFIR
-- (Rifiuti/Registrazioni/Index, azione "RENTRI - Conservazione sostitutiva xFIR"): chiamata una sola
-- volta a fine loop lato C# (RentriFormularioService.ConservazioneXfirInviaAsync) con l'elenco degli
-- Id dei movimenti per cui la chiamata all'hub e' andata a buon fine, invece di N round-trip
-- separati - stesso principio di uspRentriRegistrazioni_upd_Sincronizza (unico altro precedente in
-- questo repo per un parametro JSON-array), qui pero' senza cursore perche' e' un semplice elenco di
-- Id, non righe con piu' campi: basta un UPDATE set-based con JOIN su OPENJSON.
-- @Ids: JSON array di Id movimento, es. ["fd73e743a19b44c0","..."]
-- exec dbo.uspRifiutiMovimenti_upd_Conservazione @IdSessione='...', @Ids='["fd73e743a19b44c0"]'
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_upd_Conservazione]
	@IdSessione CHAR(16) = NULL,
	@Ids NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @aggiornati INT = 0;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Ids IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Ids non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		UPDATE m
		SET
			RentriFormularioDataConservazione = GETDATE(),
			RentriFormularioInviiConservazione = ISNULL(m.RentriFormularioInviiConservazione, 0) + 1
		FROM
			dbo.tblRifiutiMovimenti m
			INNER JOIN OPENJSON(@Ids) j ON m.Id = j.[value]
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
		WHERE e.Id = @IdSessione;

		SET @aggiornati = @@ROWCOUNT;

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

	SELECT Aggiornati = @aggiornati;

END
GO
