SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Contratti clienti (@Tipo = 'C') e Offerte clienti (@Tipo = 'O'): elenco dell'azienda
-- interna corrente della sessione. Righe, scope e ricerca sono in ufnOfferteContratti_get_List, comune
-- all'esportazione. @SoloInVigore = 1: solo quelli validi oggi (data di oggi tra inizio e fine).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloInVigore BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @SoloInVigore = ISNULL(@SoloInVigore, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (contratto) o O (offerta)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT
			t.Id,
			t.StatoValore,
			t.StatoDescrizione,
			t.Cliente,
			t.Tipo,
			t.DataInizio,
			t.DataFine,
			t.Descrizione,
			t.Protocollo,
			t.Importi,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnOfferteContratti_get_List(@IdSessione, @Tipo, @Search) t
		WHERE
			@SoloInVigore = 0
			OR (t.DataInizio <= @oggi AND t.DataFine >= @oggi)
		ORDER BY t.Cliente, t.DataInizio DESC, t.Id
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
