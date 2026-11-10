CREATE OR ALTER PROCEDURE [dbo].[uspCalendari_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso: la select serve al contesto delle pagine degli eventi, quindi basta la lettura
		-- sui Calendari (CLD) oppure su una funzione degli eventi del modulo: SCD per le Scadenze, SRV o SRA
		-- per i Servizi (Servizi > Assegnati con la sola SRA, docs/regole/scadenze-servizi.md S1.3).
		-- @permessoEventi va riportato a NULL prima di ogni chiamata: la SP lo usa come segnale di cache miss
		DECLARE @permesso TINYINT;
		DECLARE @permessoEventi TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'CLD',
			@Permesso = @permesso OUTPUT;
		SET @permesso = ISNULL(@permesso, 0);

		IF @IdModulo = 'SCD'
		BEGIN
			SET @permessoEventi = NULL;
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'SCD',
				@Permesso = @permessoEventi OUTPUT;
			SET @permesso = IIF(ISNULL(@permessoEventi, 0) > @permesso, @permessoEventi, @permesso);
		END
		ELSE IF @IdModulo = 'SRV'
		BEGIN
			SET @permessoEventi = NULL;
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'SRV',
				@Permesso = @permessoEventi OUTPUT;
			SET @permesso = IIF(ISNULL(@permessoEventi, 0) > @permesso, @permessoEventi, @permesso);

			SET @permessoEventi = NULL;
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'SRA',
				@Permesso = @permessoEventi OUTPUT;
			SET @permesso = IIF(ISNULL(@permessoEventi, 0) > @permesso, @permessoEventi, @permesso);
		END

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sul modulo
		IF dbo.ufnModuli_get_IsAttivoBySessione(@IdModulo, @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Determina la selezione corrente: parametro → calendario in sessione → nessuna
		SET @IdSelected = COALESCE(
			NULLIF(LTRIM(RTRIM(@IdSelected)), ''),
			(SELECT s.IdCalendario
			 FROM dbo.tblSessioni s
			 INNER JOIN dbo.tblCalendari c ON s.IdCalendario = c.Id
			 WHERE
				 s.Id = @IdSessione
				 AND c.IdModulo = @IdModulo
				 AND c.Lock = 0
			),
			REPLICATE('0', 16)
		);

		;WITH cte AS (
			-- Opzione vuota sempre in cima
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi per Id e Pos

			-- Calendario selezionato: appare sempre, ma solo se accessibile alla sessione
			-- (stessi filtri di sede/modulo/lock del ramo 3, senza il filtro @Search)
			SELECT
				c.Id,
				[Text] = c.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(e.IdUtente) i
				INNER JOIN dbo.tblCalendari c ON i.Id = c.IdSede
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND c.Id = @IdSelected
				AND c.IdModulo = @IdModulo
				AND c.Lock = 0
				AND c.Id <> REPLICATE('0', 16)
			UNION ALL

			-- Altri calendari accessibili dall'utente della sessione per il modulo
			SELECT
				c.Id,
				[Text] = c.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(e.IdUtente) i
				INNER JOIN dbo.tblCalendari c ON i.Id = c.IdSede
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND c.IdModulo = @IdModulo
				AND c.Lock = 0
				AND c.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR c.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%'
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
		THROW 50001, @returnMessage, 1
	END

END;
