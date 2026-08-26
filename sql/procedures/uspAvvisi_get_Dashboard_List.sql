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

		DECLARE @permessoScadenze TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('SCD', @IdUtente);
		DECLARE @permessoServizi TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('SRV', @IdUtente);
		DECLARE @permessoLimiti TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('RLM', @IdUtente);
		DECLARE @permessoAutorizzazioni TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('RAT', @IdUtente);

		-- Permesso già verificato: niente branching AD/US, filtro diretto sul modulo.
		DECLARE @IdCalendarioScadenze tvpId_Char_16;
		INSERT INTO @IdCalendarioScadenze (Id)
		SELECT c.Id
		FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
		INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
		WHERE c.Lock = 0 AND c.IdModulo = 'SCD';

		DECLARE @IdTipoScadenze tvpId_Char_1;
		INSERT INTO @IdTipoScadenze (Id) VALUES ('S');

		DECLARE @IdCalendarioServizi tvpId_Char_16;
		INSERT INTO @IdCalendarioServizi (Id)
		SELECT c.Id
		FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
		INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
		WHERE c.Lock = 0 AND c.IdModulo = 'SRV';

		DECLARE @IdTipoServizi tvpId_Char_1;
		INSERT INTO @IdTipoServizi (Id) VALUES ('V');

		SELECT
			Categoria = 'Scadenze',
			[Count] = (
				SELECT COUNT(*)
				FROM dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendarioScadenze, @IdTipoScadenze)
				WHERE
					IdStato = 'D'
					AND AvvisoData < @countData
			),
			UrlDestinazione = '/home/avvisi/scadenze',
			Icona = 'fa-calendar-check'
		WHERE @permessoScadenze >= 1 -- categoria esclusa del tutto se manca il permesso SCD

		UNION ALL -- Categoria esclusa del tutto se manca il permesso SRV

		SELECT
			Categoria = 'Servizi',
			[Count] = (
				SELECT COUNT(*)
				FROM dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendarioServizi, @IdTipoServizi)
				WHERE
					IdStato = 'D'
					AND AvvisoData < @countData
			),
			UrlDestinazione = '/home/avvisi/servizi',
			Icona = 'fa-calendar-alt'
		WHERE @permessoServizi >= 1

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

		UNION ALL -- Categoria esclusa del tutto se manca il permesso RAT

		SELECT
			Categoria = 'Autorizzazioni in scadenza',
			[Count] = (
				SELECT COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON a.IdSede = i.Id
				WHERE
					a.Nessuna = 0
					AND a.Disabilitata = 0
					AND a.Lock = 0
					AND (a.DataFine < @countData OR DATEDIFF(DAY, @countData, a.DataFine) < 30)
			),
			UrlDestinazione = '/home/avvisi/autorizzazioni',
			Icona = 'fa-file-contract'
		WHERE @permessoAutorizzazioni >= 1
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
