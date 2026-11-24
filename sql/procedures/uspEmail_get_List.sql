SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email (modulo EML, funzione EMR, solo amministratori): le email del dominio della sessione,
-- dalla piu' recente, a pagine. Ricerca per indirizzo o oggetto (@Search), stato (@Stato: D da inviare, comprese
-- quelle in invio; I inviate; E non inviate; vuoto tutte) e data di creazione (@DallaData, @AllaData).
-- StatoValore come _StatoPartial: 0 inviata (verde), 1 da inviare o in invio (arancione), 2 non inviata (rosso).
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16) = (
			SELECT u.IdDominio
			FROM
				dbo.tblSessioni s
				INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			WHERE s.Id = @IdSessione);

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		SELECT
			e.Id,
			e.Creazione,
			e.Invio,
			e.Tipo,
			TipoNome = CASE e.Tipo WHEN 'S' THEN 'Di servizio' WHEN 'U' THEN 'Avviso' ELSE 'Al cliente' END,
			e.Indirizzo,
			e.Oggetto,
			e.IdStato,
			StatoValore = CASE e.IdStato WHEN 'I' THEN 0 WHEN 'E' THEN 2 ELSE 1 END,
			StatoDescrizione = CASE e.IdStato WHEN 'I' THEN 'Inviata' WHEN 'E' THEN 'Non inviata' WHEN 'P' THEN 'In invio' ELSE 'Da inviare' END,
			e.Tentativi,
			e.ProssimoTentativo,
			e.Nota,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.tblEmail e
		WHERE
			e.IdDominio = @idDominio
			AND (@Search IS NULL OR e.Indirizzo LIKE '%' + @Search + '%' OR e.Oggetto LIKE '%' + @Search + '%')
			AND (@Stato IS NULL OR e.IdStato = @Stato OR (@Stato = 'D' AND e.IdStato = 'P'))
			AND (@DallaData IS NULL OR e.Creazione >= @DallaData)
			AND (@AllaData IS NULL OR e.Creazione < DATEADD(DAY, 1, CAST(@AllaData AS DATETIME2(0))))
		ORDER BY e.Creazione DESC, e.Id DESC
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO
