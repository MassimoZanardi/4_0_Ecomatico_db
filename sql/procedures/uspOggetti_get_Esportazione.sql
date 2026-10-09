SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Oggetti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspOggetti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspOggetti_get_Esportazione
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
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione (APC = Gestione Oggetti/Persone)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Ramo 1: oggetti dell'azienda della sessione; ramo 2: oggetti condivisi da altre aziende
		WITH tbl AS (
			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblOggetti s
				INNER JOIN dbo.tblSessioni e ON s.IdSede = e.IdAzienda
				OUTER APPLY (
					SELECT TOP 1 a.Id, Area = a.Nome
					FROM
						dbo.tblAreeOsepe ae
						INNER JOIN dbo.tblAree a ON ae.Id = a.Id
					WHERE
						a.Lock = 0
						AND ae.IdOsepe = s.Id
				) c
			WHERE
				e.Id = @IdSessione
				AND s.Lock = 0
			UNION ALL

			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblOggetti s
				CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnOggetti_get_CondivisiByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdSede <> e.IdAzienda
				) c
		)
		SELECT TOP (@MaxRighe + 1)
			[Nome] = s.Nome,
			[Codice] = s.Codice,
			[Tipo] = t.Nome,
			[Descrizione] = s.Descrizione,
			[Impiegabile nei servizi] = IIF(s.ImpiegabileServizi = 1, 'Sì', 'No'),
			[Unità di misura nei servizi] = um.Nome,
			[Disabilitato] = IIF(s.Disabilitata = 1, 'Sì', 'No'),
			[Condiviso nell'area] = tbl.Area
		FROM
			tbl
			INNER JOIN dbo.tblOggetti s ON tbl.Id = s.Id
			LEFT JOIN dbo.tblOggettiTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblUnitaMisura um ON s.IdUnitaMisura = um.Id
		WHERE (@Search IS NULL OR s.Nome LIKE '%' + @Search + '%')
		ORDER BY s.Nome
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
