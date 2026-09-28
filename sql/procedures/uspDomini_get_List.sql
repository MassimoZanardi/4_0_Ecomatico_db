CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_List]
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

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		SELECT
			d.Id,
			StatoValore = CASE
				WHEN d.Scadenza < GETDATE() THEN 2
				WHEN d.IdStato = 'SO' THEN 2
				WHEN DATEDIFF(DAY, GETDATE(), d.Scadenza) < 30 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN d.Scadenza < GETDATE() THEN 'Dominio scaduto'
				WHEN d.IdStato = 'SO' THEN 'Dominio sospeso'
				WHEN DATEDIFF(DAY, GETDATE(), d.Scadenza) < 30 THEN 'Dominio in scadenza'
				ELSE 'OK'
			END,
			d.Registrazione,
			d.Scadenza,
			d.Nome,
			d.Riferimento,
			UltimoAccessoData = IIF(ua.[Data] IS NULL, 'Nessuno', FORMAT(ua.[Data], 'dd/MM/yyyy HH:mm')),
			UltimoAccessoUtente = IIF(ua.Email IS NULL, 'Nessuna', ua.Email),
			d.Codice,
			UtenteMaster = um.Email,
			IsStart = CAST(IIF(d.Logo IS NULL, 0, 1) AS BIT),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblDomini d
			OUTER APPLY (
				SELECT TOP 1 u.Email
				FROM dbo.tblUtenti u
				WHERE
					u.IdDominio = d.Id
					AND u.[Master] = 1
			) um
				OUTER APPLY (
				SELECT TOP 1 e.[Data], u.Email
				FROM dbo.tblUtentiLogin e
				INNER JOIN dbo.tblUtenti u ON e.Id = u.Id
				WHERE
					u.IdDominio = d.Id
					AND u.[Master] = 0
					AND d.[Master] = 0
				ORDER BY e.[Data] DESC
			) ua
		WHERE
			d.Lock = 0
			AND
				(
				@Search IS NULL
				OR d.Nome LIKE '%' + @Search + '%'
				OR d.Riferimento LIKE '%' + @Search + '%'
				)
		ORDER BY d.Registrazione DESC
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
