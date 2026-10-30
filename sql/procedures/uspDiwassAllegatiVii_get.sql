SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'Allegato VII (i soggetti in uspDiwassAllegatiVii_get_Soggetti). Modificabile: bozza o annunciato su
-- DIWASS (dopo la partenza DIWASS non ammette modifiche)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get]
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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND a.Lock <= 2
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			a.IdAziendaInterna,
			AziendaNome = s.NomeCompleto,
			a.IdRegistrazione,
			RegistrazioneNumero = r.Numero,
			RegistrazioneData = r.Data,
			a.Numero,
			a.Stato,
			StatoDescrizione = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			-- Un documento ricevuto da DIWASS (organizzato da altri o fuori da Ecomatico) è in sola lettura
			Modificabile = CAST(IIF(ISNULL(a.Ricevuto, 0) = 0 AND (a.Stato IS NULL OR a.Stato = 'ANNOUNCED'), 1, 0) AS BIT),
			Ricevuto = CAST(ISNULL(a.Ricevuto, 0) AS BIT),
			a.Ruoli,
			RuoliNome = dbo.ufnDiwassAllegatiVii_get_RuoliDescrizione(a.Ruoli),
			a.DataLettura,
			a.DaInviare,
			a.DataInvio,
			a.DataStato,
			a.TipoDestinazione,
			a.DataSpedizione,
			a.Quantita,
			a.UnitaQuantita,
			a.Contenitore,
			a.LuogoPartenza,
			a.ResponsabileNome,
			a.ResponsabileTelefono,
			a.ResponsabileEmail,
			a.IdEer,
			EerNome = e.Nome,
			a.Descrizione,
			a.CodiceDoganale,
			a.IdNazioneSpedizione,
			a.IdNazioneDestinazione,
			a.IdNazioneTransito1,
			a.IdNazioneTransito2,
			a.IdAttivita,
			Codice = IIF(a.Codice IS NULL, NULL, a.ListaCodice + '|' + a.Codice),
			a.FirmaNome,
			a.FirmaRuolo,
			a.FirmaEmail,
			a.FirmaData,
			a.ProduttoreFirmaNome,
			a.ProduttoreFirmaRuolo,
			a.ProduttoreFirmaData,
			a.Note,
			a.Lock
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSedi s ON a.IdAziendaInterna = s.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON a.IdRegistrazione = r.Id
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
		WHERE a.Id = @Id;

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
