SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registri dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiRegistri_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistri_get_Esportazione
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
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: sede corrente della sessione (tblSessioni.IdSede); senza sede nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = r.Nome,
			[Tipo] = t.Nome,
			[Collegato a RENTRI] = IIF(z.Id IS NULL, 'No', 'Sì'),
			[Controllo scadenze autorizzazioni] = IIF(r.ControlloScadenzeAutorizzazioni = 1, 'Sì', 'No'),
			[Controllo targhe] = IIF(r.ControlloTarghe = 1, 'Sì', 'No'),
			[Controllo conducenti] = IIF(r.ControlloConducenti = 1, 'Sì', 'No'),
			[Controllo patenti] = IIF(r.ControlloPatenti = 1, 'Sì', 'No'),
			[Controllo attività R/S] = IIF(r.ControlloAttivitaRs = 1, 'Sì', 'No')
		FROM
			dbo.tblRifiutiRegistri r
			INNER JOIN dbo.tblRifiutiRegistriTipi t ON r.IdTipo = t.Id
			INNER JOIN dbo.tblSessioni e ON r.IdSede = e.IdSede
			LEFT JOIN dbo.tblRentriRegistri z ON r.Id = z.Id
		WHERE
			e.Id = @IdSessione
			AND r.Lock = 0
			AND (@Search IS NULL OR r.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Nome
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