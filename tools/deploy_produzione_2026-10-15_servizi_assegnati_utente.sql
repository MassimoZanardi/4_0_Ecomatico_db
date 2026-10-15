/*
Deploy produzione 2026-10-15 - Servizi assegnati: solo i propri servizi, assegnazione solo dagli amministratori

Indipendente dagli altri script. Rieseguibile. Eseguire con sqlcmd -f 65001 -I (oppure da SSMS).
Va deployato insieme all'app (Servizi > scheda: salvando senza utenti spuntati si tolgono le assegnazioni).

1. uspServiziAssegnati_get, _upd, _del: oltre alla sede del calendario, il servizio deve essere assegnato all'utente
   della sessione (prima un utente poteva aprire, modificare e cancellare il servizio di un collega conoscendone
   l'indirizzo). Regola S7.3.
2. uspEventi_get_Utenti_SelectList e uspEventi_upd_Utente: solo un amministratore (ruolo AD), come già la pagina.
   uspEventi_upd_Utente con @Reset = 1 e senza utente toglie tutte le assegnazioni (prima togliere la spunta a tutti
   gli utenti non aveva effetto). Regola S6.3.
Regole in docs/regole/scadenze-servizi.md (repo app).
*/

-- ===== uspServiziAssegnati_get
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

-- ===== uspServiziAssegnati_upd
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
	@InGiornata BIT = 0
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

-- ===== uspServiziAssegnati_del
CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_del]
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

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il servizio esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblServizi
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

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

		DECLARE @lock INT;
		SELECT @lock = e.Lock
		FROM dbo.tblServizi s
		INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE s.Id = @Id;

		-- ── CASO 1: servizio attivo (Lock = 0) → soft delete ─────────────
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				UPDATE e
				SET Lock = 4
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.Id = @Id
					AND e.Lock = 0;

				UPDATE e
				SET Lock = 4
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblRicorrenzeEccezioni e ON s.IdEvento = e.Id
				WHERE
					s.Id = @Id
					AND e.Lock = 0;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			-- Log FUORI dalla transazione
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: servizio in bozza (Lock = 2) → hard delete ───────────
		ELSE IF @lock = 2
		BEGIN
			-- Legge tutti i dati necessari FUORI dalla transazione
			DECLARE @IdEvento CHAR(16);
			SELECT @IdEvento = IdEvento
			FROM dbo.tblServizi
			WHERE Id = @Id;

			DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
			DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;

			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

			BEGIN TRANSACTION;
				-- Figlie di tblEventi (FK dirette) → prima di tblEventi
				DELETE dbo.tblEventiUtenti
				WHERE Id = @IdEvento;
				DELETE dbo.tblRicorrenzeEccezioni
				WHERE IdEvento = @IdEvento;
				DELETE dbo.tblRicorrenze
				WHERE Id = @IdEvento;
				DELETE dbo.tblEventiProprieta
				WHERE Id = @IdEvento;
				DELETE dbo.tblEventiFirme
				WHERE Id = @IdEvento;
				DELETE dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				-- Servizio e Osepe associati
				DELETE dbo.tblServiziOsepe
				WHERE Id = @Id;
				DELETE dbo.tblServizi
				WHERE Id = @Id;

				-- Firme (dopo aver eliminato tblEventiFirme)
				DELETE dbo.tblFirme
				WHERE Id IN (@idFirmaRichiedente, @idFirmaEsecutore);

				-- Evento
				DELETE dbo.tblEventi
				WHERE Id = @IdEvento;

				-- Pulizia log e Id
				DELETE dbo.tblIdCancellati
				WHERE Id IN (@Id, @IdEvento);
				DELETE dbo.tblIdLog
				WHERE Id IN (@Id, @IdEvento);
				DELETE dbo.tblId
				WHERE Id IN (@Id, @IdEvento);
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
		THROW 50001, @returnMessage, 1
	END

END;


GO

-- ===== uspEventi_get_Utenti_SelectList
CREATE OR ALTER PROCEDURE [dbo].[uspEventi_get_Utenti_SelectList]
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
			@IdFunzione = 'SRA',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli utenti del dominio li vede, e li assegna, solo un amministratore
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			WHERE
				s.Id = @IdSessione
				AND u.IdRuolo = 'AD'
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: mancava la verifica che @Id (l'Evento) appartenesse a un
		-- calendario/sede accessibile dalla sessione — presente invece nei SP
		-- "fratelli" upd_Utente/upd_Proprieta. Stesso pattern applicato qui.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE e.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Evento non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida o scaduta';
			GOTO BRANCH_END;
		END

		SELECT
			Id = u.Id,
			[Text] = u.Email,
			Selected = CAST(IIF(e.IdUtente IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblEventiUtenti e ON u.Id = e.IdUtente AND e.Id = @Id
		WHERE
			u.IdDominio = @idDominio
			AND u.[Master] = 0
			AND u.Lock = 0
		ORDER BY
			Selected DESC, [Text];

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

-- ===== uspEventi_upd_Utente
CREATE OR ALTER PROCEDURE [dbo].[uspEventi_upd_Utente]
	@Id CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
	@Reset BIT = 0,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza utente, con @Reset = 1, si tolgono tutte le assegnazioni dell'evento (nessun utente spuntato)
		IF @IdUtente IS NULL AND ISNULL(@Reset, 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
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
			@IdFunzione = 'SRA',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli utenti li assegna solo un amministratore, l'unico che vede gli utenti del dominio
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			WHERE
				s.Id = @IdSessione
				AND u.IdRuolo = 'AD'
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Togliere tutte le assegnazioni: basta che l'evento sia di un calendario accessibile
		IF @IdUtente IS NULL
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblEventi e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
				WHERE e.Id = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Evento o utente non validi';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblEventiUtenti
				WHERE Id = @Id;
			COMMIT TRANSACTION;

			SELECT @returnValue AS ReturnValue;
			GOTO BRANCH_END;
		END

		-- Verifica che l'evento appartenga a un calendario/sede accessibile dalla sessione
		-- e che l'utente da associare appartenga allo stesso dominio della sede
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSediInterne si ON c.IdSede = si.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = si.IdDominio
			WHERE
				e.Id = @Id
				AND u.Id = @IdUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Evento o utente non validi';
			GOTO BRANCH_END;
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.IdEvento AND z.Lock = 0
			WHERE
				e.Id = @Id
				AND r.Id IS NOT NULL
				AND z.IdEvento IS NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Gli utenti possono essere associati solo ad eventi non ricorrenti o ad occorrenze modificate';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @Reset = 1
				DELETE dbo.tblEventiUtenti
				WHERE Id = @Id;
			ELSE
				DELETE dbo.tblEventiUtenti
				WHERE
					Id = @Id
					AND IdUtente = @IdUtente;

			INSERT INTO dbo.tblEventiUtenti (Id, IdUtente)
			VALUES (@Id, @IdUtente);
		COMMIT TRANSACTION;

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

