CREATE PROCEDURE [dbo].[uspAree_get_Osepe_List]
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
			Id,
			Nome,
			Tipo,
			Condivisioni
		FROM (
			-- Ramo 1: Sedi
			SELECT
				s.Id,
				Nome = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Tipo = 'Sede',
				c.Condivisioni
			FROM
				dbo.tblAreeOsepe a
			INNER JOIN dbo.tblOsepe o ON a.IdOsepe = o.Id
			INNER JOIN dbo.tblSedi s ON a.IdOsepe = s.Id
			OUTER APPLY (
					SELECT Condivisioni = COUNT(*)
					FROM dbo.tblAreeOsepe ae
					INNER JOIN dbo.tblAree ar ON ae.Id = ar.Id
					WHERE
						ae.IdOsepe = s.Id
						AND ar.Lock = 0
			) c
			WHERE
				a.Id = @Id
				AND o.Tipo = 'S'
				AND s.Lock = 0
				AND (@Search IS NULL OR s.NomeCompleto + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%')
			UNION ALL -- rami mutualmente esclusivi per tipo Osepe

			-- Ramo 2: Persone
			SELECT
				s.Id,
				Nome = s.NomeCompleto,
				Tipo = 'Persona',
				c.Condivisioni
			FROM
				dbo.tblAreeOsepe a
			INNER JOIN dbo.tblOsepe o ON a.IdOsepe = o.Id
			INNER JOIN dbo.tblPersone s ON a.IdOsepe = s.Id
			OUTER APPLY (
					SELECT Condivisioni = COUNT(*)
					FROM dbo.tblAreeOsepe ae
					INNER JOIN dbo.tblAree ar ON ae.Id = ar.Id
					WHERE
						ae.IdOsepe = s.Id
						AND ar.Lock = 0
			) c
			WHERE
				a.Id = @Id
				AND o.Tipo = 'P'
				AND s.Lock = 0
				AND (@Search IS NULL OR s.NomeCompleto LIKE '%' + @Search + '%')
			UNION ALL

			-- Ramo 3: Oggetti
			SELECT
				s.Id,
				Nome = s.Nome,
				Tipo = 'Oggetto',
				c.Condivisioni
			FROM
				dbo.tblAreeOsepe a
			INNER JOIN dbo.tblOsepe o ON a.IdOsepe = o.Id
			INNER JOIN dbo.tblOggetti s ON a.IdOsepe = s.Id
			OUTER APPLY (
					SELECT Condivisioni = COUNT(*)
					FROM dbo.tblAreeOsepe ae
					INNER JOIN dbo.tblAree ar ON ae.Id = ar.Id
					WHERE
						ae.IdOsepe = s.Id
						AND ar.Lock = 0
			) c
			WHERE
				a.Id = @Id
				AND o.Tipo = 'O'
				AND s.Lock = 0
				AND (@Search IS NULL OR s.Nome LIKE '%' + @Search + '%')
		) t
		ORDER BY t.Nome;

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
