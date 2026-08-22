CREATE PROCEDURE [dbo].[uspSedi_get_AziendeEsterne_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@CodiceFiscale VARCHAR(50) = NULL,
	@Note VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANS',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Indirizzo = dbo.ufnStringhe_get_SenzaSpazi(@Indirizzo, 0, 1);
		SET @CodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		WITH tbl AS (
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
				Tipo = t.NomeParent,
				s.NomeCompleto,
				s.IndirizzoCompleto,
				s.CodiceFiscale,
				s.PartitaIva,
				s.Note
			FROM
				dbo.tblSedi s
			INNER JOIN dbo.tblSediTipi t ON s.IdTipo = t.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			OUTER APPLY (
					SELECT TOP 1 a.Id, Area = a.Nome
					FROM
						dbo.tblAreeOsepe ae
					INNER JOIN dbo.tblAree a ON ae.Id = a.Id
					WHERE
						a.Lock = 0
						AND ae.IdOsepe = s.Id
			) c
			WHERE
				e.Id = @IdSessione
				AND s.InternaEsterna = 'E'
				AND s.IdParent IS NULL
				AND s.Lock = 0
			UNION ALL

			SELECT
				s.Id,
				StatoValore = 1,
				StatoDescrizione = 'Anagrafica condivisa da altre aziende nell''area: ' + c.Area,
				Tipo = t.NomeParent,
				s.NomeCompleto,
				s.IndirizzoCompleto,
				s.CodiceFiscale,
				s.PartitaIva,
				s.Note
			FROM
				dbo.tblSedi s
			INNER JOIN dbo.tblSediTipi t ON s.IdTipo = t.Id
			CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM
						dbo.tblSessioni e
					CROSS APPLY dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdAziendaInterna <> e.IdAzienda
			) c
		)
		SELECT
			tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
			tbl.Tipo, tbl.NomeCompleto, tbl.IndirizzoCompleto,
			tbl.CodiceFiscale, tbl.PartitaIva, tbl.Note,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		WHERE
			(@Nome IS NULL OR tbl.NomeCompleto LIKE '%' + @Nome + '%')
			AND (@Indirizzo IS NULL OR tbl.IndirizzoCompleto LIKE '%' + @Indirizzo + '%')
			AND (@CodiceFiscale IS NULL OR tbl.CodiceFiscale LIKE '%' + @CodiceFiscale + '%')
			AND (@Note IS NULL OR tbl.Note LIKE '%' + @Note + '%')
		ORDER BY tbl.NomeCompleto
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
