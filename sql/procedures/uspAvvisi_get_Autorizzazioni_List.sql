SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_Autorizzazioni_List]
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

		-- Pagina dedicata: nega esplicitamente l'accesso senza permesso RAT, come le altre
		-- pagine dell'app (a differenza di uspAvvisi_get_Count, che deve restare tollerante).
		DECLARE @permesso TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('RAT', @IdUtente);
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Soglia "30 giorni" e distinzione scaduta/in scadenza già esistenti in
		-- uspRifiutiAutorizzazioni_get_List: stessa regola di business, riusata qui.
		-- Scoping solo sedi interne (niente aziende esterne condivise), coerente col
		-- resto del sottosistema Avvisi (Scadenze/Servizi, Limiti).
		;WITH tbl AS (
			SELECT
				a.Id,
				StatoValore = CASE WHEN a.DataFine < GETDATE() THEN 2 ELSE 1 END,
				StatoDescrizione = CASE
					WHEN a.DataFine < GETDATE() THEN 'Scaduta'
					ELSE 'In scadenza tra ' + CAST(DATEDIFF(DAY, GETDATE(), a.DataFine) AS VARCHAR) + ' giorni'
				END,
				a.Numero,
				Ruolo = r.Nome,
				SedeNome = s.NomeCompleto + ' - ' + s.IndirizzoCompleto,
				a.DataFine
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON s.Id = i.Id
			WHERE
				a.Nessuna = 0
				AND a.Disabilitata = 0
				AND a.Lock = 0
				AND (a.DataFine < GETDATE() OR DATEDIFF(DAY, GETDATE(), a.DataFine) < 30)
				AND (@Search IS NULL OR a.Numero LIKE '%' + @Search + '%')
		),
		tblCount AS (SELECT COUNT(*) AS RowsCount FROM tbl)
		SELECT
			tbl.Id,
			tbl.StatoValore,
			tbl.StatoDescrizione,
			tbl.Numero,
			tbl.Ruolo,
			tbl.SedeNome,
			tbl.DataFine,
			tblCount.RowsCount
		FROM tbl
		CROSS JOIN tblCount
		ORDER BY tbl.DataFine
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
