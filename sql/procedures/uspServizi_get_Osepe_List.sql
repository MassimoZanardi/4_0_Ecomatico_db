CREATE PROCEDURE [dbo].[uspServizi_get_Osepe_List]
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
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP 50
			Id,
			Nome,
			Tipo,
			Quantita,
			IdUnitaMisura
		FROM (
			-- Ramo 1: Persone
			SELECT
				s.Id,
				Nome = s.NomeCompleto,
				Tipo = 'Persona',
				a.Quantita,
				s.IdUnitaMisura
			FROM
				dbo.tblServiziOsepe a
			INNER JOIN dbo.tblOsepe o ON a.IdOsepe = o.Id
			INNER JOIN dbo.tblPersone s ON a.IdOsepe = s.Id
			WHERE
				a.Id = @Id
				AND o.Tipo = 'P'
				AND s.Lock = 0
				AND (@Search IS NULL OR s.NomeCompleto LIKE '%' + @Search + '%')
			UNION ALL -- rami mutualmente esclusivi per tipo Osepe

			-- Ramo 2: Oggetti
			SELECT
				s.Id,
				Nome = s.Nome,
				Tipo = 'Oggetto',
				a.Quantita,
				s.IdUnitaMisura
			FROM
				dbo.tblServiziOsepe a
			INNER JOIN dbo.tblOsepe o ON a.IdOsepe = o.Id
			INNER JOIN dbo.tblOggetti s ON a.IdOsepe = s.Id
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
