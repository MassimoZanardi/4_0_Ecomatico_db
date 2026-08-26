SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_Limiti_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdUtente CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Pagina dedicata: a differenza di uspAvvisi_get_Count (dove il permesso mancante
		-- su un solo modulo non deve rompere il conteggio aggregato), qui neghiamo
		-- esplicitamente l'accesso, come le altre pagine dell'app.
		DECLARE @permesso TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('RLM', @IdUtente);
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH tbl AS (
			SELECT v.*
			FROM dbo.ufnRifiutiLimiti_get_Verifica_List(NULL) v
			INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON v.IdSede = i.Id
			WHERE
				v.Superato = 1
				AND (@Search IS NULL OR v.Nome LIKE '%' + @Search + '%')
		),
		tblCount AS (SELECT COUNT(*) AS RowsCount FROM tbl)
		SELECT
			tbl.Id,
			tbl.Nome,
			SedeNome = s.Nome + ' ' + s.IndirizzoCompleto,
			RegistroNome = tbl.RegistroVerificaNome,
			tbl.IdUnitaMisura,
			tbl.Riferimento,
			tbl.Intervallo,
			tbl.Valore,
			tbl.ValoreAttuale,
			tblCount.RowsCount
		FROM tbl
		INNER JOIN dbo.tblSedi s ON s.Id = tbl.IdSede
		CROSS JOIN tblCount
		ORDER BY s.Nome, tbl.Nome, tbl.RegistroVerificaNome
		OFFSET @Offset ROWS
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
