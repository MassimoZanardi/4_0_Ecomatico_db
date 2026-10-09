SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: elenco paginato dei movimenti (pagamenti attivi) dell'azienda del contesto, dal più vecchio, per
-- data contabile. Senza azienda nel contesto nessuna riga. Colonne e ricerca: ufnPagamenti_get_PrimaNota.
-- Il saldo progressivo c'è solo con una banca o cassa selezionata.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_PrimaNota_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@Verso CHAR(1) = NULL,
	@Testo VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @Verso = UPPER(NULLIF(LTRIM(RTRIM(@Verso)), ''));
		SET @Testo = dbo.ufnStringhe_get_SenzaSpazi(@Testo, 0, 1);
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Verso IS NOT NULL AND @Verso NOT IN ('E', 'U')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Verso deve essere E (entrate) o U (uscite)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			t.Id,
			[Data] = t.DataContabile,
			t.DataRegistrazione,
			t.IdBancaCassa,
			t.BancaCassaNome,
			t.IdModalita,
			t.ModalitaNome,
			t.IdConto,
			t.ContoNome,
			t.Manuale,
			t.Tipo,
			t.Causale,
			t.Entrata,
			t.Uscita,
			t.Saldo,
			t.Fatture,
			t.NomeCompleto,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnPagamenti_get_PrimaNota(@IdSessione, @DataDa, @DataA, @IdBancaCassa, @Verso, @Testo) t
		ORDER BY
			t.DataContabile,
			t.DataRegistrazione,
			t.Id
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
