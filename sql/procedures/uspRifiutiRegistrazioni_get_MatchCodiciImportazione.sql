SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Risolve i codici grezzi RENTRI (stato fisico, attività recupero/smaltimento, tipo analisi, classe ADR,
-- unità di misura, esito e causale di respingimento) sui rispettivi Id interni, per l'importazione di un
-- formulario digitale RENTRI
-- (Rifiuti/Registrazioni e Rifiuti/Formulari, "Acquisisci da formulario digitale"). Nessun controllo
-- bloccante: un codice non riconosciuto restituisce Id NULL, l'utente completa a mano da Edit - stesso
-- principio di uspRifiutiAutorizzazioni_get_MatchImportazione. Tabelle di riferimento statiche (nessuna
-- titolarità, stesso trattamento delle rispettive _get_SelectList), quindi eventuali aggiunte/modifiche ai
-- codici non richiedono mai di toccare il codice applicativo.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_MatchCodiciImportazione]
	@StatoFisicoCodice VARCHAR(5) = NULL,
	@AttivitaRsCodice VARCHAR(5) = NULL,
	@AnalisiTipoCodice VARCHAR(20) = NULL,
	@AdrCodice VARCHAR(5) = NULL,
	@UnitaMisuraCodice VARCHAR(5) = NULL,
	@EsitoCodice VARCHAR(5) = NULL,
	@CausaleRespingimentoCodice VARCHAR(5) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @StatoFisicoCodice = NULLIF(LTRIM(RTRIM(@StatoFisicoCodice)), '');
		SET @AttivitaRsCodice = NULLIF(LTRIM(RTRIM(@AttivitaRsCodice)), '');
		SET @AnalisiTipoCodice = NULLIF(LTRIM(RTRIM(@AnalisiTipoCodice)), '');
		SET @AdrCodice = NULLIF(LTRIM(RTRIM(@AdrCodice)), '');
		SET @UnitaMisuraCodice = NULLIF(LTRIM(RTRIM(@UnitaMisuraCodice)), '');
		SET @EsitoCodice = NULLIF(LTRIM(RTRIM(@EsitoCodice)), '');
		SET @CausaleRespingimentoCodice = NULLIF(LTRIM(RTRIM(@CausaleRespingimentoCodice)), '');

		SELECT
			IdStatoFisico = (SELECT TOP 1 Id FROM dbo.tblRifiutiStatiFisici WHERE Codice = @StatoFisicoCodice),
			IdAttivitaRs = (SELECT TOP 1 Id FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento WHERE Codice = @AttivitaRsCodice),
			IdAnalisiTipo = (SELECT TOP 1 Id FROM dbo.tblRifiutiAnalisiTipi WHERE Codice = @AnalisiTipoCodice),
			IdAdr = (SELECT TOP 1 Id FROM dbo.tblAdr WHERE Codice = @AdrCodice),
			IdUnitaMisura = (SELECT TOP 1 Id FROM dbo.tblUnitaMisura WHERE Codice = @UnitaMisuraCodice),
			IdEsito = (SELECT TOP 1 Id FROM dbo.tblRifiutiRegistrazioniEsiti WHERE Codice = @EsitoCodice),
			IdCausaleRespingimento = (SELECT TOP 1 Id FROM dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento WHERE Codice = @CausaleRespingimentoCodice);

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
