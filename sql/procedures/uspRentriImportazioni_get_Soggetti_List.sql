SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: soggetti delle registrazioni lette da RENTRI (sezione "Soggetti" dell'anteprima), con lo
-- stato dell'abbinamento: A abbinato, N autorizzazione da aggiungere a una sede esistente, M da completare,
-- U scelto dall'utente, C da creare con i dati completati dall'utente. Prima quelli da completare.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Soggetti_List]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
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
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			x.Id,
			x.Ruolo,
			RuoloNome = CASE x.Ruolo WHEN 'P' THEN 'Produttore' WHEN 'T' THEN 'Trasportatore' WHEN 'D' THEN 'Destinatario' ELSE 'Intermediario' END,
			x.CodiceFiscale,
			Numero = NULLIF(x.Numero, ''),
			x.Denominazione,
			x.Stato,
			x.IsModificato,
			x.IdAutorizzazione,
			AutorizzazioneNome = IIF(a.Id IS NULL, NULL, CONCAT(sa.NomeCompleto, IIF(a.Numero IS NULL, ' - nessuna autorizzazione', CONCAT(' - n. ', a.Numero)))),
			x.IdSede,
			SedeNome = s.NomeCompleto,
			x.Nome,
			x.PartitaIva,
			x.IdNazione,
			x.IdComune,
			ComuneNome = k.Nome,
			x.Localita,
			x.CAP,
			x.Indirizzo,
			x.NumeroCivico,
			Registrazioni = (SELECT COUNT(DISTINCT CONCAT(ms.Anno, '/', ms.Progressivo)) FROM dbo.tblRentriImportazioniMovimentiSoggetti ms WHERE ms.IdSoggetto = x.Id)
		FROM
			dbo.tblRentriImportazioniSoggetti x
			LEFT JOIN dbo.tblRifiutiAutorizzazioni a ON x.IdAutorizzazione = a.Id
			LEFT JOIN dbo.tblSedi sa ON a.IdSede = sa.Id
			LEFT JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblComuni k ON x.IdComune = k.Id
		WHERE x.IdImportazione = @Id
		ORDER BY IIF(x.Stato = 'M', 0, 1), x.CodiceFiscale, x.Ruolo, x.Numero;

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
