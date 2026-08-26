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

		;WITH Base AS (

		SELECT
			-- Pos della voce di menu di primo livello dell'Area: la dashboard segue
			-- dinamicamente l'ordine delle Aree nel menu, senza doverlo duplicare qui.
			AreaPos = (SELECT m.Pos FROM dbo.tblMenu m WHERE m.IdParent IS NULL AND m.IdArea = 'SCD'),
			Ordine = 0,
			Area = 'Scadenze',
			AreaIcona = (SELECT REPLACE(Icon, 'fal ', '') FROM dbo.tblPagineAree WHERE Nome = 'Scadenze'),
			Categoria = 'Scadenze',
			Descrizione = 'Scadenze imminenti o già scadute',
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
			AreaPos = (SELECT m.Pos FROM dbo.tblMenu m WHERE m.IdParent IS NULL AND m.IdArea = 'SRV'),
			Ordine = 0,
			Area = 'Servizi',
			AreaIcona = (SELECT REPLACE(Icon, 'fal ', '') FROM dbo.tblPagineAree WHERE Nome = 'Servizi'),
			-- "Scadenze" e non "Servizi": il numero conta i servizi con una scadenza
			-- scaduta o imminente, non il totale dei servizi - la fascia sopra indica
			-- già il modulo (Servizi), qui si descrive cosa conta il numero.
			Categoria = 'Scadenze',
			Descrizione = 'Servizi con scadenza imminente o già superata',
			[Count] = (
				SELECT COUNT(*)
				FROM dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendarioServizi, @IdTipoServizi)
				WHERE
					IdStato = 'D'
					AND AvvisoData < @countData
			),
			UrlDestinazione = '/home/avvisi/servizi',
			-- Calendario (non l'icona del modulo Servizi): il sottotitolo indica la natura
			-- "scadenza pianificata" dell'avviso, non il modulo (già indicato sopra).
			Icona = 'fa-calendar-check'
		WHERE @permessoServizi >= 1

		UNION ALL -- Categoria esclusa del tutto se manca il permesso RLM

		SELECT
			AreaPos = (SELECT m.Pos FROM dbo.tblMenu m WHERE m.IdParent IS NULL AND m.IdArea = 'RIF'),
			Ordine = 0,
			Area = 'Rifiuti',
			AreaIcona = (SELECT REPLACE(Icon, 'fal ', '') FROM dbo.tblPagineAree WHERE Nome = 'Rifiuti'),
			Categoria = 'Limiti superati',
			Descrizione = 'Limiti rifiuti che hanno superato la soglia impostata',
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
			AreaPos = (SELECT m.Pos FROM dbo.tblMenu m WHERE m.IdParent IS NULL AND m.IdArea = 'RIF'),
			Ordine = 1,
			Area = 'Rifiuti',
			AreaIcona = (SELECT REPLACE(Icon, 'fal ', '') FROM dbo.tblPagineAree WHERE Nome = 'Rifiuti'),
			Categoria = 'Autorizzazioni in scadenza',
			Descrizione = 'Autorizzazioni rifiuti scadute o in scadenza entro 30 giorni',
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
			-- Calendario: ha una DataFine nota in anticipo, stessa natura di Scadenze/Servizi
			-- (a differenza di Limiti superati, che è un calcolo live senza data pianificata).
			Icona = 'fa-calendar-check'
		WHERE @permessoAutorizzazioni >= 1

		)
		SELECT Area, AreaIcona, Categoria, Descrizione, [Count], UrlDestinazione, Icona
		FROM Base
		ORDER BY AreaPos, Ordine
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
