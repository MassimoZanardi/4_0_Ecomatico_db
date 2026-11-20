SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: elenco delle importazioni (in preparazione ed eseguite) dei registri dell'azienda corrente,
-- dalla più recente, a pagine. Righe e ricerca: ufnRentriImportazioni_get_Elenco (la stessa dell'esportazione).
-- StatoValore come _StatoPartial: 0 eseguita (verde), 1 in preparazione (arancione).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');

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

		SELECT
			t.Id,
			StatoValore = IIF(t.Stato = 'E', 0, 1),
			StatoDescrizione = IIF(t.Stato = 'E', 'Importazione eseguita', 'Anteprima in preparazione, non ancora importata'),
			t.Stato,
			t.RegistroNome,
			t.Modalita,
			t.DalAnno,
			t.DalNumero,
			t.AlAnno,
			t.AlNumero,
			t.FinoAlPrimoProblema,
			t.DataCreazione,
			t.DataEsecuzione,
			t.UtenteAccount,
			t.Movimenti,
			t.Importate,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnRentriImportazioni_get_Elenco(@IdSessione, @Search, @Stato, @DallaData, @AllaData) t
		ORDER BY t.Data DESC, t.Id
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

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
