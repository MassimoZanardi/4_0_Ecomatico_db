SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali RENTRI (solo dati descrittivi, mai chiavi o segreti): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRentriCredenziali_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRentriCredenziali_get_Esportazione
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Nr. iscrizione] = h.Identificativo,
			[Certificato] = f.Nome,
			[Scadenza del certificato] = f.DataScadenza,
			[Accreditamento] = a.Nome,
			[Stato] = CASE
				WHEN f.DataScadenza < GETDATE() THEN 'Certificato scaduto'
				WHEN DATEDIFF(DAY, GETDATE(), f.DataScadenza) < 30 THEN 'Certificato in scadenza'
				ELSE 'OK'
			END
		FROM
			dbo.tblRentriCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN dbo.tblRentriCertificati f ON c.IdCertificato = f.Id
			LEFT JOIN dbo.tblRentriAccreditamenti a ON c.IdAccreditamento = a.Id
			LEFT JOIN [1_0_rentri]..tblCredenziali h ON c.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
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
