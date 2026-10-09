SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modelli dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiModelli_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiModelli_get_Esportazione
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RMD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Scope: registro corrente della sessione (tblSessioni.IdRegistro); senza registro nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = m.Nome,
			[Operazione] = o.Nome,
			[Codice EER] = e.Nome,
			[Descrizione EER] = e.Descrizione,
			[Pericoloso] = CASE e.Pericoloso WHEN 1 THEN 'Sì' WHEN 0 THEN 'No' END,
			[Stato fisico] = s.Nome,
			[Attività] = a.Codice,
			[Unità di misura] = um.Codice,
			[Materiale] = mt.Nome,
			[Etichette] = (SELECT STRING_AGG(x.Nome, ', ') WITHIN GROUP (ORDER BY x.Nome) FROM dbo.tblRifiutiModelliEtichette me INNER JOIN dbo.tblEtichette x ON me.IdEtichetta = x.Id WHERE me.Id = m.Id),
			[Note] = m.UtenteNote
		FROM
			dbo.tblRifiutiModelli m
			INNER JOIN dbo.tblSessioni ses ON m.IdRegistro = ses.IdRegistro
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			LEFT JOIN dbo.tblUnitaMisura um ON m.IdUnitaMisura = um.Id
			LEFT JOIN dbo.tblRifiutiMateriali mt ON m.IdMateriale = mt.Id
		WHERE
			ses.Id = @IdSessione
			AND m.Lock = 0
			AND (@Search IS NULL OR m.Nome LIKE '%' + @Search + '%')
		ORDER BY m.Nome
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