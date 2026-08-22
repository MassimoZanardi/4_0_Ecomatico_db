CREATE PROCEDURE [dbo].[uspSedi_get_Sedi_SelectList]
	@IdSessione CHAR(16) = NULL,
	@Contesto INT = -1,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Normalizza: NULL → nessuna selezione
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

		/*
        *   Imposta @idAziendaInterna in funzione del Contesto
        *   0 = Dominio    → IdDominio    (solo da sessione su dominio Master) -- non implementato
        *   1 = Azienda    → IdAzienda
        *   2 = Sede       → IdSede
        *   3 = Registro   → IdRegistro
        *   4 = Magazzino  → IdMagazzino
        *   5 = Calendario → IdCalendario
        */
		DECLARE @idAziendaInterna CHAR(16);
		IF @Contesto = 1 -- Azienda
		BEGIN
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblSessioni e
			INNER JOIN dbo.tblSedi s ON e.IdAzienda = s.Id
			WHERE e.Id = @IdSessione;
		END
		ELSE IF @Contesto = 2 -- Sede
		BEGIN
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblSessioni e
			INNER JOIN dbo.tblSedi s ON e.IdSede = s.Id
			WHERE e.Id = @IdSessione;
		END
		ELSE IF @Contesto = 3 -- Registro
		BEGIN
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblSessioni e
			INNER JOIN dbo.tblRifiutiRegistri c ON e.IdRegistro = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE e.Id = @IdSessione;
		END
		ELSE IF @Contesto = 4 -- Magazzino
		BEGIN
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblSessioni e
			INNER JOIN dbo.tblMagazzini c ON e.IdMagazzino = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE e.Id = @IdSessione;
		END
		ELSE IF @Contesto = 5 -- Calendario
		BEGIN
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE e.Id = @IdSessione;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				s.Id,
				[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSelected
				AND s.Id <> @idSediciZeri
			UNION ALL

			SELECT
				s.Id,
				[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
			INNER JOIN dbo.tblSedi s ON u.Id = s.Id
			WHERE
				e.Id = @IdSessione
				AND ( (u.IdDominio = e.IdDominio AND u.Condivisa = 1) OR u.IdAziendaInterna = ISNULL(@idAziendaInterna, u.IdAziendaInterna) )
				AND u.Disabilitata = 0
				AND s.Id <> @IdSelected
				AND (@Search IS NULL OR s.NomeCompleto + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%')
		)
		SELECT TOP 50
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text]
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
