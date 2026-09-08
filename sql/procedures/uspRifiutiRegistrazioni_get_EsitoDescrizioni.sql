SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Descrizioni leggibili per l'esito/causale di respingimento RENTRI, usate solo per la modale di anteprima
-- di "RENTRI - Verifica esito" (Rifiuti/Registrazioni/Edit) prima della conferma vera e propria - la
-- risoluzione Id effettiva ai fini del salvataggio resta in uspRentriRegistrazioni_upd_Esito
-- (uspRifiutiRegistrazioni_get_MatchCodiciImportazione), qui serve solo il Nome da mostrare all'utente.
-- Nessun controllo di permesso/titolarità: stesse tabelle di riferimento statiche di
-- uspRifiutiRegistrazioni_get_MatchCodiciImportazione, nessun dato di sessione coinvolto.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_EsitoDescrizioni]
	@Esito VARCHAR(5) = NULL,
	@EsitoCausaleRespingimento VARCHAR(5) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Esito = NULLIF(LTRIM(RTRIM(@Esito)), '');
		SET @EsitoCausaleRespingimento = NULLIF(LTRIM(RTRIM(@EsitoCausaleRespingimento)), '');

		SELECT
			DescrizioneEsito = (SELECT TOP 1 Nome
			FROM dbo.tblRifiutiRegistrazioniEsiti
			WHERE Codice = @Esito),
			DescrizioneCausaleRespingimento = (SELECT TOP 1 Nome
			FROM dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento
			WHERE Codice = @EsitoCausaleRespingimento);

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
