SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture fornitori > Carica file XML: dati che servono all'applicazione (FatturaXmlCaricaService) per
-- controllare il file prima di caricarlo. Sempre una riga:
--   l'azienda del contesto (il destinatario del file deve essere lei);
--   il fornitore del file, cercato tra le schede fornitore attive dell'azienda per partita IVA o codice
--     fiscale (Fornitori = quante schede corrispondono: con più di una la scelta resta all'utente);
--   IsPresente = 1 se la fattura è già registrata (stesso fornitore, stesso numero, stesso anno del documento).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_XmlCarica
	@IdSessione CHAR(16) = NULL,
	@PartitaIva VARCHAR(30) = NULL,
	@CodiceFiscale VARCHAR(30) = NULL,
	@NumeroFornitore VARCHAR(30) = NULL,
	@DataEmissione DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @PartitaIva = NULLIF(LTRIM(RTRIM(@PartitaIva)), '');
		SET @CodiceFiscale = NULLIF(LTRIM(RTRIM(@CodiceFiscale)), '');
		SET @NumeroFornitore = NULLIF(LTRIM(RTRIM(@NumeroFornitore)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: il caricamento registra una fattura
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Fornitore: scheda attiva dell'azienda con la stessa partita IVA o lo stesso codice fiscale
		DECLARE @fornitori INT;
		DECLARE @idClienteFornitore CHAR(16);
		DECLARE @fornitoreNome VARCHAR(500);
		SELECT
			@fornitori = COUNT(*),
			@idClienteFornitore = MIN(c.Id)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.IdAziendaInterna = @idAzienda
			AND c.Tipo = 'F'
			AND c.Lock = 0
			AND (
				(@PartitaIva IS NOT NULL AND s.PartitaIva = @PartitaIva)
				OR (@CodiceFiscale IS NOT NULL AND s.CodiceFiscale = @CodiceFiscale)
			);

		IF @fornitori <> 1
			SET @idClienteFornitore = NULL;

		SELECT @fornitoreNome = s.NomeCompleto
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE c.Id = @idClienteFornitore;

		-- Fattura già registrata: stesso fornitore, stesso numero e stesso anno del documento
		DECLARE @isPresente BIT = 0;
		IF @idClienteFornitore IS NOT NULL AND @NumeroFornitore IS NOT NULL AND @DataEmissione IS NOT NULL
			AND EXISTS (
				SELECT 1
				FROM dbo.tblFatture
				WHERE
					IdSede = @idAzienda
					AND Tipo = 'F'
					AND Lock = 0
					AND IdClienteFornitore = @idClienteFornitore
					AND NumeroFornitore = @NumeroFornitore
					AND YEAR(DataEmissione) = YEAR(@DataEmissione)
			)
			SET @isPresente = 1;

		SELECT
			AziendaNome = a.NomeCompleto,
			AziendaPartitaIva = a.PartitaIva,
			AziendaCodiceFiscale = a.CodiceFiscale,
			IdClienteFornitore = @idClienteFornitore,
			FornitoreNome = @fornitoreNome,
			Fornitori = ISNULL(@fornitori, 0),
			IsPresente = @isPresente
		FROM dbo.tblSedi a
		WHERE a.Id = @idAzienda;

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
