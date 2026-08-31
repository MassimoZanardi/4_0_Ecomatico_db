/*
	Deploy produzione - 2026-08-31

	ATTENZIONE - DA ESEGUIRE INSIEME AL DEPLOY DELLA NUOVA VERSIONE DELL'APP,
	NON PRIMA: questo script rimuove 2 stored procedure (uspRentriSedi_ins_Credenziale,
	uspRentriSedi_del_Credenziale) tuttora chiamate dalla versione dell'app
	attualmente in produzione. Se questo script viene eseguito mentre gira
	ancora la vecchia app, chiunque apra Rentri/Sedi/Edit in quella finestra
	temporale otterra' un errore SQL (procedura inesistente) sull'Add/Remove
	Credenziali. Tutte le altre modifiche in questo bundle sono invece
	solo additive (nuovi parametri opzionali, nuove colonne, nuove SP) e
	non rompono la vecchia app.

	Contenuto (bundle di tutte le SP del modulo Rentri/Sedi non ancora in
	produzione, sessioni 2026-08-30/2026-08-31 - solo stored procedure,
	nessuna modifica di schema/dati, idempotente):

	1) Rentri/Sedi/Edit: da elenco libero Credenziali a 2 slot fissi Primaria/Secondaria
	   - DROP dbo.uspRentriSedi_ins_Credenziale, dbo.uspRentriSedi_del_Credenziale
	     (sostituite dalla singola uspRentriSedi_upd sotto)
	   - dbo.uspRentriSedi_upd (nuova, rinominata da uspRentriSedi_upd_Credenziali
	     per coerenza con le altre SP _upd del modulo - mai esistita in
	     produzione con il nome precedente, nessun DROP aggiuntivo necessario):
	     riceve i 2 slot in un colpo
	     solo, valida titolarita'/dominio/Lock=0/hub collegato su entrambe,
	     applica lo swap automatico se una credenziale ha accreditamento
	     Delegato (va sempre in Pos=0), blocca 2 credenziali entrambe Delegato,
	     poi riconcilia le associazioni (DELETE non piu' presenti, UPDATE Pos
	     per quelle mantenute, INSERT riga hub+locale per quelle nuove).
	     L'Identificativo Sede digitato dall'utente va sempre sulla riga hub
	     di Pos=0 (la primaria effettiva dopo l'eventuale swap); quella di
	     Pos=1 riceve un identificativo tecnico generato una sola volta.
	   - dbo.uspRentriSedi_get_Credenziali_SelectList: riscritta con pattern
	     standard "riga selezionata sempre visibile fuori dal filtro @Search"
	     + nuovo @IdEscluso (non permette di scegliere la stessa credenziale
	     in entrambi gli slot) + accreditamento tra parentesi nel Text.

	2) Rifiniture Index/Edit Rentri/Sedi e Rentri/Credenziali
	   - dbo.uspRentriSedi_get_List: filtra ora sulla sola Azienda in contesto
	     di sessione (prima esponeva tutte le Aziende interne del Dominio ad
	     un Admin), aggiunge le colonne IndirizzoCompleto, Identificativo
	     (Nr. iscrizione dalla riga hub Pos=0) e CredenzialePrimariaNome.
	   - dbo.uspRentriSedi_get: aggiunge IndirizzoCompleto.
	   - dbo.uspRentriCredenziali_get_List: aggiunge la colonna Identificativo
	     (Nr. iscrizione, stesso join hub gia' usato da uspRentriCredenziali_get).

	3) Rentri/Sedi/Edit: nuova sezione Registri RENTRI per Sede (sessione 2026-08-31)
	   - dbo.uspRentriSedi_get_IdRentri (nuova): risolve l'IdRentri della
	     credenziale Primaria (Pos=0) di una Sede, con verifica di titolarita'
	     - usata per risolvere l'id hub richiesto dagli endpoint Registri.
	   - dbo.uspRifiutiAttivitaRecuperoSmaltimento_get_List (nuova): lista
	     statica Id/Codice/Attivita di tblRifiutiAttivitaRecuperoSmaltimento
	     (R1-R13, D1-D15) per le checkbox "Codici recupero/smaltimento" del
	     modale Aggiungi/Modifica registro.
	   - dbo.uspRifiutiAttivita_get_List (nuova): lista statica Id/Codice/Nome
	     di tblRifiutiAttivita per le checkbox "Attivita associate al registro"
	     dello stesso modale - il Codice (es. IntermediazioneSenzaDetenzione,
	     CentroRaccolta) e' il valore letterale inviato all'hub rentri-api,
	     distinto dal Nome mostrato in UI.

	Verificato su DB dev: build pulita, header ANSI_NULLS/QUOTED_IDENTIFIER/CRLF
	su tutte le SP, smoke test con sessione a basso privilegio (diniego pulito),
	test funzionale su dati reali per uspRentriSedi_get_IdRentri e per il flusso
	completo 2 slot Credenziali/Identificativo Sede.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-08-31.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 0) Drop delle SP sostituite (solo dopo il deploy della nuova app)
--------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS dbo.uspRentriSedi_ins_Credenziale;
GO
DROP PROCEDURE IF EXISTS dbo.uspRentriSedi_del_Credenziale;
GO

--------------------------------------------------------------------------------
-- 1) dbo.uspRentriSedi_upd
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_upd]
	@IdSede CHAR(16) = NULL,
	@IdCredenzialePrimaria CHAR(16) = NULL,
	@IdCredenzialeSecondaria CHAR(16) = NULL,
	@IdentificativoSede VARCHAR(30) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdCredenzialePrimaria = NULLIF(LTRIM(RTRIM(@IdCredenzialePrimaria)), '');
		SET @IdCredenzialeSecondaria = NULLIF(LTRIM(RTRIM(@IdCredenzialeSecondaria)), '');
		SET @IdentificativoSede = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@IdentificativoSede, 0, 1));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdCredenzialePrimaria = @idSediciZeri SET @IdCredenzialePrimaria = NULL;
		IF @IdCredenzialeSecondaria = @idSediciZeri SET @IdCredenzialeSecondaria = NULL;

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenzialePrimaria IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la credenziale primaria';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenzialeSecondaria IS NOT NULL AND @IdCredenzialeSecondaria = @IdCredenzialePrimaria
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale secondaria deve essere diversa dalla primaria';
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

		-- Titolarità sulla sede + dominio della sede
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
		WHERE i.Id = @IdSede;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La credenziale deve appartenere allo stesso dominio, essere attiva e già collegata all'hub
		DECLARE @idRentriPrimaria CHAR(16), @accreditamentoPrimaria CHAR(1);
		SELECT
			@idRentriPrimaria = IdRentri,
			@accreditamentoPrimaria = IdAccreditamento
		FROM dbo.tblRentriCredenziali
		WHERE
			Id = @IdCredenzialePrimaria
			AND IdDominio = @idDominio
			AND Lock = 0;

		IF @idRentriPrimaria IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale primaria selezionata non è valida';
			GOTO BRANCH_END;
		END

		DECLARE @idRentriSecondaria CHAR(16), @accreditamentoSecondaria CHAR(1);
		IF @IdCredenzialeSecondaria IS NOT NULL
		BEGIN
			SELECT
				@idRentriSecondaria = IdRentri,
				@accreditamentoSecondaria = IdAccreditamento
			FROM dbo.tblRentriCredenziali
			WHERE
				Id = @IdCredenzialeSecondaria
				AND IdDominio = @idDominio
				AND Lock = 0;

			IF @idRentriSecondaria IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale secondaria selezionata non è valida';
				GOTO BRANCH_END;
			END

			IF ISNULL(@accreditamentoPrimaria, '') = 'D' AND ISNULL(@accreditamentoSecondaria, '') = 'D'
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non è possibile associare due credenziali con accreditamento Delegato';
				GOTO BRANCH_END;
			END
		END

		-- La credenziale con accreditamento Delegato è sempre la primaria (Pos=0), indipendentemente dallo slot scelto in UI.
		-- L'Identificativo Sede (dato reale, digitato dall'utente) va sempre sulla riga hub di Pos=0;
		-- la riga hub di Pos=1 (se presente) è un dettaglio tecnico dell'hub, mai mostrato, valorizzato a caso.
		DECLARE @idCredenzialePos0 CHAR(16) = @IdCredenzialePrimaria;
		DECLARE @idRentriCredPos0 CHAR(16) = @idRentriPrimaria;
		DECLARE @idCredenzialePos1 CHAR(16) = @IdCredenzialeSecondaria;
		DECLARE @idRentriCredPos1 CHAR(16) = @idRentriSecondaria;

		IF @IdCredenzialeSecondaria IS NOT NULL AND ISNULL(@accreditamentoSecondaria, '') = 'D' AND ISNULL(@accreditamentoPrimaria, '') <> 'D'
		BEGIN
			SET @idCredenzialePos0 = @IdCredenzialeSecondaria;
			SET @idRentriCredPos0 = @idRentriSecondaria;
			SET @idCredenzialePos1 = @IdCredenzialePrimaria;
			SET @idRentriCredPos1 = @idRentriPrimaria;
		END

		BEGIN TRANSACTION;

			-- Rimuove le associazioni esistenti non più presenti nelle 2 posizioni finali
			DELETE [1_0_rentri]..tblSedi
			WHERE Id COLLATE DATABASE_DEFAULT IN (
				SELECT rcs.IdRentri COLLATE DATABASE_DEFAULT
				FROM dbo.tblRentriCredenzialiSedi rcs
				WHERE
					rcs.IdSede = @IdSede
					AND rcs.IdCredenziale <> @idCredenzialePos0
					AND (@idCredenzialePos1 IS NULL OR rcs.IdCredenziale <> @idCredenzialePos1)
			);

			DELETE dbo.tblRentriCredenzialiSedi
			WHERE
				IdSede = @IdSede
				AND IdCredenziale <> @idCredenzialePos0
				AND (@idCredenzialePos1 IS NULL OR IdCredenziale <> @idCredenzialePos1);

			-- Posizione 0 (primaria effettiva): l'Identificativo Sede va sempre aggiornato qui
			IF EXISTS (SELECT 1 FROM dbo.tblRentriCredenzialiSedi WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos0)
			BEGIN
				UPDATE dbo.tblRentriCredenzialiSedi
				SET Pos = 0
				WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos0;

				UPDATE h
				SET Identificativo = @IdentificativoSede
				FROM [1_0_rentri]..tblSedi h
				INNER JOIN dbo.tblRentriCredenzialiSedi rcs ON h.Id COLLATE DATABASE_DEFAULT = rcs.IdRentri COLLATE DATABASE_DEFAULT
				WHERE rcs.IdSede = @IdSede AND rcs.IdCredenziale = @idCredenzialePos0;
			END
			ELSE
			BEGIN
				DECLARE @idRentriAssocPos0 CHAR(16) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

				INSERT INTO [1_0_rentri]..tblSedi (Id, IdCredenziale, Identificativo)
				VALUES (@idRentriAssocPos0, @idRentriCredPos0, @IdentificativoSede);

				INSERT INTO dbo.tblRentriCredenzialiSedi (IdSede, IdCredenziale, IdRentri, Pos)
				VALUES (@IdSede, @idCredenzialePos0, @idRentriAssocPos0, 0);
			END

			-- Posizione 1 (secondaria effettiva, opzionale): l'Identificativo hub è un dettaglio tecnico,
			-- generato una sola volta alla creazione e mai più toccato/mostrato
			IF @idCredenzialePos1 IS NOT NULL
			BEGIN
				IF EXISTS (SELECT 1 FROM dbo.tblRentriCredenzialiSedi WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos1)
				BEGIN
					UPDATE dbo.tblRentriCredenzialiSedi
					SET Pos = 1
					WHERE IdSede = @IdSede AND IdCredenziale = @idCredenzialePos1;
				END
				ELSE
				BEGIN
					DECLARE @idRentriAssocPos1 CHAR(16) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
					DECLARE @identificativoTecnicoPos1 VARCHAR(30) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

					INSERT INTO [1_0_rentri]..tblSedi (Id, IdCredenziale, Identificativo)
					VALUES (@idRentriAssocPos1, @idRentriCredPos1, @identificativoTecnicoPos1);

					INSERT INTO dbo.tblRentriCredenzialiSedi (IdSede, IdCredenziale, IdRentri, Pos)
					VALUES (@IdSede, @idCredenzialePos1, @idRentriAssocPos1, 1);
				END
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

--------------------------------------------------------------------------------
-- 2) dbo.uspRentriSedi_get_Credenziali_SelectList
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_get_Credenziali_SelectList]
	@IdSede CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@IdEscluso CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @IdEscluso = NULLIF(LTRIM(RTRIM(@IdEscluso)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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

		-- Titolarità sulla sede + dominio della sede
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
		WHERE i.Id = @IdSede;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- credenziale selezionata: sempre presente, anche se non combacia con @Search

			SELECT
				c.Id,
				[Text] = c.Nome + ISNULL(' (' + a.Nome + ')', ''),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblRentriCredenziali c
				LEFT JOIN dbo.tblRentriAccreditamenti a ON c.IdAccreditamento = a.Id
			WHERE
				c.Id = @IdSelected
				AND c.IdDominio = @idDominio

			UNION ALL -- altre credenziali attive del dominio, filtrabili per @Search

			SELECT
				c.Id,
				[Text] = c.Nome + ISNULL(' (' + a.Nome + ')', ''),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblRentriCredenziali c
				LEFT JOIN dbo.tblRentriAccreditamenti a ON c.IdAccreditamento = a.Id
			WHERE
				c.IdDominio = @idDominio
				AND c.Lock = 0
				AND c.Id <> @IdSelected
				AND (@IdEscluso IS NULL OR c.Id <> @IdEscluso)
				AND
					(
					@Search IS NULL
					OR c.Nome LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20 Id, [Text], Selected
		FROM cte
		ORDER BY Pos, [Text]
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
-- 3) dbo.uspRentriSedi_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_get_List]
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
			s.Id,
			StatoValore = CASE
				WHEN sc.DataScadenza < GETDATE() THEN 2
				WHEN DATEDIFF(DAY, GETDATE(), sc.DataScadenza) < 30 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN sc.DataScadenza < GETDATE() THEN 'Certificato scaduto'
				WHEN DATEDIFF(DAY, GETDATE(), sc.DataScadenza) < 30 THEN 'Certificato in scadenza'
				ELSE 'OK'
			END,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			Identificativo = idf.Identificativo,
			CredenzialePrimariaNome = idf.CredenzialePrimariaNome,
			CredenzialiCount = (SELECT COUNT(*) FROM dbo.tblRentriCredenzialiSedi rcs WHERE rcs.IdSede = s.Id),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblSedi s
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.Id = i.Id
			INNER JOIN dbo.tblSessioni e ON e.Id = @IdSessione
			OUTER APPLY (
				SELECT MIN(f.DataScadenza) AS DataScadenza
				FROM
					dbo.tblRentriCredenzialiSedi rcs
					INNER JOIN dbo.tblRentriCredenziali c ON rcs.IdCredenziale = c.Id AND c.Lock = 0
					LEFT JOIN dbo.tblRentriCertificati f ON c.IdCertificato = f.Id
				WHERE rcs.IdSede = s.Id
			) sc
			OUTER APPLY (
				SELECT TOP 1
					h.Identificativo,
					CredenzialePrimariaNome = c.Nome
				FROM
					dbo.tblRentriCredenzialiSedi rcs
					INNER JOIN dbo.tblRentriCredenziali c ON rcs.IdCredenziale = c.Id
					INNER JOIN [1_0_rentri]..tblSedi h ON rcs.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
				WHERE rcs.IdSede = s.Id AND rcs.Pos = 0
			) idf
		WHERE
			ISNULL(s.Disabilitata, 0) = 0
			AND i.IdAziendaInterna = e.IdAzienda
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto
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
-- 4) dbo.uspRentriSedi_get
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_get]
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

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto
		FROM dbo.tblSedi s
		WHERE s.Id = @IdSede;

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
-- 5) dbo.uspRentriCredenziali_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCredenziali_get_List]
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
			c.Id,
			StatoValore = CASE
				WHEN f.DataScadenza < GETDATE() THEN 2
				WHEN DATEDIFF(DAY, GETDATE(), f.DataScadenza) < 30 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN f.DataScadenza < GETDATE() THEN 'Certificato scaduto'
				WHEN DATEDIFF(DAY, GETDATE(), f.DataScadenza) < 30 THEN 'Certificato in scadenza'
				ELSE 'OK'
			END,
			c.Nome,
			Identificativo = h.Identificativo,
			CertificatoNome = f.Nome,
			AccreditamentoNome = a.Nome,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblRentriCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN dbo.tblRentriCertificati f ON c.IdCertificato = f.Id
			LEFT JOIN dbo.tblRentriAccreditamenti a ON c.IdAccreditamento = a.Id
			LEFT JOIN [1_0_rentri]..tblCredenziali h ON c.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
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
-- 6) dbo.uspRentriSedi_get_IdRentri
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_get_IdRentri]
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

		-- Controlla il permesso sul record (titolarità), stesso pattern di uspRentriSedi_get_Credenziali_List
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			WHERE i.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdRentri CHAR(16);
		SELECT @IdRentri = IdRentri
		FROM dbo.tblRentriCredenzialiSedi
		WHERE IdSede = @IdSede AND Pos = 0;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
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
-- 7) dbo.uspRifiutiAttivitaRecuperoSmaltimento_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAttivitaRecuperoSmaltimento_get_List]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SELECT
			Id,
			Codice,
			Attivita
		FROM
			dbo.tblRifiutiAttivitaRecuperoSmaltimento
		ORDER BY
			CASE Attivita WHEN 'R' THEN 0 ELSE 1 END,
			Id;

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
-- 8) dbo.uspRifiutiAttivita_get_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAttivita_get_List]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SELECT
			Id,
			Codice,
			Nome
		FROM
			dbo.tblRifiutiAttivita
		ORDER BY
			Id;

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
