CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_Calendario_Eventi_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@AllaData SMALLDATETIME = NULL
AS
-- Scadenze del calendario del contesto da @DallaData (compresa) ad @AllaData (esclusa), una per riga, comprese le
-- occorrenze delle serie e le annullate: la pagina le dispone come il calendario a blocchi dei Servizi (S4.7.7,
-- gemella di uspServizi_get_Calendario_Eventi_List) al posto della tabella a celle di uspScadenze_get_Calendario*_List.
-- Le scadenze non hanno durata (righe compatte) ne' richiedente: Descrizione = il testo dell'avviso (tipo e
-- descrizione). Stato: S scaduta, D da eseguire o in esecuzione, E eseguita, A annullata. IdSerie come in
-- uspScadenze_get_ByData_List (S5.8)
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL OR @AllaData IS NULL OR @AllaData <= @DallaData
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il periodo indicato non è valido';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		-- Fine esclusa: ufnEventi_get_List prende gli estremi compresi
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, @AllaData);

		SELECT
			s.Id,
			s.IdEvento,
			IdSerie = ISNULL(s2.Id, s.Id),
			e.[Data],
			e.InGiornata,
			Durata = CAST(NULL AS INT),
			Stato = CASE
				WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 'S'
				WHEN e.IdStato IN ('D', 'I') THEN 'D'
				ELSE e.IdStato
			END,
			StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, NULL),
			Descrizione = ISNULL(e.AvvisoTesto, ''),
			Indirizzo = CAST(NULL AS VARCHAR(200)),
			Risorse = r.Risorse,
			e.Ricorre,
			e.Eccezione
		FROM
			dbo.tblScadenze s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @fine, @IdCalendario, @IdTipo) e ON s.IdEvento = e.Id
			-- Serie dell'occorrenza modificata (come uspScadenze_get_ByData_List)
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM dbo.tblRicorrenzeEccezioni zs
				INNER JOIN dbo.tblScadenze s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = s.IdEvento
					AND zs.Lock = 0
					AND e.Ricorre = 0
			) s2
			-- Soggetti, persone e oggetti collegati, per il testo della riga
			OUTER APPLY (
				SELECT Risorse = STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY o.Tipo, n.Nome)
				FROM
					dbo.tblScadenzeOsepe so
					INNER JOIN dbo.tblOsepe o ON so.IdOsepe = o.Id
					CROSS APPLY (
						SELECT Nome = d.NomeCompleto FROM dbo.tblSedi d WHERE d.Id = so.IdOsepe AND o.Tipo = 'S'
						UNION ALL
						SELECT Nome = p.NomeCompleto FROM dbo.tblPersone p WHERE p.Id = so.IdOsepe AND o.Tipo = 'P'
						UNION ALL
						SELECT Nome = g.Nome FROM dbo.tblOggetti g WHERE g.Id = so.IdOsepe AND o.Tipo = 'O'
					) n
				WHERE so.Id = s.Id
			) r
		ORDER BY e.[Data], s.Id;

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
