SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Operatori DIWASS: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassOperatori_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassOperatori_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Collegamento CHAR(1) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Collegamento = NULLIF(LTRIM(RTRIM(@Collegamento)), '');
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
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: sedi dell'azienda del contesto e condivise (ufnDiwassOperatori_get_SediBySessione_List)
		SELECT TOP (@MaxRighe + 1)
			[Azienda] = ISNULL(p.NomeCompleto, s.NomeCompleto),
			[Sede] = IIF(s.IdParent IS NULL, NULL, s.NomeCompleto),
			[Indirizzo] = s.IndirizzoCompleto,
			[Partita IVA] = ISNULL(s.PartitaIva, s.CodiceFiscale),
			[Condivisa] = IIF(v.Condivisa = 1, 'Sì', 'No'),
			[Operatore DIWASS] = o.Nome,
			[Id operatore DIWASS] = o.OperatorInternalId,
			[Id sede principale DIWASS] = o.LinkedOperatorInternalId,
			[Indirizzo su DIWASS] = o.Indirizzo,
			[Identificativo su DIWASS] = o.Identificativo,
			[Stato su DIWASS] = o.Stato,
			[Ultima verifica] = o.DataVerifica
		FROM
			dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v
			INNER JOIN dbo.tblSedi s ON v.Id = s.Id
			LEFT JOIN dbo.tblSedi p ON s.IdParent = p.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON s.Id = o.Id
		WHERE
			(
			@Search IS NULL
			OR s.NomeCompleto LIKE '%' + @Search + '%'
			OR p.NomeCompleto LIKE '%' + @Search + '%'
			OR s.IndirizzoCompleto LIKE '%' + @Search + '%'
			OR s.PartitaIva LIKE '%' + @Search + '%'
			OR s.CodiceFiscale LIKE '%' + @Search + '%'
			)
			AND
				(
				@Collegamento IS NULL
				OR
					(
					@Collegamento = 'S'
					AND o.Id IS NOT NULL
					)
				OR
					(
					@Collegamento = 'N'
					AND o.Id IS NULL
					)
				)
		ORDER BY
			ISNULL(p.NomeCompleto, s.NomeCompleto),
			ISNULL(s.IdParent, s.Id),
			IIF(s.IdParent IS NULL, 0, 1),
			s.NomeCompleto
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
