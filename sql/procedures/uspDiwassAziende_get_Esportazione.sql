SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Aziende (mai la chiave di autenticazione): righe per l'esportazione dell'elenco in Excel e in CSV
-- (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassAziende_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassAziende_get_Esportazione
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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Azienda] = s.NomeCompleto,
			[Indirizzo] = s.IndirizzoCompleto,
			[Credenziale] = c.Nome,
			[Utente EU Login] = h.Username,
			[Client id] = h.ClientId
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			LEFT JOIN dbo.tblDiwassCredenzialiAziende a ON s.Id = a.IdAziendaInterna
			LEFT JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
		WHERE
			e.Id = @IdSessione
			AND i.IdDominio = e.IdDominio
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				OR c.Nome LIKE '%' + @Search + '%'
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
