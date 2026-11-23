CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Calendario_Eventi_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@AllaData SMALLDATETIME = NULL
AS
-- Servizi del calendario del contesto da @DallaData (compresa) ad @AllaData (esclusa), uno per riga, comprese le
-- occorrenze delle serie e gli annullati: la pagina li dispone a blocchi (Servizi > Calendario a blocchi, S4.7.7),
-- al posto della tabella a celle di uspServizi_get_Calendario*_List. Stato: S scaduto (da eseguire o in esecuzione
-- con la data passata), D da eseguire o in esecuzione, E eseguito, A annullato. IdSerie come in
-- uspServizi_get_ByData_List (S5.8): per l'occorrenza modificata e' la serie di cui e' il sostituto
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
			@IdFunzione = 'SRV',
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
		INSERT INTO @IdTipo (Id) VALUES ('V');

		-- Fine esclusa: ufnEventi_get_List prende gli estremi compresi
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, @AllaData);

		SELECT
			s.Id,
			s.IdEvento,
			IdSerie = ISNULL(s2.Id, s.Id),
			e.[Data],
			e.InGiornata,
			s.Durata,
			Stato = CASE
				WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 'S'
				WHEN e.IdStato IN ('D', 'I') THEN 'D'
				ELSE e.IdStato
			END,
			StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			Descrizione = ISNULL(e.AvvisoTesto, ''),
			Risorse = r.Risorse,
			e.Ricorre,
			e.Eccezione
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @fine, @IdCalendario, @IdTipo) e ON s.IdEvento = e.Id
			-- Serie dell'occorrenza modificata (come uspServizi_get_ByData_List)
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM dbo.tblRicorrenzeEccezioni zs
				INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = s.IdEvento
					AND zs.Lock = 0
					AND e.Ricorre = 0
			) s2
			-- Persone e oggetti impiegati, per il testo del blocco
			OUTER APPLY (
				SELECT Risorse = STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY o.Tipo, n.Nome)
				FROM
					dbo.tblServiziOsepe so
					INNER JOIN dbo.tblOsepe o ON so.IdOsepe = o.Id
					CROSS APPLY (
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
