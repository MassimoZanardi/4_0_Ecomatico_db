CREATE OR ALTER PROCEDURE [dbo].[uspAree_get_SediInterne_List]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblAree
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Area non trovata o già eliminata';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Permesso 1: Admin del dominio a cui appartiene l'area
		-- Permesso 2: Admin Master (accesso globale)
		-- Stesso controllo di uspAree_get: questa SP alimenta una sotto-lista della stessa pagina Edit
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblAree a
			INNER JOIN dbo.tblUtenti u ON a.IdDominio = u.IdDominio
			WHERE
				a.Id = @Id
				AND u.Id = @idUtente
				AND u.IdRuolo = 'AD'
				AND u.Lock = 0
		)
		AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblUtenti ut
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				ut.Id = @idUtente
				AND ut.IdRuolo = 'AD'
				AND ut.Lock = 0
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Normalizza parametri opzionali: collassa spazi multipli interni, trim, NULL se vuoto
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		SELECT TOP 50
			s.Id,
			s.NomeCompleto,
			s.IndirizzoCompleto
		FROM
			dbo.tblAreeSediInterne a
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
		WHERE
			a.Id = @Id
			AND s.Lock = 0
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				OR s.IndirizzoCompleto LIKE '%' + @Search + '%'
				)
		ORDER BY
			s.NomeCompleto;

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
