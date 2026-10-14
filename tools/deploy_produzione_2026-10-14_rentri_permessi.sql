/*
Deploy produzione 2026-10-14 - RENTRI: operazioni dalle pagine operative anche per gli utenti standard

Indipendente dagli altri script. Rieseguibile. Eseguire con sqlcmd -f 65001 -I (oppure da SSMS).
Va deployato insieme all'app (nuovo metodo GetAnagraficaAsync usato dalla pagina Firma remota).

1. Letture di supporto RENTRI: accettano RNT (configurazione, solo amministratori) oppure la funzione della pagina che
   le usa. Prima un utente standard con i permessi su Registrazioni o Formulari riceveva "Non si dispone dei diritti
   necessari" su invio, stampa, esito, accettazione, conservazione, azioni e firma dei formulari.
   - uspRentriRegistri_get_IdRentri, uspRentriRegistri_get, uspSedi_get_CodiceFiscale,
     uspRentriRegistri_get_IdCredenziale: RNT, RRG o RFR
   - uspRentriSedi_get_IdRentri: RNT o RAT (controllo dell'Albo dalle Autorizzazioni)
   - uspRentriCredenziali_get_IdRentriRegistro: RNT o RFX (collegamento della firma remota)
2. Registro nel contesto e scheda del registro: uspRifiutiRegistri_get_SelectList accetta RRT (Registri rifiuti) oppure
   RRG, RFR, RMD, EOW; uspRifiutiRegistri_get accetta RRT, RRG o RFR. Prima un utente senza il permesso sui Registri
   non poteva scegliere il registro nel contesto, ne' aprire registrazioni e formulari.
3. Firma remota: uspUtenti_get_SelectListByDominio (chi non è amministratore vede solo se stesso), nuova
   uspUtenti_get_Anagrafica (codice fiscale, nome e cognome per se stessi, con RFX).
*/

-- ===== uspRentriRegistri_get_IdRentri
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

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT) oppure le pagine che inviano e leggono dal RENTRI (Registrazioni RRG, Formulari RFR)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRrg TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permessoRrg OUTPUT;
		IF ISNULL(@permessoRrg, 0) > @permesso SET @permesso = @permessoRrg;

		DECLARE @permessoRfr TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permessoRfr OUTPUT;
		IF ISNULL(@permessoRfr, 0) > @permesso SET @permesso = @permessoRfr;

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


-- ===== uspRentriRegistri_get
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

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT) oppure le pagine che inviano e leggono dal RENTRI (Registrazioni RRG, Formulari RFR)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRrg TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permessoRrg OUTPUT;
		IF ISNULL(@permessoRrg, 0) > @permesso SET @permesso = @permessoRrg;

		DECLARE @permessoRfr TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permessoRfr OUTPUT;
		IF ISNULL(@permessoRfr, 0) > @permesso SET @permesso = @permessoRfr;

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


-- ===== uspSedi_get_CodiceFiscale
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

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT) oppure le pagine che inviano e leggono dal RENTRI (Registrazioni RRG, Formulari RFR)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRrg TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permessoRrg OUTPUT;
		IF ISNULL(@permessoRrg, 0) > @permesso SET @permesso = @permessoRrg;

		DECLARE @permessoRfr TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permessoRfr OUTPUT;
		IF ISNULL(@permessoRfr, 0) > @permesso SET @permesso = @permessoRfr;

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


-- ===== uspRentriRegistri_get_IdCredenziale
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get_IdCredenziale]
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

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT) oppure le pagine che firmano su RENTRI (Registrazioni RRG per l'accettazione, Formulari RFR)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRrg TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permessoRrg OUTPUT;
		IF ISNULL(@permessoRrg, 0) > @permesso SET @permesso = @permessoRrg;

		DECLARE @permessoRfr TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permessoRfr OUTPUT;
		IF ISNULL(@permessoRfr, 0) > @permesso SET @permesso = @permessoRfr;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdSede CHAR(16);
		SELECT @IdSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCredenziale CHAR(16);
		SELECT @IdCredenziale = IdCredenziale
		FROM dbo.tblRentriCredenzialiSedi
		WHERE IdSede = @IdSede AND Pos = 0;

		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
			GOTO BRANCH_END;
		END

		SELECT rtn = @IdCredenziale;

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


-- ===== uspRentriSedi_get_IdRentri
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

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT) oppure Autorizzazioni (RAT), che controlla l'iscrizione all'Albo sul RENTRI
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRat TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RAT',
			@Permesso = @permessoRat OUTPUT;
		IF ISNULL(@permessoRat, 0) > @permesso SET @permesso = @permessoRat;

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


