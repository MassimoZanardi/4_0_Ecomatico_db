SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva il layout di stampa (DDT e fatture) dell'azienda interna corrente della sessione (una riga per azienda: la
-- crea se manca). Colori, dimensioni e allineamenti sono i valori usati dal report (es. Black, 10pt, Left), gli
-- stessi elencati dalla pagina. Il logo si carica a parte (uspSediReport_upd_Logo): qui @NoLogo = 1 lo toglie.
CREATE OR ALTER PROCEDURE dbo.uspSediReport_upd
	@IdSessione CHAR(16) = NULL,
	@IdLayout CHAR(2) = NULL,
	@Intestazione VARCHAR(1000) = NULL,
	@PiePagina VARCHAR(1000) = NULL,
	@IntestazioneColore VARCHAR(10) = NULL,
	@IntestazioneFontSize VARCHAR(10) = NULL,
	@IntestazioneAllineamento VARCHAR(10) = NULL,
	@PiePaginaColore VARCHAR(10) = NULL,
	@PiePaginaFontSize VARCHAR(10) = NULL,
	@PiePaginaAllineamento VARCHAR(10) = NULL,
	@NoLogo BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdLayout = NULLIF(LTRIM(RTRIM(@IdLayout)), '');
		SET @IntestazioneColore = NULLIF(LTRIM(RTRIM(@IntestazioneColore)), '');
		SET @IntestazioneFontSize = NULLIF(LTRIM(RTRIM(@IntestazioneFontSize)), '');
		SET @IntestazioneAllineamento = NULLIF(LTRIM(RTRIM(@IntestazioneAllineamento)), '');
		SET @PiePaginaColore = NULLIF(LTRIM(RTRIM(@PiePaginaColore)), '');
		SET @PiePaginaFontSize = NULLIF(LTRIM(RTRIM(@PiePaginaFontSize)), '');
		SET @PiePaginaAllineamento = NULLIF(LTRIM(RTRIM(@PiePaginaAllineamento)), '');
		SET @NoLogo = ISNULL(@NoLogo, 0);

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
			@IdFunzione = 'AZI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il layout è dell'azienda interna corrente della sessione
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

		IF @IdLayout IS NULL OR NOT EXISTS (SELECT 1
		FROM dbo.tblReportLayout
		WHERE Id = @IdLayout)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il layout dei documenti';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IntestazioneColore, '') NOT IN ('Black', 'Blue', 'Gray', 'Green', 'Red')
			OR ISNULL(@PiePaginaColore, '') NOT IN ('Black', 'Blue', 'Gray', 'Green', 'Red')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il colore';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IntestazioneFontSize, '') NOT IN ('8pt', '9pt', '10pt', '12pt', '14pt', '16pt')
			OR ISNULL(@PiePaginaFontSize, '') NOT IN ('8pt', '9pt', '10pt', '12pt', '14pt', '16pt')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''altezza dei caratteri';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IntestazioneAllineamento, '') NOT IN ('Left', 'Center', 'Right')
			OR ISNULL(@PiePaginaAllineamento, '') NOT IN ('Left', 'Center', 'Right')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''allineamento';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblSediReport WITH (UPDLOCK, HOLDLOCK)
			SET
				IdLayout = @IdLayout,
				Intestazione = @Intestazione,
				Piepagina = @PiePagina,
				IntestazioneColore = @IntestazioneColore,
				IntestazioneFontSize = @IntestazioneFontSize,
				IntestazioneAllineamento = @IntestazioneAllineamento,
				PiepaginaColore = @PiePaginaColore,
				PiepaginaFontSize = @PiePaginaFontSize,
				PiepaginaAllineamento = @PiePaginaAllineamento,
				Logo = IIF(@NoLogo = 1, NULL, Logo)
			WHERE Id = @idAzienda;

			IF @@ROWCOUNT = 0
				INSERT dbo.tblSediReport (Id, IdLayout, Intestazione, Piepagina, IntestazioneColore, IntestazioneFontSize, IntestazioneAllineamento, PiepaginaColore, PiepaginaFontSize, PiepaginaAllineamento)
				VALUES (@idAzienda, @IdLayout, @Intestazione, @PiePagina, @IntestazioneColore, @IntestazioneFontSize, @IntestazioneAllineamento, @PiePaginaColore, @PiePaginaFontSize, @PiePaginaAllineamento);
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

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
