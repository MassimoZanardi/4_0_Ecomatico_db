SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Aziende: aziende interne del dominio visibili all'utente, con la credenziale DIWASS associata (come
-- Rentri > Sedi per le credenziali RENTRI). Pagina di configurazione: nessun contesto azienda/sede
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

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

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			CredenzialeNome = c.Nome,
			h.Username,
			h.ClientId,
			RowsCount = COUNT(*) OVER ()
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
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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