-- ===== uspRentriCredenziali_get_IdRentriRegistro
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCredenziali_get_IdRentriRegistro]
	@IdCredenziale CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT) oppure Firma remota (RFX), che collega la credenziale di firma
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRfx TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permessoRfx OUTPUT;
		IF ISNULL(@permessoRfx, 0) > @permesso SET @permesso = @permessoRfx;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: la credenziale deve appartenere allo stesso Dominio della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti a ON a.IdDominio = rc.IdDominio
			INNER JOIN dbo.tblSessioni s ON s.IdUtente = a.Id
			WHERE rc.Id = @IdCredenziale AND s.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'endpoint hub di risoluzione del connettore (certificato) è per Registro
		-- (viewRegistri, 1_0_rentri), non per Credenziale: si risale a un Registro
		-- qualunque delle Sedi collegate a questa Credenziale - condividono lo stesso
		-- certificato, quindi va bene il primo trovato.
		DECLARE @IdRentri CHAR(16);
		SELECT TOP 1 @IdRentri = rr.IdRentri
		FROM
			dbo.tblRentriCredenzialiSedi cs
			INNER JOIN dbo.tblRifiutiRegistri g ON g.IdSede = cs.IdSede AND g.Lock = 0
			INNER JOIN dbo.tblRentriRegistri rr ON rr.Id = g.Id AND rr.IdRentri IS NOT NULL
		WHERE cs.IdCredenziale = @IdCredenziale;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessun registro collegato a RENTRI per questo operatore';
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


