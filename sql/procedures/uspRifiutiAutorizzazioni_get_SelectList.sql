CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdRuolo CHAR(1) = NULL,
	@IdOperazione CHAR(1) = NULL,
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
		SET @IdRuolo = NULLIF(LTRIM(RTRIM(@IdRuolo)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRuolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRuolo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdOperazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdOperazione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Normalizza @IdSelected: NULL → nessuna selezione
		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Determina se il ruolo richiede una sede specifica (es. trasportatore → azienda interna)
		DECLARE @isSede BIT;
		SELECT @isSede = CASE
			WHEN @IdRuolo = 'P' THEN ProduttoreSede
			WHEN @IdRuolo = 'T' THEN TrasportatoreSede
			WHEN @IdRuolo = 'D' THEN DestinatarioSede
			WHEN @IdRuolo = 'I' THEN IntermediarioSede
			ELSE 0
		END
		FROM dbo.tblRifiutiOperazioni
		WHERE Id = @IdOperazione;

		-- @isSede = 1 → @idSede è la sede specifica del registro (o azienda interna per T/I)
		-- @isSede = 0 → @idSede è l'azienda interna, usata per filtrare per IdAziendaInterna
		DECLARE @idSede CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idSede = CASE
						  WHEN @IdRuolo IN ('T', 'I') THEN s.IdAziendaInterna
						  ELSE s.Id
					  END,
			@idUtente = e.IdUtente
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblRifiutiRegistri r ON e.IdRegistro = r.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Calcolo unico delle sedi visibili all'utente: evita di richiamare
		-- ufnSedi_get_SediByUtente_List più volte nella stessa esecuzione
		SELECT
			Id, IdParent, IdAziendaInterna, IdDominio, Condivisa, Disabilitata, Interna
		INTO #sediUtente
		FROM dbo.ufnSedi_get_SediByUtente_List(@idUtente);

		CREATE UNIQUE CLUSTERED INDEX IX_sediUtente_Id ON #sediUtente (Id);

		-- ── Ramo NON produttori (Trasportatori, Destinatari, Intermediari) ──────
		IF @IdRuolo <> 'P'
		BEGIN
			;WITH cte AS (
				SELECT
					Id = CAST(@idSediciZeri AS CHAR(16)),
					[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
					Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
					Pos = 0

				UNION ALL -- ramo selezionato: sempre presente se <> '000...'

				SELECT
					a.Id,
					[Text] = ISNULL(a.Numero + ' ', '') + s.NomeCompleto + ' ' + s.IndirizzoCompleto + ISNULL(' - ' + a.Identificativo, ''),
					Selected = CAST(1 AS BIT),
					Pos = 1
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				WHERE
					a.Id = @IdSelected
					AND a.Id <> @idSediciZeri
				UNION ALL -- altri risultati filtrabili

				SELECT
					a.Id,
					[Text] = ISNULL(a.Numero + ' ', '') + s.NomeCompleto + ' ' + s.IndirizzoCompleto + ISNULL(' - ' + a.Identificativo, ''),
					Selected = CAST(0 AS BIT),
					Pos = 2
				FROM
					#sediUtente u
					INNER JOIN dbo.tblRifiutiAutorizzazioni a ON u.Id = a.IdSede
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				WHERE
					( (@isSede = 1 AND a.IdSede = @idSede) OR (@isSede = 0 AND u.IdAziendaInterna = @idSede) OR (@isSede = 0 AND u.Condivisa = 1) )
					AND a.Disabilitata = 0
					AND s.Disabilitata = 0
					AND u.Disabilitata = 0
					AND a.Id <> @IdSelected
					AND a.IdRuolo = @IdRuolo
					AND a.Lock < 2
					AND (@Search IS NULL OR ISNULL(a.Numero + ' ', '') + s.NomeCompleto + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%')
			)
			SELECT TOP 20 Id, [Text], Selected
			FROM cte ORDER BY Pos, [Text]
			OPTION (RECOMPILE);
		END

		-- ── Ramo PRODUTTORI ─────────────────────────────────────────────────────
		ELSE
		BEGIN
			;WITH cte AS (
				SELECT
					Id = CAST(@idSediciZeri AS CHAR(16)),
					[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
					Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
					Pos = 0

				UNION ALL -- autorizzazione selezionata

				SELECT
					a.Id,
					[Text] = ISNULL(a.Numero + ' ', '') + s.NomeCompleto + ' ' + s.IndirizzoCompleto + ISNULL(' - ' + a.Identificativo, ''),
					Selected = CAST(1 AS BIT),
					Pos = 1
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				WHERE
					a.Id = @IdSelected
					AND a.Id <> @idSediciZeri
				UNION ALL -- sede selezionata (produttore senza autorizzazione specifica)

				SELECT
					s.Id,
					[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
					Selected = CAST(1 AS BIT),
					Pos = 1
				FROM dbo.tblSedi s
				WHERE
					s.Id = @IdSelected
					AND s.Id <> @idSediciZeri
					AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioni WHERE Id = @IdSelected)
				UNION ALL -- sedi senza autorizzazione Nessuna=1

				SELECT
					s.Id,
					[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
					Selected = CAST(0 AS BIT),
					Pos = 2
				FROM
					#sediUtente u
					INNER JOIN dbo.tblSedi s ON u.Id = s.Id
				WHERE
					( (@isSede = 1 AND s.Id = @idSede) OR (@isSede = 0 AND s.IdAziendaInterna = @idSede) OR (@isSede = 0 AND u.Condivisa = 1) )
					AND s.Id <> @IdSelected
					AND u.Disabilitata = 0
					AND NOT EXISTS ( SELECT 1 FROM dbo.tblRifiutiAutorizzazioni a WHERE s.Id = a.IdSede AND a.Nessuna = 1 AND a.IdRuolo = 'P' AND a.Lock = 0 )
					AND (@Search IS NULL OR s.NomeCompleto + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%')
				UNION ALL -- autorizzazioni produttore

				SELECT
					a.Id,
					[Text] = ISNULL(a.Numero + ' ', '') + s.NomeCompleto + ' ' + s.IndirizzoCompleto + ISNULL(' - ' + a.Identificativo, ''),
					Selected = CAST(0 AS BIT),
					Pos = 2
				FROM
					#sediUtente u
					INNER JOIN dbo.tblRifiutiAutorizzazioni a ON u.Id = a.IdSede
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				WHERE
					( (@isSede = 1 AND a.IdSede = @idSede) OR (@isSede = 0 AND u.IdAziendaInterna = @idSede) OR (@isSede = 0 AND u.Condivisa = 1) )
					AND a.Disabilitata = 0
					AND s.Disabilitata = 0
					AND u.Disabilitata = 0
					AND a.Id <> @IdSelected
					AND a.IdRuolo = @IdRuolo
					AND a.Lock < 2
					AND (@Search IS NULL OR ISNULL(a.Numero + ' ', '') + s.NomeCompleto + ' ' + s.IndirizzoCompleto + ISNULL(' - ' + a.Identificativo, '') LIKE '%' + @Search + '%')
			)
			SELECT TOP 20 Id, [Text], Selected
			FROM cte ORDER BY Pos, [Text]
			OPTION (RECOMPILE);
		END

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
