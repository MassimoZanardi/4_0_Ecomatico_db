/*
Deploy produzione 2026-10-09 - Rifiuti > MUD: tblSediDatiEstesi.CodiceRea diventa NumeroRea

Indipendente dagli script della fatturazione. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

1. tblSediDatiEstesi: colonna CodiceRea rinominata in NumeroRea (i dati restano).
2. uspRifiutiMud_get: restituisce NumeroRea.
3. uspRifiutiMud_upd: il parametro @CodiceRea diventa @NumeroRea.

Va deployato insieme all'app: la scheda del MUD legge e passa NumeroRea, con la versione precedente
dell'app il salvataggio della dichiarazione dà errore.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'tblSediDatiEstesi.NumeroRea';
GO
-- tblSediDatiEstesi: la colonna CodiceRea diventa NumeroRea, lo stesso nome di tblFattureDatiFiscali.NumeroRea
-- ("numero REA" è il termine ufficiale). Restano due dati distinti: questo è il numero dell'unità locale,
-- salvato dal MUD; quello dei dati fiscali è il numero dell'azienda, usato dalla fattura elettronica.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la colonna rinominata.
SET NOCOUNT ON;
GO
IF COL_LENGTH('dbo.tblSediDatiEstesi', 'CodiceRea') IS NOT NULL
	AND COL_LENGTH('dbo.tblSediDatiEstesi', 'NumeroRea') IS NULL
	EXEC sp_rename 'dbo.tblSediDatiEstesi.CodiceRea', 'NumeroRea', 'COLUMN';
GO

PRINT 'uspRifiutiMud_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMud_get]
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
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		-- (tblSessioni.IdAzienda), non tutte le aziende accessibili all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiMud c
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiMud
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dichiarazione MUD non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			c.Id,
			c.IdSede,
			c.IdSedeLegale,
			SedeLegaleNome = sl.Nome + ' ' + sl.IndirizzoCompleto,
			LegaleNome = ld.LegaleNome,
			LegaleCognome = ld.LegaleCognome,
			c.IdSedeUnitaLocale,
			SedeUnitaLocaleNome = su.Nome + ' ' + su.IndirizzoCompleto,
			IdAteco = ud.IdAteco,
			AtecoDescrizione = a.Descrizione,
			NumeroRea = ud.NumeroRea,
			Dipendenti = ud.Dipendenti,
			c.Data,
			c.Anno,
			c.DataGenerazione,
			c.Lock
		FROM
			dbo.tblRifiutiMud c
			LEFT JOIN dbo.tblSedi sl ON c.IdSedeLegale = sl.Id
			LEFT JOIN dbo.tblSediDatiEstesi ld ON sl.Id = ld.Id
			LEFT JOIN dbo.tblSedi su ON c.IdSedeUnitaLocale = su.Id
			LEFT JOIN dbo.tblSediDatiEstesi ud ON su.Id = ud.Id
			LEFT JOIN dbo.tblAteco a ON ud.IdAteco = a.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

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

PRINT 'uspRifiutiMud_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMud_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSedeLegale CHAR(16) = NULL,
	@IdSedeUnitaLocale CHAR(16) = NULL,
	@Data DATE = NULL,
	@Anno INT = NULL,
	@LegaleNome VARCHAR(50) = NULL,
	@LegaleCognome VARCHAR(50) = NULL,
	@IdAteco VARCHAR(10) = NULL,
	@NumeroRea VARCHAR(10) = NULL,
	@Dipendenti INT = NULL,
	@Telefono VARCHAR(100) = NULL,
	@Email VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSedeLegale = NULLIF(LTRIM(RTRIM(@IdSedeLegale)), '');
		SET @IdSedeUnitaLocale = NULLIF(LTRIM(RTRIM(@IdSedeUnitaLocale)), '');
		SET @LegaleNome = dbo.ufnStringhe_get_SenzaSpazi(@LegaleNome, 0, 1);
		SET @LegaleCognome = dbo.ufnStringhe_get_SenzaSpazi(@LegaleCognome, 0, 1);
		SET @IdAteco = NULLIF(LTRIM(RTRIM(@IdAteco)), '');
		SET @NumeroRea = dbo.ufnStringhe_get_SenzaSpazi(@NumeroRea, 0, 1);
		SET @Telefono = dbo.ufnStringhe_get_SenzaSpazi(@Telefono, 0, 1);
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
		IF @IdSedeLegale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede legale';
			GOTO BRANCH_END;
		END
		IF @IdSedeUnitaLocale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''unità locale';
			GOTO BRANCH_END;
		END
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Data non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Anno IS NULL OR @Anno NOT BETWEEN 2000 AND YEAR(GETDATE())
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Anno esercizio non valido';
			GOTO BRANCH_END;
		END
		IF @Dipendenti IS NOT NULL AND @Dipendenti < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di addetti non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @IdAteco IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblAteco WHERE Id = @IdAteco)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Codice ATECO non valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		-- (tblSessioni.IdAzienda), e recupera la sede reale della dichiarazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblRifiutiMud c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Sede legale e unità locale devono appartenere all'azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				s.Id = @IdSedeLegale
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede legale indicata non è valida';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				s.Id = @IdSedeUnitaLocale
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''unità locale indicata non è valida';
			GOTO BRANCH_END;
		END

		-- Una sola dichiarazione per unità locale e anno di riferimento
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiMud
			WHERE
				Id <> @Id
				AND IdSedeUnitaLocale = @IdSedeUnitaLocale
				AND Anno = @Anno
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già una dichiarazione MUD per questa unità locale e questo anno';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblRifiutiMud
			SET
				Lock = 0,
				IdSedeLegale = @IdSedeLegale,
				IdSedeUnitaLocale = @IdSedeUnitaLocale,
				Data = @Data,
				Anno = @Anno
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Dichiarazione MUD non trovata o già eliminata';
				GOTO BRANCH_END;
			END

			-- Dati estesi Sede legale (Legale rappresentante): UPDATE mirato alle sole
			-- colonne di competenza, per non toccare ATECO/REA/Addetti quando Sede legale
			-- e Unità locale coincidono (caso comune: azienda mono-sede)
			IF EXISTS (SELECT 1 FROM dbo.tblSediDatiEstesi WHERE Id = @IdSedeLegale)
				UPDATE dbo.tblSediDatiEstesi
				SET
					LegaleNome = @LegaleNome,
					LegaleCognome = @LegaleCognome
				WHERE Id = @IdSedeLegale;
			ELSE
				INSERT dbo.tblSediDatiEstesi (Id, LegaleNome, LegaleCognome)
				VALUES (@IdSedeLegale, @LegaleNome, @LegaleCognome);

			-- Dati estesi Unità locale (ATECO/REA/Addetti): stesso principio, colonne
			-- disgiunte da quelle della Sede legale
			IF EXISTS (SELECT 1 FROM dbo.tblSediDatiEstesi WHERE Id = @IdSedeUnitaLocale)
				UPDATE dbo.tblSediDatiEstesi
				SET
					IdAteco = @IdAteco,
					NumeroRea = @NumeroRea,
					Dipendenti = @Dipendenti
				WHERE Id = @IdSedeUnitaLocale;
			ELSE
				INSERT dbo.tblSediDatiEstesi (Id, IdAteco, NumeroRea, Dipendenti)
				VALUES (@IdSedeUnitaLocale, @IdAteco, @NumeroRea, @Dipendenti);

			-- Telefono/e-mail: aggiornano l'anagrafica reale della Sede (Unità locale),
			-- upsert mirato sui soli recapiti T0/M0 per non toccare T1/T2/M1/M2
			DELETE dbo.tblSediRecapiti
			WHERE Id = @IdSedeUnitaLocale AND IdRecapito IN ('T0', 'M0');

			INSERT dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @IdSedeUnitaLocale, 'T0', @Telefono
			WHERE @Telefono IS NOT NULL;
			INSERT dbo.tblSediRecapiti (Id, IdRecapito, Valore) SELECT @IdSedeUnitaLocale, 'M0', @Email
			WHERE @Email IS NOT NULL;
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
