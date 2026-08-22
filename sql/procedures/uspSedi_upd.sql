CREATE OR ALTER PROCEDURE [dbo].[uspSedi_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@InternaEsterna CHAR(1) = NULL,
	@IdTipo CHAR(1) = NULL,
	@Disabilitata BIT = 0,
	@UnitaLocale BIT = 0,
	@Nome VARCHAR(50) = NULL,
	@Cognome VARCHAR(50) = NULL,
	@PartitaIva VARCHAR(20) = NULL,
	@CodiceFiscale VARCHAR(20) = NULL,
	@Codice VARCHAR(20) = NULL,
	@Note VARCHAR(1000)= NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@NumeroCivico VARCHAR(10) = NULL,
	@CAP VARCHAR(10) = NULL,
	@Localita VARCHAR(50) = NULL,
	@IDComune VARCHAR(50) = NULL,
	@IDNazione CHAR(3) = '380',
	@Telefono0 VARCHAR(100) = NULL,
	@Telefono1 VARCHAR(100) = NULL,
	@Telefono2 VARCHAR(100) = NULL,
	@Email0 VARCHAR(100) = NULL,
	@Email1 VARCHAR(100) = NULL,
	@Email2 VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @InternaEsterna = NULLIF(LTRIM(RTRIM(@InternaEsterna)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');

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
		IF @InternaEsterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @InternaEsterna non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdTipo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idFunzione CHAR(3) = IIF(@InternaEsterna = 'I', 'AZI', 'ANS');
		DECLARE @permesso TINYINT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblSedi
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sede non trovata';
			GOTO BRANCH_END;
		END

		IF @InternaEsterna = 'E'
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @Id
				AND Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
					AND s.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede condivisa da altre aziende non può essere modificata';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @InternaEsterna = 'I'
		BEGIN
			-- Titolarità: Admin dello stesso Dominio della sede, oppure Admin di un Dominio Master.
			-- Il bypass Master è intenzionale (confermato dall'utente): un Master-admin deve poter
			-- cancellare/modificare aziende interne di qualsiasi dominio, non solo del proprio.
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @Id
				AND Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
				INNER JOIN dbo.tblUtenti a ON i.IdDominio = a.IdDominio
				INNER JOIN dbo.tblSessioni e ON a.Id = e.IdUtente
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
					AND a.IdRuolo = 'AD'
					AND a.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
				WHERE
					e.Id = @IdSessione
					AND ut.IdRuolo = 'AD'
					AND ut.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
		END

		-- Formattazione parametri opzionali
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Cognome = dbo.ufnStringhe_get_SenzaSpazi(@Cognome, 0, 1);
		SET @PartitaIva = dbo.ufnStringhe_get_SenzaSpazi(@PartitaIva, 0, 1);
		SET @CodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1);
		SET @Codice = dbo.ufnStringhe_get_SenzaSpazi(@Codice, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);
		SET @Indirizzo = dbo.ufnStringhe_get_SenzaSpazi(@Indirizzo, 0, 1);
		SET @NumeroCivico = dbo.ufnStringhe_get_SenzaSpazi(@NumeroCivico, 0, 1);
		SET @CAP = dbo.ufnStringhe_get_SenzaSpazi(@CAP, 0, 1);
		SET @Localita = dbo.ufnStringhe_get_SenzaSpazi(@Localita, 0, 1);
		SET @IDComune = dbo.ufnStringhe_get_SenzaSpazi(@IDComune, 0, 1);
		SET @IDNazione = dbo.ufnStringhe_get_SenzaSpazi(@IDNazione, 0, 1);
		SET @Telefono0 = dbo.ufnStringhe_get_SenzaSpazi(@Telefono0, 0, 1);
		SET @Telefono1 = dbo.ufnStringhe_get_SenzaSpazi(@Telefono1, 0, 1);
		SET @Telefono2 = dbo.ufnStringhe_get_SenzaSpazi(@Telefono2, 0, 1);
		SET @Email0 = dbo.ufnStringhe_get_SenzaSpazi(@Email0, 0, 1);
		SET @Email1 = dbo.ufnStringhe_get_SenzaSpazi(@Email1, 0, 1);
		SET @Email2 = dbo.ufnStringhe_get_SenzaSpazi(@Email2, 0, 1);

		DECLARE @idIndirizzo CHAR(16);
		DECLARE @isNuovoIndirizzo BIT;

		SELECT @idIndirizzo = IdIndirizzo
		FROM dbo.tblSediIndirizzi
		WHERE Id = @Id;

		SET @isNuovoIndirizzo = IIF(@idIndirizzo IS NULL, 1, 0);

		IF @isNuovoIndirizzo = 1
			EXEC dbo.uspId_get
				@IdSessione = @IdSessione,
				@Conferma = 1,
				@Id = @idIndirizzo OUTPUT;

		-- UnitaLocale: solo una sede può avere il flag attivo all'interno dello stesso gruppo
		-- IdParent (il genitore stesso incluso). Se @Id ha un genitore, il gruppo è ancorato al
		-- genitore (se stesso + fratelli). Se @Id è una radice (IdParent NULL), il gruppo è
		-- ancorato a @Id stesso, cosi' da includere le sue eventuali sotto-sedi (altrimenti
		-- IdParent = NULL non troverebbe mai corrispondenze, per semantica SQL standard, e
		-- impostare UnitaLocale sulla radice non azzererebbe mai i figli).
		DECLARE @idParentGruppo CHAR(16) = ISNULL((SELECT IdParent
		FROM dbo.tblSedi
		WHERE Id = @Id), @Id);

		BEGIN TRANSACTION;

			IF @isNuovoIndirizzo = 1
			BEGIN
				INSERT INTO dbo.tblIndirizzi
					(Id, Indirizzo, NumeroCivico, CAP, Localita, IdComune, IdNazione)
				VALUES
					(@idIndirizzo, @Indirizzo, @NumeroCivico, @CAP, @Localita, @IDComune, @IDNazione);

				INSERT INTO dbo.tblSediIndirizzi (Id, IdIndirizzo)
				VALUES (@Id, @idIndirizzo);
			END
			ELSE
			BEGIN
				UPDATE dbo.tblIndirizzi
				SET
					Indirizzo = @Indirizzo,
					NumeroCivico = @NumeroCivico,
					CAP = @CAP,
					Localita = @Localita,
					IdComune = @IDComune,
					IdNazione = @IDNazione
				WHERE Id = @idIndirizzo;
			END

			DELETE dbo.tblSediRecapiti
			WHERE Id = @Id;

			INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @Id, 'T0', @Telefono0
			WHERE @Telefono0 IS NOT NULL;
			INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @Id, 'T1', @Telefono1
			WHERE @Telefono1 IS NOT NULL;
			INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @Id, 'T2', @Telefono2
			WHERE @Telefono2 IS NOT NULL;
			INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @Id, 'M0', @Email0
			WHERE @Email0 IS NOT NULL;
			INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @Id, 'M1', @Email1
			WHERE @Email1 IS NOT NULL;
			INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @Id, 'M2', @Email2
			WHERE @Email2 IS NOT NULL;

			UPDATE s
			SET
				Lock = 0,
				IdTipo = @IdTipo,
				Nome = @Nome,
				Cognome = @Cognome,
				CodiceFiscale = COALESCE(sl.CodiceFiscale, @CodiceFiscale),
				PartitaIva = COALESCE(sl.PartitaIva, @PartitaIva),
				Codice = @Codice,
				Note = @Note,
				Disabilitata = @Disabilitata,
				UnitaLocale = @UnitaLocale,
				IndirizzoCompleto = CASE WHEN i.IdNazione = '380' THEN ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.Localita + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(c.Nome + ' (' + p.Sigla + ')', '') ELSE ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(i.Localita + ' ', '') + ISNULL(n.Nome, '') END
			FROM
				dbo.tblSedi s
				LEFT JOIN dbo.tblSedi sl ON s.IdParent = sl.Id
				LEFT JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
				LEFT JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
				LEFT JOIN dbo.tblComuni c ON i.IdComune = c.Id
				LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
				LEFT JOIN dbo.tblNazioni n ON i.IdNazione = n.Id
			WHERE
				s.Id = @Id
				AND s.Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Sede non trovata o già eliminata';
				GOTO BRANCH_END;
			END

			IF @UnitaLocale = 1
				UPDATE dbo.tblSedi
				SET UnitaLocale = 0
				WHERE
					Id <> @Id
					AND Lock = 0
					AND
						(
						Id = @idParentGruppo
						OR IdParent = @idParentGruppo
						);
			ELSE IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi
				WHERE
					UnitaLocale = 1
					AND Lock = 0
					AND
						(
						Id = @idParentGruppo
						OR IdParent = @idParentGruppo
						)
			)
				-- Il gruppo deve avere sempre almeno una sede con UnitaLocale=true: se nessuna lo è
				-- più (l'unica sede true si sta spegnendo e nessun'altra la sostituisce nella stessa
				-- chiamata), il genitore del gruppo la eredita automaticamente. Se @Id è il genitore
				-- stesso, questo annulla di fatto la sua richiesta di spegnersi: una sede non può
				-- spegnere da sola il proprio flag, solo un'altra sede del gruppo può "rubarglielo"
				-- diventando true (confermato dall'utente) — per una sede isolata (senza genitore né
				-- figli) questo significa che, una volta true, resta true per sempre.
				-- Lock = 0 su entrambe le query: una sede cancellata (Lock=4) con un vecchio
				-- UnitaLocale=1 residuo non deve mascherare l'invariante, e non ha senso azzerare o
				-- forzare il flag su record non attivi.
				UPDATE dbo.tblSedi
				SET UnitaLocale = 1
				WHERE
					Id = @idParentGruppo
					AND Lock = 0;

			UPDATE s
			SET NomeCompleto = COALESCE(s.Cognome + ' ' + s.Nome, s.Nome, sl.Nome)
			FROM dbo.tblSedi s
			LEFT JOIN dbo.tblSedi sl ON s.IdParent = sl.Id
			WHERE s.Id = @Id;

			UPDATE s
			SET
				CodiceFiscale = sl.CodiceFiscale,
				PartitaIva = sl.PartitaIva
			FROM dbo.tblSedi s
			LEFT JOIN dbo.tblSedi sl ON s.IdParent = sl.Id
			WHERE
				s.Id = @Id
				AND s.IdTipo IN ('A', 'G');

			IF @InternaEsterna = 'I'
				UPDATE s
				SET IdAziendaInterna = i.Id
				FROM dbo.tblSedi s
				LEFT JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
				WHERE s.Id = @Id;
			ELSE
				UPDATE s
				SET IdAziendaInterna = e.IdSedeInterna
				FROM dbo.tblSedi s
				LEFT JOIN dbo.tblSediEsterne e ON ISNULL(s.IdParent, s.Id) = e.Id
				WHERE s.Id = @Id;

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






