/*
	Deploy produzione - 2026-09-11 - Campo Registri.ConservazioniXfirMax (limite conservazioni xFIR per Dominio)

	Contenuto di questo script (solo 4_0_ecomatico; presuppone che deploy_produzione_2026-09-10_domini_conservazionixfirmax.sql
	sia già stato eseguito, dato che il controllo qui sotto legge tblDomini.ConservazioniXfirMax):

	Motivazione: nuovo campo "Conservazioni max xFIR" in Rentri/Registri/Edit, abilitato/disabilitato insieme
	al checkbox "Conservazione" già presente (collegato all'hub RENTRI). Alla modifica di un registro, la
	somma di questo valore su tutti i registri dello stesso Dominio con Conservazione=1 non deve superare
	tblDomini.ConservazioniXfirMax (limite già configurabile per Dominio, applicato ora per la prima volta).

	1) ALTER TABLE dbo.tblRifiutiRegistri ADD ConservazioniXfirMax INT NULL (idempotente, guardato con
	   IF NOT EXISTS - la colonna è già presente su dev al momento di questo deploy, non è però
	   garantito che lo sia già anche in produzione).

	2) CREATE OR ALTER PROCEDURE dbo.uspRentriRegistri_get: aggiunta ConservazioniXfirMax = ISNULL(g.ConservazioniXfirMax, 0)
	   alla SELECT (letta da tblRifiutiRegistri, non dall'hub - a differenza degli altri campi Conservazione*).

	3) CREATE OR ALTER PROCEDURE dbo.uspRentriRegistri_upd:
	   - nuovo parametro @ConservazioniXfirMax INT = 0
	   - nuovo blocco di validazione (attivo solo se @Conservazione=1, subito dopo quello gemello già
	     esistente per tblDomini.ConservazioniMax): somma il nuovo valore con quello degli altri registri
	     del Dominio con Conservazione=1, blocca se supera tblDomini.ConservazioniXfirMax
	   - nuovo UPDATE diretto su dbo.tblRifiutiRegistri (mancava del tutto prima: la SP non aveva mai scritto
	     nulla sulla tabella locale, solo sull'hub e su tblRentriRegistri)

	Verificato su DB dev: colonna già presente, le 2 SP ridistribuite senza errori di compilazione,
	OBJECT_ID(...) valido su entrambe dopo il redeploy. Round-trip completo (get/upd/get) con superamento
	del limite e messaggio di errore dedicato non testato con una sessione reale (nessuna disponibile in
	dev con permesso RNT livello 2 al momento dello sviluppo) - da verificare in UI prima o subito dopo
	il deploy in produzione.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-11_registri_conservazionixfirmax.sql
	(il flag -f 65001 è obbligatorio per non corrompere gli accenti italiani)
*/
--------------------------------------------------------------------------------
-- 1) dbo.tblRifiutiRegistri: aggiunge colonna (idempotente)
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiRegistri') AND name = 'ConservazioniXfirMax')
BEGIN
	ALTER TABLE dbo.tblRifiutiRegistri ADD ConservazioniXfirMax INT NULL;
END
GO

--------------------------------------------------------------------------------
-- 2) dbo.uspRentriRegistri_get
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get]
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistri WHERE Id = @Id AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registro non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.Nome,
			g.IdSede,
			SedeNome = s.NomeCompleto,
			s.IndirizzoCompleto,
			Identificativo = h.Identificativo,
			BloccoFormulari = h.BloccoFormulari,
			DataInizioInvio = h.DataInizioInvio,
			IsCollegato = CAST(IIF(r.IdRentri IS NULL, 0, 1) AS BIT),
			Conservazione = ISNULL(h.Conservazione, 0),
			ConservazioneNome = ISNULL(h.ConservazioneNome, ''),
			ConservazioneCodiceFiscale = ISNULL(h.ConservazioneCodiceFiscale, ''),
			ConservazioneEmail = ISNULL(h.ConservazioneEmail, ''),
			ConservazioniXfirMax = ISNULL(g.ConservazioniXfirMax, 0)
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRentriRegistri r ON g.Id = r.Id
			LEFT JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
		WHERE g.Id = @Id;

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

