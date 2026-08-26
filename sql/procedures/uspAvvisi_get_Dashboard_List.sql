SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_Dashboard_List]
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Nessuna cache: a differenza del badge (polling periodico), questa pagina si
		-- carica una volta per visita, il costo del ricalcolo è accettabile.
		DECLARE @countData DATETIME = GETDATE();

		-- Finestra temporale: ultimi 30 giorni → prossime 4 settimane (stessa di uspAvvisi_get_Count)
		DECLARE @DallaData SMALLDATETIME = DATEADD(DAY, -30, @countData);
		DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 28, @countData);

		-- Calendari accessibili dall'utente sui moduli abilitati
		DECLARE @IdCalendario tvpId_Char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT c.Id
		FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
		INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
		WHERE
			c.Lock = 0
			AND c.IdModulo IN (
			  -- Admin: moduli abilitati sul dominio
			  SELECT dm.IdModulo
			  FROM dbo.tblUtenti u
			  INNER JOIN dbo.tblDominiModuli dm ON u.IdDominio = dm.Id
			  WHERE u.Id = @IdUtente
				AND u.IdRuolo = 'AD'

			  UNION ALL -- AD e US mutualmente esclusivi

			  -- Utente Standard: moduli delle funzioni con permesso esplicito
			  SELECT f.Id
			  FROM dbo.tblUtenti u
			  INNER JOIN dbo.tblUtentiFunzioni uf ON u.Id = uf.Id
			  INNER JOIN dbo.tblModuliFunzioni f ON uf.IdFunzione = f.IdFunzione
			  WHERE u.Id = @IdUtente
				AND u.IdRuolo = 'US'
		  );

		-- Tipi di eventi accessibili dall'utente
		DECLARE @IdTipo tvpId_Char_1;
		INSERT INTO @IdTipo (Id)
		SELECT t.IdTipo
		FROM dbo.tblUtenti u
		INNER JOIN dbo.tblDominiModuli d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblModuliFunzioni mf ON d.IdModulo = mf.Id
		INNER JOIN dbo.tblFunzioni f ON mf.IdFunzione = f.Id
		INNER JOIN dbo.tblFunzioniEventiTipi t ON f.Id = t.Id
		WHERE
			u.Id = @IdUtente
			AND u.IdRuolo = 'AD'
		UNION ALL -- AD e US mutualmente esclusivi

		SELECT t.IdTipo
		FROM dbo.tblUtenti u
		INNER JOIN dbo.tblUtentiFunzioni uf ON u.Id = uf.Id
		INNER JOIN dbo.tblFunzioniEventiTipi t ON uf.Id = t.Id
		WHERE
			u.Id = @IdUtente
			AND u.IdRuolo = 'US';

		DECLARE @permessoLimiti TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('RLM', @IdUtente);

		SELECT
			Categoria = 'Scadenze/Servizi',
			[Count] = (
				SELECT COUNT(*)
				FROM dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendario, @IdTipo)
				WHERE
					IdStato = 'D'
					AND AvvisoData < @countData
			),
			UrlDestinazione = '/home/avvisi',
			Icona = 'fa-calendar-check'

		UNION ALL -- Categoria esclusa del tutto se manca il permesso RLM

		SELECT
			Categoria = 'Limiti superati',
			[Count] = (
				SELECT COUNT(*)
				FROM dbo.ufnRifiutiLimiti_get_Verifica_List(NULL) v
				INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON v.IdSede = i.Id
				WHERE v.Superato = 1
			),
			UrlDestinazione = '/home/avvisi/limiti',
			Icona = 'fa-exclamation-triangle'
		WHERE @permessoLimiti >= 1
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
GO
