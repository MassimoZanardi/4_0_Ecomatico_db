SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Clienti tra cui scegliere quello a cui fatturare un documento (link "Seleziona" del blocco "Cliente a cui
-- fatturare"): schede cliente attive dell'azienda del documento (per i rifiuti, quella del registro: non
-- quella del contesto della sessione), al massimo 50, filtrabili per nome, partita IVA o codice fiscale.
-- Si legge con il permesso sul documento, senza quello sulle anagrafiche dei clienti.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Clienti_List
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
		IF ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle registrazioni e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Azienda del documento, se accessibile dalla sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = s.IdAziendaInterna
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
		WHERE r.Id = @Id;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			c.Id,
			[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
			Selected = CAST(0 AS BIT)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.IdAziendaInterna = @idAzienda
			AND c.Tipo = 'C'
			AND c.Lock = 0
			AND ISNULL(s.Disabilitata, 0) = 0
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
				OR s.PartitaIva LIKE '%' + @Search + '%'
				OR s.CodiceFiscale LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto, c.Id
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
