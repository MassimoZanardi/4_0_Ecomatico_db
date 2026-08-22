CREATE PROCEDURE [dbo].[uspOggetti_get_List]
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
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		WITH tbl AS (
			-- Ramo 1: oggetti dell'azienda della sessione
			SELECT
				s.Id,
				StatoValore = CASE
					WHEN s.Disabilitata = 1 THEN 2
					WHEN c.Id IS NULL THEN 0
					ELSE 1
				END,
				StatoDescrizione = CASE
					WHEN s.Disabilitata = 1 THEN 'Anagrafica disabilitata'
					WHEN c.Id IS NULL THEN 'OK'
					ELSE 'Anagrafica condivisa da questa azienda nell''area: ' + c.Area
				END,
				s.Nome,
				s.IdUnitaMisura,
				s.Codice
			FROM
				dbo.tblOggetti s
				INNER JOIN dbo.tblSessioni e ON s.IdSede = e.IdAzienda
				OUTER APPLY (
					SELECT TOP 1 a.Id, Area = a.Nome
					FROM dbo.tblAreeOsepe ae
					INNER JOIN dbo.tblAree a ON ae.Id = a.Id
					WHERE
						a.Lock = 0
						AND ae.IdOsepe = s.Id
				) c
			WHERE
				e.Id = @IdSessione
				AND s.Lock = 0
			UNION ALL -- rami distinti: ramo 1 = azienda corrente, ramo 2 = altre aziende

			-- Ramo 2: oggetti condivisi da altre aziende
			SELECT
				s.Id,
				StatoValore = 1,
				StatoDescrizione = 'Oggetto condiviso da altre aziende nell''area: ' + c.Area,
				s.Nome,
				s.IdUnitaMisura,
				s.Codice
			FROM
				dbo.tblOggetti s
				CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM dbo.tblSessioni e
					CROSS APPLY dbo.ufnOggetti_get_CondivisiByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdSede <> e.IdAzienda
				) c
		)
		SELECT
			tbl.Id,
			tbl.StatoValore,
			tbl.StatoDescrizione,
			tbl.Nome,
			tbl.IdUnitaMisura,
			tbl.Codice,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		WHERE (@Search IS NULL OR tbl.Nome LIKE '%' + @Search + '%')
		ORDER BY tbl.Nome
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
		THROW 50001, @returnMessage, 1
	END

END;
