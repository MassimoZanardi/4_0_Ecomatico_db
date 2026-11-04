SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_get_List]
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		-- Stato (_StatoPartial): scadenza della credenziale, valida fino al giorno indicato compreso
		SELECT
			c.Id,
			StatoValore = CASE
				WHEN c.Scadenza < CAST(GETDATE() AS DATE) THEN 2
				WHEN DATEDIFF(DAY, GETDATE(), c.Scadenza) < 30 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN c.Scadenza < CAST(GETDATE() AS DATE) THEN 'Credenziale scaduta'
				WHEN DATEDIFF(DAY, GETDATE(), c.Scadenza) < 30 THEN 'Credenziale in scadenza'
				ELSE 'OK'
			END,
			c.Nome,
			h.ClientId,
			c.Scadenza,
			AziendeCount = (SELECT COUNT(*)
			FROM dbo.tblViviFirCredenzialiAziende a
			WHERE a.IdCredenziale = c.Id),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblViviFirCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN [1_0_vivifir]..tblCredenziali h ON c.IdViviFir = h.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR h.ClientId LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
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