-- ===== uspUtenti_get_SelectListByDominio
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_SelectListByDominio]
	@IdDominio CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdDominio = NULLIF(LTRIM(RTRIM(@IdDominio)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdDominio non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		DECLARE @idUtenteSessione CHAR(16);
		DECLARE @isAdminSessione BIT;
		SELECT
			@idDominioSessione = a.IdDominio,
			@idUtenteSessione = a.Id,
			@isAdminSessione = CAST(IIF(a.IdRuolo = 'AD', 1, 0) AS BIT)
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: si può elencare solo il proprio Dominio, oppure qualsiasi
		-- Dominio se l'Admin appartiene a un Dominio Master.
		IF @IdDominio <> @idDominioSessione
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = '',
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			u.Id,
			[Text] = CAST(
				CASE
					WHEN NULLIF(LTRIM(RTRIM(CONCAT(u.Nome, ' ', u.Cognome))), '') IS NOT NULL
						THEN CONCAT(u.Nome, ' ', u.Cognome, ' (', u.Email, ')')
					ELSE u.Email
				END
			AS VARCHAR(200)),
			Selected = CAST(IIF(u.Id = @IdSelected, 1, 0) AS BIT),
			Pos = 1
		FROM dbo.tblUtenti u
		WHERE
			u.IdDominio = @IdDominio
			AND u.Lock = 0
			AND ISNULL(u.[Master], 0) = 0
			-- Chi non è Amministratore vede solo se stesso (Firma remota: ognuno collega la propria)
			AND
				(
				@isAdminSessione = 1
				OR u.Id = @idUtenteSessione
				)
		ORDER BY Pos, [Text];

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


-- ===== uspUtenti_get_Anagrafica
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_Anagrafica]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: in lettura basta la consultazione della Firma remota (RFX)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtenteSessione CHAR(16);
		SELECT @idUtenteSessione = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtenteSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		-- Titolarità sull'utente target: se stesso, oppure Amministratore del suo Dominio
		-- (o di un Dominio Master). Stesso schema di uspUtenti_upd_Anagrafica, che la pagina Firma remota usa per salvare questi dati.
		IF @idUtenteSessione <> @IdUtente
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti target
				INNER JOIN dbo.tblUtenti admin ON admin.IdDominio = target.IdDominio
				WHERE
					target.Id = @IdUtente
					AND admin.Id = @idUtenteSessione
					AND admin.IdRuolo = 'AD'
					AND admin.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti target
				INNER JOIN dbo.tblUtenti admin ON admin.Id = @idUtenteSessione
				INNER JOIN dbo.tblDomini d ON admin.IdDominio = d.Id
				WHERE
					target.Id = @IdUtente
					AND admin.IdRuolo = 'AD'
					AND admin.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
		END

		SELECT
			Id,
			CodiceFiscale,
			Nome,
			Cognome
		FROM dbo.tblUtenti
		WHERE
			Id = @IdUtente
			AND Lock <= 2;

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


-- ===== uspRifiutiRegistri_get_SelectList
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistri_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: Registri rifiuti (RRT) oppure le pagine che lavorano con il registro nel contesto (Registrazioni RRG, Formulari RFR, Modelli RMD, Gestione EoW EOW)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRrg TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permessoRrg OUTPUT;
		IF ISNULL(@permessoRrg, 0) > @permesso SET @permesso = @permessoRrg;

		DECLARE @permessoRfr TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permessoRfr OUTPUT;
		IF ISNULL(@permessoRfr, 0) > @permesso SET @permesso = @permessoRfr;

		DECLARE @permessoRmd TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RMD',
			@Permesso = @permessoRmd OUTPUT;
		IF ISNULL(@permessoRmd, 0) > @permesso SET @permesso = @permessoRmd;

		DECLARE @permessoEow TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permessoEow OUTPUT;
		IF ISNULL(@permessoEow, 0) > @permesso SET @permesso = @permessoEow;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Se @IdSelected non fornito, usa il registro della sessione corrente
		-- oppure l'opzione vuota (REPLICATE('0',16))
		SELECT @IdSelected =
			COALESCE(
				@IdSelected,
				(SELECT s.IdRegistro
				 FROM
					 dbo.tblSessioni s
					 INNER JOIN dbo.tblRifiutiRegistri r ON s.IdRegistro = r.Id
				 WHERE
					 s.Id = @IdSessione
					 AND r.Lock = 0
				),
				REPLICATE('0', 16)
			);

		SELECT TOP 20
			Id,
			[Text],
			Selected
		FROM (
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				r.Id,
				[Text] = r.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto,
				Selected = CAST(IIF(r.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
				INNER JOIN dbo.tblRifiutiRegistri r ON i.Id = r.IdSede
				INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			WHERE
				r.Lock = 0
				AND
					(
					@Search IS NULL
					OR (r.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto) LIKE '%' + @Search + '%'
					)
		) x
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


-- ===== uspRifiutiRegistri_get
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistri_get]
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

		-- Controlla il permesso sulla funzione: Registri rifiuti (RRT) oppure le schede che leggono i dati del registro (Registrazioni RRG, Formulari RFR)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		DECLARE @permessoRrg TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permessoRrg OUTPUT;
		IF ISNULL(@permessoRrg, 0) > @permesso SET @permesso = @permessoRrg;

		DECLARE @permessoRfr TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permessoRfr OUTPUT;
		IF ISNULL(@permessoRfr, 0) > @permesso SET @permesso = @permessoRfr;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiRegistri
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registro non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			Id,
			IdSede,
			IdTipo,
			Nome = ISNULL(Nome, ''),
			ControlloScadenzeAutorizzazioni = ISNULL(ControlloScadenzeAutorizzazioni, 1),
			ControlloTarghe = ISNULL(ControlloTarghe, 1),
			ControlloConducenti = ISNULL(ControlloConducenti, 1),
			ControlloPatenti = ISNULL(ControlloPatenti, 1),
			ControlloAttivitaRs = ISNULL(ControlloAttivitaRs, 1),
			Lock
		FROM dbo.tblRifiutiRegistri
		WHERE
			Id = @Id
			AND Lock <= 2;

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

