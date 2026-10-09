SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Allocazioni EoW: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspEoWAllocazioni_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
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
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è quella del contesto della sessione (tblSessioni.IdSede); contesto "tutte le sedi" = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT TOP (@MaxRighe + 1)
			[Nome] = a.Nome,
			[Tipo] = t.Nome,
			[Materiale] = mat.MaterialeNome,
			[Lotti] = (SELECT STRING_AGG(l.Nome, ', ') WITHIN GROUP (ORDER BY l.Nome) FROM dbo.tblEoWLottiAllocazioni la INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id WHERE la.IdAllocazione = a.Id)
		FROM
			dbo.tblEoWAllocazioni a
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON a.IdSede = i.Id
			LEFT JOIN dbo.tblEoWAllocazioniTipi t ON a.IdAllocazioneTipo = t.Id
			-- Il materiale non è un campo proprio dell'allocazione: si ricava dai lotti già collegati
			OUTER APPLY (
				SELECT TOP 1 IdMateriale = l.IdMateriale, MaterialeNome = m.Nome
				FROM
					dbo.tblEoWLottiAllocazioni la
					INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
					LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				WHERE la.IdAllocazione = a.Id
			) mat
		WHERE
			a.Lock = 0
			AND a.IdSede = @idSede
			AND (@IdMateriale IS NULL OR mat.IdMateriale = @IdMateriale)
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%')
		ORDER BY a.Nome
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
