SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Limiti dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiLimiti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiLimiti_get_Esportazione
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
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: sede corrente della sessione (tblSessioni.IdSede); senza sede nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Registro] = ISNULL(r.Nome, 'Tutti i registri'),
			[Riferimento] = IIF(c.Riferimento = 'G', 'Giacenza', 'Operazioni'),
			[Intervallo] = CASE c.Intervallo WHEN 'GG' THEN 'Giornaliero' WHEN 'WK' THEN 'Settimanale' WHEN 'MM' THEN 'Mensile' WHEN 'YY' THEN 'Annuale' ELSE c.Intervallo END,
			[Limite] = c.Valore,
			[Unità di misura] = c.IdUnitaMisura,
			[Codici EER] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiLimitiEer le INNER JOIN dbo.tblRifiutiEer x ON le.IdEer = x.Id WHERE le.IdLimite = c.Id),
			[Operazioni] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Pos) FROM dbo.tblRifiutiLimitiOperazioni lo INNER JOIN dbo.tblRifiutiOperazioni x ON lo.IdOperazione = x.Id WHERE lo.IdLimite = c.Id),
			[Etichette] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiLimitiEtichette lt INNER JOIN dbo.tblEtichette x ON lt.IdEtichetta = x.Id WHERE lt.IdLimite = c.Id)
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdSede
			LEFT JOIN dbo.tblRifiutiRegistri r ON c.IdRegistro = r.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND (@Search IS NULL OR c.Nome LIKE '%' + @Search + '%')
		ORDER BY c.Nome
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