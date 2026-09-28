CREATE OR ALTER PROCEDURE [dbo].[uspOsepe_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@Contesto INT = -1,
	@IncludiOggetti BIT = 1,
	@IncludiSedi BIT = 1,
	@IncludiPersone BIT = 1,
	@ImpiegabileServizi BIT = 0,
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

		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

		-- Tabella tipi da includere in base ai parametri
		DECLARE @tblTipi TABLE (Tipo CHAR(1));
		IF @IncludiOggetti = 1 INSERT @tblTipi (Tipo) VALUES ('O');
		IF @IncludiSedi = 1 INSERT @tblTipi (Tipo) VALUES ('S');
		IF @IncludiPersone = 1 INSERT @tblTipi (Tipo) VALUES ('P');

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
		-- Contesto = 4 (Magazzino) rimosso: tblMagazzini non esiste più nello schema
		-- e non era mai usato da nessuna pagina (funzionalità superata dal nuovo modulo
		-- "Gestione Magazzino", che non usa questo Contesto).
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
			-- Opzione vuota sempre in cima
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi: solo uno dei tre
					   -- corrisponderà all'@IdSelected

			-- Sede selezionata
			SELECT
				Id,
				[Text] = NomeCompleto + ' ' + IndirizzoCompleto,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblSedi
			WHERE
				Id = @IdSelected
				AND Id <> @idSediciZeri
				AND Lock = 0
			UNION ALL

			-- Persona selezionata
			SELECT
				Id,
				[Text] = NomeCompleto,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblPersone
			WHERE
				Id = @IdSelected
				AND Id <> @idSediciZeri
				AND Lock = 0
			UNION ALL

			-- Oggetto selezionato
			SELECT
				Id,
				[Text] = Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblOggetti
			WHERE
				Id = @IdSelected
				AND Id <> @idSediciZeri
				AND Lock = 0
			UNION ALL

			-- Osepe accessibili dall'utente nel dominio corrente
			-- u.IdSede corrisponde a IdAziendaInterna in ufnOsepe_get_ByUtente_List
			SELECT
				u.Id,
				[Text] = u.[Text],
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
			WHERE
				e.Id = @IdSessione
				AND
					(
						(
						u.IdDominio = e.IdDominio
						AND u.Condivisa = 1
						)
					OR u.IdSede = ISNULL(@idAziendaInterna, u.IdSede)
					)
				AND u.Tipo IN (SELECT Tipo FROM @tblTipi)
				AND u.Disabilitata = 0
				AND u.ImpiegabileServizi = IIF(@ImpiegabileServizi = 1, 1, u.ImpiegabileServizi)
				AND u.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR u.[Text] LIKE '%' + @Search + '%'
					)
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
