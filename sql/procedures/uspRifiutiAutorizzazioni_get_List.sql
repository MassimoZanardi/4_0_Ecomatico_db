
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Numero VARCHAR(50) = NULL,
	@Sede VARCHAR(50) = NULL,
	@IdRuolo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Numero = dbo.ufnStringhe_get_SenzaSpazi(@Numero, 0, 1);
		SET @Sede = dbo.ufnStringhe_get_SenzaSpazi(@Sede, 0, 1);
		SET @IdRuolo = NULLIF(LTRIM(RTRIM(@IdRuolo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		;WITH tbl AS (
			-- Autorizzazioni interne: legate alla sessione tramite IdAziendaInterna
			SELECT
				a.Id,
				StatoValore = CASE
					WHEN a.DataFine < GETDATE() THEN 2
					WHEN a.Disabilitata = 1 THEN 2
					WHEN s.Disabilitata = 1 THEN 2
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 1
					ELSE 0
				END,
				StatoDescrizione = CASE
					WHEN a.DataFine < GETDATE() THEN 'Autorizzazione scaduta'
					WHEN a.Disabilitata = 1 THEN 'Autorizzazione disabilitata'
					WHEN s.Disabilitata = 1 THEN 'Sede disabilitata'
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 'Autorizzazione in scadenza'
					ELSE 'OK'
				END,
				a.Numero,
				a.IdRuolo,
				a.DataInizio,
				a.DataFine,
				Ruolo = r.Nome,
				Sede = s.NomeCompleto + ' - ' + s.IndirizzoCompleto
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND a.Nessuna = 0
				AND a.Lock = 0
				AND
					(
					@Numero IS NULL
					OR a.Numero LIKE '%' + @Numero + '%'
					)
				AND
					(
					@Sede IS NULL
					OR s.NomeCompleto + ' - ' + s.IndirizzoCompleto LIKE '%' + @Sede + '%'
					)
				AND
					(
					@IdRuolo IS NULL
					OR a.IdRuolo = @IdRuolo
					)
			UNION ALL

			-- Autorizzazioni esterne: legate alla sessione tramite aziende esterne condivise
			SELECT
				a.Id,
				StatoValore = CASE
					WHEN a.DataFine < GETDATE() THEN 2
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 1
					ELSE 0
				END,
				StatoDescrizione = CASE
					WHEN a.DataFine < GETDATE() THEN 'Autorizzazione scaduta'
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 'Autorizzazione in scadenza'
					ELSE 'OK'
				END,
				a.Numero,
				a.IdRuolo,
				a.DataInizio,
				a.DataFine,
				Ruolo = r.Nome,
				Sede = s.NomeCompleto + ' - ' + s.IndirizzoCompleto
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblRifiutiAutorizzazioni a ON s.Id = a.IdSede
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				CROSS APPLY (
					SELECT TOP 1 x.Id
					FROM dbo.tblSessioni e
					CROSS APPLY dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdAziendaInterna <> e.IdAzienda
				) c
			WHERE
				a.Disabilitata = 0
				AND a.Nessuna = 0
				AND s.Disabilitata = 0
				AND a.Lock = 0
				AND
					(
					@Numero IS NULL
					OR a.Numero LIKE '%' + @Numero + '%'
					)
				AND
					(
					@Sede IS NULL
					OR s.NomeCompleto + ' - ' + s.IndirizzoCompleto LIKE '%' + @Sede + '%'
					)
				AND
					(
					@IdRuolo IS NULL
					OR a.IdRuolo = @IdRuolo
					)
		)
		SELECT
			tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
			tbl.Numero, tbl.IdRuolo, tbl.DataInizio, tbl.DataFine,
			tbl.Ruolo, tbl.Sede,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		ORDER BY tbl.Sede, tbl.DataFine DESC
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