--------------------------------------------------------------------------------
-- 3) dbo.uspRentriRegistri_upd
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Scollega BIT = 0,
	@Identificativo VARCHAR(20) = NULL,
	@BloccoFormulari VARCHAR(10) = NULL,
	@DataInizioInvio DATE = NULL,
	@Conservazione BIT = 0,
	@ConservazioneNome VARCHAR(50) = NULL,
	@ConservazioneCodiceFiscale VARCHAR(20) = NULL,
	@ConservazioneEmail VARCHAR(50) = NULL,
	@ConservazioniXfirMax INT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Scollega = ISNULL(@Scollega, 0);
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));
		SET @BloccoFormulari = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@BloccoFormulari, 0, 1));
		SET @Conservazione = ISNULL(@Conservazione, 0);
		SET @ConservazioneNome = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneNome, 0, 1);
		SET @ConservazioneCodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneCodiceFiscale, 0, 1);
		SET @ConservazioneEmail = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneEmail, 0, 1);
		SET @ConservazioniXfirMax = ISNULL(@ConservazioniXfirMax, 0);

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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede del registro
		DECLARE @idSede CHAR(16);
		SELECT @idSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRentri CHAR(16);
		SELECT @idRentri = IdRentri
		FROM dbo.tblRentriRegistri
		WHERE Id = @Id;

		-- Scollegamento esplicito: la conservazione sostitutiva non ha senso su un registro non
		-- collegato a RENTRI, azzerata insieme allo scollegamento (libera anche il posto nel
		-- conteggio ConservazioniMax del Dominio)
		IF @Scollega = 1
		BEGIN
			BEGIN TRANSACTION;
				IF @idRentri IS NOT NULL
				BEGIN
					DELETE dbo.tblRentriRegistri WHERE Id = @Id;
					DELETE [1_0_rentri]..tblRegistri WHERE Id = @idRentri;
				END
			COMMIT TRANSACTION;
			SELECT ReturnValue = @returnValue;
			GOTO BRANCH_END;
		END

		-- Il registro non ha una propria credenziale: eredita sempre la Primaria (Pos=0) della Sede su cui si appoggia
		DECLARE @idRentriSede CHAR(16);
		SELECT @idRentriSede = IdRentri
		FROM dbo.tblRentriCredenzialiSedi
		WHERE
			IdSede = @idSede
			AND Pos = 0;

		IF @idRentriSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista già un altro registro con lo stesso identificativo
		IF @Identificativo IS NOT NULL AND EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriRegistri r
				INNER JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
			WHERE
				r.Id <> @Id
				AND h.Identificativo = @Identificativo
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro registro con lo stesso identificativo è già presente';
			GOTO BRANCH_END;
		END

		-- Limite di registri con conservazione sostitutiva abilitata per Dominio (tblDomini.ConservazioniMax);
		-- @Id escluso dal conteggio: se già abilitata su questo stesso registro non va contata come "nuova"
		IF @Conservazione = 1
		BEGIN
			DECLARE @idDominio CHAR(16);
			SELECT @idDominio = IdDominio FROM dbo.tblSessioni WHERE Id = @IdSessione;

			IF ISNULL((SELECT ConservazioniMax FROM dbo.tblDomini WHERE Id = @idDominio), 0)
				<=
				(SELECT COUNT(*)
				 FROM
					 dbo.tblRifiutiRegistri r
					 INNER JOIN dbo.tblSediInterne i ON r.IdSede = i.Id
					 INNER JOIN dbo.tblRentriRegistri rr ON r.Id = rr.Id
					 INNER JOIN [1_0_rentri]..tblRegistri h ON rr.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
				 WHERE
					 i.IdDominio = @idDominio
					 AND h.Conservazione = 1
					 AND r.Lock = 0
					 AND r.Id <> @Id
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'È stato raggiunto il numero massimo di registri con conservazione sostitutiva abilitata';
				GOTO BRANCH_END;
			END

			-- Limite di conservazioni xFIR per Dominio (tblDomini.ConservazioniXfirMax); somma il nuovo
			-- valore con quello degli altri registri con conservazione attiva sullo stesso Dominio
			IF ISNULL((SELECT ConservazioniXfirMax FROM dbo.tblDomini WHERE Id = @idDominio), 0)
				<
				(@ConservazioniXfirMax
				 + ISNULL((SELECT SUM(r.ConservazioniXfirMax)
					 FROM
						 dbo.tblRifiutiRegistri r
						 INNER JOIN dbo.tblSediInterne i ON r.IdSede = i.Id
						 INNER JOIN dbo.tblRentriRegistri rr ON r.Id = rr.Id
						 INNER JOIN [1_0_rentri]..tblRegistri h ON rr.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
					 WHERE
						 i.IdDominio = @idDominio
						 AND h.Conservazione = 1
						 AND r.Lock = 0
						 AND r.Id <> @Id), 0))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'È stato raggiunto il numero massimo di conservazioni xFIR consentito per il Dominio';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			-- Igiene dati: azzerato quando la conservazione e' disattivata, cosi' un futuro utilizzo
			-- del campo che dimentichi il filtro h.Conservazione=1 non trova valori residui fuorvianti
			-- (la validazione sopra e' comunque gia' corretta di per se', perche' filtra su h.Conservazione)
			UPDATE dbo.tblRifiutiRegistri
			SET ConservazioniXfirMax = IIF(@Conservazione = 1, @ConservazioniXfirMax, 0)
			WHERE Id = @Id;

			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblRegistri (Id, IdSede, Identificativo, BloccoFormulari, DataInizioInvio, Conservazione, ConservazioneNome, ConservazioneCodiceFiscale, ConservazioneEmail)
				VALUES (@idRentri, @idRentriSede, @Identificativo, @BloccoFormulari, @DataInizioInvio, @Conservazione, @ConservazioneNome, @ConservazioneCodiceFiscale, @ConservazioneEmail);

				INSERT INTO dbo.tblRentriRegistri (Id, IdRentri)
				VALUES (@Id, @idRentri);
			END
			ELSE
			BEGIN
				UPDATE [1_0_rentri]..tblRegistri
				SET
					IdSede = @idRentriSede,
					Identificativo = @Identificativo,
					BloccoFormulari = @BloccoFormulari,
					DataInizioInvio = @DataInizioInvio,
					Conservazione = @Conservazione,
					ConservazioneNome = @ConservazioneNome,
					ConservazioneCodiceFiscale = @ConservazioneCodiceFiscale,
					ConservazioneEmail = @ConservazioneEmail
				WHERE Id = @idRentri;
			END
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
