SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Banche e casse: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspBancheCasse_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Tipo] = CASE b.Tipo WHEN 'B' THEN 'Banca' WHEN 'C' THEN 'Cassa' END,
			[Nome] = b.Nome,
			[IBAN] = b.Iban,
			[BIC] = b.Bic,
			[Codice SIA] = b.CodiceSia,
			[Saldo iniziale] = b.SaldoIniziale,
			[Data saldo iniziale] = b.DataSaldoIniziale
		FROM
			dbo.tblBancheCasse b
			INNER JOIN dbo.tblSessioni e ON b.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND b.Lock = 0
			AND (@Search IS NULL OR b.Nome LIKE '%' + @Search + '%' OR b.Iban LIKE '%' + REPLACE(@Search, ' ', '') + '%')
		ORDER BY b.Nome
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
