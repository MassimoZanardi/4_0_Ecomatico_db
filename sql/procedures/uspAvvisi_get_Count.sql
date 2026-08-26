CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_Count]
	@IdUtente CHAR(16) = NULL,
	@Update BIT = 0,
	@Force BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @count INT = NULL;

		-- Validazione parametro
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @countData DATETIME = GETDATE();
		DECLARE @countSecond INT = 3600; -- frequenza aggiornamento in secondi

		IF @Update = 1
		BEGIN
			-- Legge il conteggio dalla cache se ancora valido (saltato con @Force=1:
			-- richiesta manuale di refresh, non il polling periodico automatico)
			IF @Force = 0
				SELECT @count = AvvisiCount
				FROM dbo.tblUtentiDefault
				WHERE
					Id = @IdUtente
					AND DATEDIFF(SECOND, AvvisiCountData, @countData) <= @countSecond;

			-- Cache scaduta, assente o @Force=1: ricalcola
			IF @count IS NULL
			BEGIN
				SET @count = 0;

				-- Finestra temporale: ultimi 30 giorni → prossime 4 settimane
				DECLARE @DallaData SMALLDATETIME = DATEADD(DAY, -30, @countData);
				DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 28, @countData);

				-- Somma le scadenze pendenti (nessun permesso SCD: 0, non un errore).
				-- Permesso già verificato: niente branching AD/US, filtro diretto sul modulo.
				DECLARE @countScadenze INT = 0;
				IF dbo.ufnFunzioni_get_PermessoByUtente('SCD', @IdUtente) >= 1
				BEGIN
					DECLARE @IdCalendarioScadenze tvpId_Char_16;
					INSERT INTO @IdCalendarioScadenze (Id)
					SELECT c.Id
					FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
					INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
					WHERE c.Lock = 0 AND c.IdModulo = 'SCD';

					DECLARE @IdTipoScadenze tvpId_Char_1;
					INSERT INTO @IdTipoScadenze (Id) VALUES ('S');

					SELECT @countScadenze = COUNT(*)
					FROM dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendarioScadenze, @IdTipoScadenze)
					WHERE IdStato = 'D' AND AvvisoData < @countData;
				END

				SET @count = @count + @countScadenze;

				-- Somma i servizi pendenti (nessun permesso SRV: 0, non un errore)
				DECLARE @countServizi INT = 0;
				IF dbo.ufnFunzioni_get_PermessoByUtente('SRV', @IdUtente) >= 1
				BEGIN
					DECLARE @IdCalendarioServizi tvpId_Char_16;
					INSERT INTO @IdCalendarioServizi (Id)
					SELECT c.Id
					FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
					INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
					WHERE c.Lock = 0 AND c.IdModulo = 'SRV';

					DECLARE @IdTipoServizi tvpId_Char_1;
					INSERT INTO @IdTipoServizi (Id) VALUES ('V');

					SELECT @countServizi = COUNT(*)
					FROM dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendarioServizi, @IdTipoServizi)
					WHERE IdStato = 'D' AND AvvisoData < @countData;
				END

				SET @count = @count + @countServizi;

				-- Somma i limiti rifiuti superati (nessun permesso RLM: 0, non un errore)
				DECLARE @countLimiti INT = 0;
				IF dbo.ufnFunzioni_get_PermessoByUtente('RLM', @IdUtente) >= 1
					SELECT @countLimiti = COUNT(*)
					FROM dbo.ufnRifiutiLimiti_get_Verifica_List(NULL) v
					INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON v.IdSede = i.Id
					WHERE v.Superato = 1;

				SET @count = @count + @countLimiti;

				-- Somma le autorizzazioni in scadenza/scadute (nessun permesso RAT: 0, non un errore)
				DECLARE @countAutorizzazioni INT = 0;
				IF dbo.ufnFunzioni_get_PermessoByUtente('RAT', @IdUtente) >= 1
					SELECT @countAutorizzazioni = COUNT(*)
					FROM
						dbo.tblRifiutiAutorizzazioni a
						INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON a.IdSede = i.Id
					WHERE
						a.Nessuna = 0
						AND a.Disabilitata = 0
						AND a.Lock = 0
						AND (a.DataFine < @countData OR DATEDIFF(DAY, @countData, a.DataFine) < 30);

				SET @count = @count + @countAutorizzazioni;

				-- Aggiorna la cache
				UPDATE dbo.tblUtentiDefault
				SET
					AvvisiCount = @count,
					AvvisiCountData = @countData
				WHERE Id = @IdUtente;
			END
		END
		ELSE
		BEGIN
			-- Lettura diretta dalla cache senza ricalcolo
			SELECT @count = AvvisiCount
			FROM dbo.tblUtentiDefault
			WHERE Id = @IdUtente;
		END

		SELECT ISNULL(@count, -1) AS rtn;

	END TRY
	BEGIN CATCH
		-- Fallback intenzionale: un errore nel conteggio non deve bloccare l'utente
		SELECT -1 AS rtn;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
