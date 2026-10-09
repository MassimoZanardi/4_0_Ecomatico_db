SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Persone: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspPersone_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspPersone_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Ruolo VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
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

		-- Ramo 1: persone dell'azienda della sessione; ramo 2: persone condivise da altre aziende
		WITH tbl AS (
			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblPersone s
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
				dbo.tblPersone s
				CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnPersone_get_CondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdSede <> e.IdAzienda
				) c
		)
		-- Ruolo: il più recente, come nell'elenco
		SELECT TOP (@MaxRighe + 1)
			[Nome] = s.Nome,
			[Cognome] = s.Cognome,
			[Ruolo] = r.Ruolo,
			[Ruolo dal] = r.DataInizio,
			[Ruolo al] = r.DataFine,
			[Impiegabile nei servizi] = IIF(s.ImpiegabileServizi = 1, 'Sì', 'No'),
			[Unità di misura nei servizi] = um.Nome,
			[Disabilitata] = IIF(s.Disabilitata = 1, 'Sì', 'No'),
			[Condivisa nell'area] = tbl.Area
		FROM
			tbl
			INNER JOIN dbo.tblPersone s ON tbl.Id = s.Id
			LEFT JOIN dbo.tblUnitaMisura um ON s.IdUnitaMisura = um.Id
			OUTER APPLY (
				SELECT TOP 1 Ruolo = r.Nome, pr.DataInizio, pr.DataFine
				FROM
					dbo.tblPersoneRuoli pr
					INNER JOIN dbo.tblRuoli r ON pr.IdRuolo = r.Id
				WHERE pr.Id = s.Id
				ORDER BY pr.DataInizio DESC
			) r
		WHERE
			(@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND
				(
				@Ruolo IS NULL
				OR s.Id IN (SELECT pr.Id FROM dbo.tblPersoneRuoli pr INNER JOIN dbo.tblRuoli r ON pr.IdRuolo = r.Id WHERE r.Nome LIKE '%' + @Ruolo + '%')
				)
		ORDER BY s.NomeCompleto
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
