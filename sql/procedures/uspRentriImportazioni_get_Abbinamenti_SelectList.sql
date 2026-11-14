SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: anagrafiche di Ecomatico a cui abbinare un soggetto letto da RENTRI. Tipo A: autorizzazione
-- del ruolo del soggetto (usata così com'è); Tipo S: sede a cui aggiungere, all'importazione, l'autorizzazione con il
-- numero di RENTRI. Solo sedi visibili all'azienda interna del registro (stesso calcolo dell'abbinamento automatico);
-- prima quelle con lo stesso codice fiscale o partita IVA del soggetto. Al massimo 50 righe.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Abbinamenti_SelectList]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSoggetto INT = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL OR @IdSoggetto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @idAziendaInterna CHAR(16), @ruolo CHAR(1), @codiceFiscale VARCHAR(20);
		SELECT
			@idAziendaInterna = sr.IdAziendaInterna,
			@ruolo = x.Ruolo,
			@codiceFiscale = x.CodiceFiscale
		FROM
			dbo.tblRentriImportazioniSoggetti x
			INNER JOIN dbo.tblRentriImportazioni m ON x.IdImportazione = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			m.Id = @Id
			AND x.Id = @IdSoggetto;

		IF @ruolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Soggetto non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);

		;WITH sedi AS (
			SELECT s.Id, s.NomeCompleto, s.IndirizzoCompleto, s.CodiceFiscale, s.PartitaIva,
				Stesso = IIF(UPPER(s.CodiceFiscale) = @codiceFiscale OR UPPER(s.PartitaIva) = @codiceFiscale, 1, 0)
			FROM
				dbo.ufnSedi_get_SediByUtente_List(@idUtente) u
				INNER JOIN dbo.tblSedi s ON u.Id = s.Id
			WHERE
				u.Disabilitata = 0
				AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
				AND s.Disabilitata = 0
				AND s.Lock < 2
				AND (
					@Search IS NULL
					OR s.NomeCompleto LIKE '%' + @Search + '%'
					OR s.CodiceFiscale LIKE '%' + @Search + '%'
					OR s.PartitaIva LIKE '%' + @Search + '%')
		),
		opzioni AS (
			SELECT
				Tipo = 'A', a.Id, s.Stesso,
				Testo = CONCAT(s.NomeCompleto, IIF(a.Numero IS NULL, ' - nessuna autorizzazione', CONCAT(' - n. ', a.Numero)),
					IIF(s.IndirizzoCompleto IS NULL, '', CONCAT(' - ', s.IndirizzoCompleto)))
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN sedi s ON a.IdSede = s.Id
			WHERE
				a.IdRuolo = @ruolo
				AND a.Disabilitata = 0
				AND a.Lock < 2
			UNION ALL
			SELECT
				Tipo = 'S', s.Id, s.Stesso,
				Testo = CONCAT(s.NomeCompleto, IIF(s.IndirizzoCompleto IS NULL, '', CONCAT(' - ', s.IndirizzoCompleto)), ' (nuova autorizzazione)')
			FROM sedi s
		)
		SELECT TOP 50 Tipo, Id, Testo
		FROM opzioni
		ORDER BY Stesso DESC, Tipo, Testo
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
