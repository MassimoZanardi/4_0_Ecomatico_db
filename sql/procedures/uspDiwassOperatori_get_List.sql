SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Operatori: aziende e sedi del contesto (più quelle condivise) con lo stato del collegamento a DIWASS.
-- Ogni azienda è seguita dalle sue sedi
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassOperatori_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Collegamento CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Collegamento = NULLIF(LTRIM(RTRIM(@Collegamento)), '');

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
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: sedi dell'azienda del contesto e condivise (ufnDiwassOperatori_get_SediBySessione_List)
		SELECT
			s.Id,
			StatoValore = CASE
				WHEN o.Id IS NULL THEN 1
				WHEN o.Stato = 'VALID' THEN 0
				ELSE 2
			END,
			StatoDescrizione = CASE
				WHEN o.Id IS NULL THEN 'Non collegato a DIWASS'
				WHEN o.Stato = 'VALID' THEN 'Collegato a DIWASS'
				ELSE 'Operatore DIWASS non valido (' + ISNULL(o.Stato, 'senza ruolo WSR Operator') + ')'
			END + IIF(v.Condivisa = 1, ' - anagrafica condivisa da altre aziende nell''area: ' + v.Area, ''),
			Azienda = ISNULL(p.NomeCompleto, s.NomeCompleto),
			Sede = IIF(s.IdParent IS NULL, NULL, s.NomeCompleto),
			s.IndirizzoCompleto,
			PartitaIva = ISNULL(s.PartitaIva, s.CodiceFiscale),
			OperatoreNome = o.Nome,
			o.OperatorInternalId,
			v.Condivisa,
			RowsCount = COUNT(*) OVER ()
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
