/*
	Deploy produzione - 2026-08-31 - Modulo Rentri/Registri

	PREREQUISITO DA VERIFICARE PRIMA DI ESEGUIRE QUESTO SCRIPT:
	la colonna [1_0_rentri]..tblRegistri.DataInizioInvio (DATE NULL) deve
	gia' esistere sull'istanza di produzione. E' una tabella dell'hub
	condiviso 1_0_rentri (usato anche da 3_1_ecomatico), non tracciata in
	nessun repo Git - va verificata/aggiunta manualmente se assente, PRIMA
	di questo bundle:

		IF NOT EXISTS (
			SELECT 1 FROM [1_0_rentri].INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_NAME = 'tblRegistri' AND COLUMN_NAME = 'DataInizioInvio')
		BEGIN
			ALTER TABLE [1_0_rentri]..tblRegistri ADD DataInizioInvio DATE NULL;
		END

	Se la colonna manca e questo script viene eseguito comunque, il deploy
	di uspRentriRegistri_get/_upd fallisce a compile-time con un errore
	"Invalid column name 'DataInizioInvio'" (fail-safe, nessun rischio di
	deploy silenzioso con bug nascosto).

	Contenuto (bundle completo del modulo Rentri/Registri - MAI deployato
	in produzione finora, primo giro completo dell'intero modulo, sessioni
	2026-08-30/2026-08-31 - solo stored procedure, nessun'altra modifica di
	schema/dati oltre al prerequisito sopra, idempotente):

	1) dbo.uspSedi_get_CodiceFiscale (nuova)
	   - Restituisce il CodiceFiscale di una Sede con verifica di titolarita'
	     (permesso RNT + ufnSedi_get_SediInterneBySessione_List) - usata da
	     Registri/Edit per la ricerca dei Blocchi formulari vidimati su RENTRI.

	2) dbo.uspRentriRegistri_get
	   - Get del singolo Registro (Nome/Sede/Identificativo/BloccoFormulari/
	     DataInizioInvio/IsCollegato), con verifica di titolarita' via
	     tblRifiutiRegistri.IdSede.

	3) dbo.uspRentriRegistri_get_IdRentri (nuova)
	   - Risolve l'IdRentri (hub) di un Registro collegato, con verifica di
	     titolarita' - usata dalla feature "Verifica collegamento RENTRI"
	     su Registri/Edit. Errore esplicito se il registro non e' collegato.

	4) dbo.uspRentriRegistri_get_List
	   - Index: filtra sulla sola Azienda in contesto di sessione, colonne
	     IndirizzoCompleto/Identificativo/CredenzialePrimariaNome/
	     AccreditamentoNome/IsCollegato, Stato scadenza (rosso/giallo/verde)
	     calcolato sul certificato della Credenziale Primaria/Secondaria
	     ereditata dalla Sede (worst-case, stesso pattern di
	     uspRentriSedi_get_List). Stato rosso anche se Identificativo o
	     BloccoFormulari sono NULL (non solo su certificato scaduto).

	5) dbo.uspRentriRegistri_upd
	   - Update/collegamento/scollegamento del Registro a RENTRI: eredita
	     sempre la Credenziale Primaria (Pos=0) della Sede, valida
	     l'Identificativo duplicato, gestisce Identificativo/BloccoFormulari/
	     DataInizioInvio sulla riga hub (insert alla prima associazione,
	     update altrimenti).

	Verificato su DB dev: build pulita, header ANSI_NULLS/QUOTED_IDENTIFIER/
	CRLF su tutte le SP, smoke test con sessione a basso privilegio (diniego
	pulito su titolarita'/permesso), test funzionale su dati reali (dominio
	test1.net) per get/get_IdRentri/get_List/upd - inclusi i rami
	collegamento, scollegamento, Identificativo duplicato, Stato rosso per
	Identificativo/BloccoFormulari NULL. Dati di test ripuliti a fine sessione.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-08-31_registri.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspSedi_get_CodiceFiscale
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_get_CodiceFiscale]
	@IdSede CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
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
			FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			WHERE i.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT rtn = CodiceFiscale
		FROM dbo.tblSedi
		WHERE Id = @IdSede;

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
			IsCollegato = CAST(IIF(r.IdRentri IS NULL, 0, 1) AS BIT)
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
-- 3) dbo.uspRentriRegistri_get_IdRentri
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get_IdRentri]
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
			WHERE
				g.Id = @Id
				AND g.Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdRentri CHAR(16);
		SELECT @IdRentri = IdRentri
		FROM dbo.tblRentriRegistri
		WHERE Id = @Id;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è collegato a RENTRI';
			GOTO BRANCH_END;
		END

		SELECT rtn = @IdRentri;

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
-- 4) dbo.uspRentriRegistri_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			StatoValore = CASE
				WHEN h.Identificativo IS NULL THEN 2
				WHEN h.BloccoFormulari IS NULL THEN 2
				WHEN sc.DataScadenza < GETDATE() THEN 2
				WHEN DATEDIFF(DAY, GETDATE(), sc.DataScadenza) < 30 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN h.Identificativo IS NULL THEN 'Registro senza identificativo'
				WHEN h.BloccoFormulari IS NULL THEN 'Registro senza blocco formulari'
				WHEN sc.DataScadenza < GETDATE() THEN 'Certificato scaduto'
				WHEN DATEDIFF(DAY, GETDATE(), sc.DataScadenza) < 30 THEN 'Certificato in scadenza'
				ELSE 'OK'
			END,
			g.Nome,
			SedeNome = s.NomeCompleto,
			s.IndirizzoCompleto,
			Identificativo = h.Identificativo,
			CredenzialePrimariaNome = idf.CredenzialePrimariaNome,
			AccreditamentoNome = idf.AccreditamentoNome,
			IsCollegato = CAST(IIF(r.IdRentri IS NULL, 0, 1) AS BIT),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSessioni e ON e.Id = @IdSessione
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRentriRegistri r ON g.Id = r.Id
			LEFT JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
			OUTER APPLY (
				-- Il registro non ha una propria credenziale: eredita Primaria/Secondaria della Sede su cui si appoggia (worst-case, come uspRentriSedi_get_List)
				SELECT MIN(f.DataScadenza) AS DataScadenza
				FROM
					dbo.tblRentriCredenzialiSedi rcs
					INNER JOIN dbo.tblRentriCredenziali c ON rcs.IdCredenziale = c.Id AND c.Lock = 0
					LEFT JOIN dbo.tblRentriCertificati f ON c.IdCertificato = f.Id
				WHERE rcs.IdSede = g.IdSede
			) sc
			OUTER APPLY (
				SELECT TOP 1
					CredenzialePrimariaNome = c.Nome,
					AccreditamentoNome = a.Nome
				FROM
					dbo.tblRentriCredenzialiSedi rcs
					INNER JOIN dbo.tblRentriCredenziali c ON rcs.IdCredenziale = c.Id
					LEFT JOIN dbo.tblRentriAccreditamenti a ON c.IdAccreditamento = a.Id
				WHERE rcs.IdSede = g.IdSede AND rcs.Pos = 0
			) idf
		WHERE
			g.Lock = 0
			AND i.IdAziendaInterna = e.IdAzienda
			AND
				(
				@Search IS NULL
				OR g.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY g.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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

--------------------------------------------------------------------------------
-- 5) dbo.uspRentriRegistri_upd
--------------------------------------------------------------------------------
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
	@DataInizioInvio DATE = NULL
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

		-- Scollegamento esplicito
		IF @Scollega = 1
		BEGIN
			IF @idRentri IS NOT NULL
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblRentriRegistri WHERE Id = @Id;
					DELETE [1_0_rentri]..tblRegistri WHERE Id = @idRentri;
				COMMIT TRANSACTION;
			END
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

		BEGIN TRANSACTION;
			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblRegistri (Id, IdSede, Identificativo, BloccoFormulari, DataInizioInvio)
				VALUES (@idRentri, @idRentriSede, @Identificativo, @BloccoFormulari, @DataInizioInvio);

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
					DataInizioInvio = @DataInizioInvio
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
