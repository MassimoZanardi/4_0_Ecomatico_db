SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Movimenti di magazzino e DDT emessi: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta
-- in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione
-- (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa
-- si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspMagazziniMovimenti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al
-- massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Come l'elenco, serve due pagine: Magazzino > Movimenti (@DdtEmessi = 0) e Magazzino > DDT (@DdtEmessi = 1),
-- con intestazioni diverse sulle stesse righe.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@ConDdt BIT = 0,
	@DdtNumero INT = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtMittente VARCHAR(50) = NULL,
	@DdtDestinatario VARCHAR(50) = NULL,
	@DdtTrasportatore VARCHAR(50) = NULL,
	@DdtEmessi BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		-- Ricerca sul DDT: "Con DDT" limita ai movimenti che hanno un DDT e abilita gli altri filtri
		-- sul DDT, che senza di esso vengono ignorati. Elenco DDT: solo i movimenti con un DDT emesso,
		-- cioè non ricevuto da un fornitore (sezionale R); date e ordinamento sono quelli del DDT
		SET @ConDdt = ISNULL(@ConDdt, 0);
		SET @DdtEmessi = ISNULL(@DdtEmessi, 0);
		IF @DdtEmessi = 1 SET @ConDdt = 1;
		SET @DdtNumeroFornitore = NULLIF(LTRIM(RTRIM(@DdtNumeroFornitore)), '');
		SET @DdtMittente = NULLIF(LTRIM(RTRIM(@DdtMittente)), '');
		SET @DdtDestinatario = NULLIF(LTRIM(RTRIM(@DdtDestinatario)), '');
		SET @DdtTrasportatore = NULLIF(LTRIM(RTRIM(@DdtTrasportatore)), '');
		IF @ConDdt = 0
		BEGIN
			SET @DdtNumero = NULL;
			SET @DdtNumeroFornitore = NULL;
			SET @DdtMittente = NULL;
			SET @DdtDestinatario = NULL;
			SET @DdtTrasportatore = NULL;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Elenco DDT: la sede è quella del contesto della sessione (tblSessioni.IdSede); contesto "tutte le
		-- sedi" = nessuna riga. L'elenco dei movimenti resta sull'azienda del contesto
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT TOP (@MaxRighe + 1)
			Ordine = ROW_NUMBER() OVER (ORDER BY IIF(@DdtEmessi = 1, d.[Data], m.[Data]) DESC, IIF(@DdtEmessi = 1, d.Numero, m.Numero) DESC, m.Numero DESC),
			MovimentoNumero = m.Numero,
			MovimentoData = m.[Data],
			Operazione = o.Nome,
			Righe = ISNULL(r.RigheCount, 0) + ISNULL(re.RigheCount, 0),
			DdtNumero = d.Numero,
			DdtSezionale = d.Sezionale,
			DdtNumeroFornitore = d.NumeroFornitore,
			DdtData = d.[Data],
			DdtCausale = d.CausaleNome,
			DdtSede = d.SedeNome,
			DdtMittente = d.MittenteNome,
			DdtDestinatario = d.DestinatarioNome,
			DdtDestinazione = d.DestinazioneNome,
			DdtTrasportatore = d.TrasportatoreNome,
			DdtInizioTrasporto = d.DataInizioTrasporto,
			DdtPeso = d.Peso
		INTO #righe
		FROM
			dbo.tblMagazziniMovimenti m
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblMagazziniOperazioni o ON m.IdOperazione = o.Id
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = m.Id) r
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = m.Id) re
			-- DDT del movimento (al massimo uno); NULL se non c'è
			OUTER APPLY (
				SELECT TOP (1)
					dd.Id,
					dd.IdSede,
					dd.Numero,
					dd.NumeroFornitore,
					dd.Sezionale,
					dd.[Data],
					dd.IdMittente,
					dd.IdDestinatario,
					dd.IdTrasportatore,
					dd.DataInizioTrasporto,
					dd.Peso,
					SedeNome = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
					CausaleNome = ca.Nome,
					MittenteNome = mt.NomeCompleto + ISNULL(' ' + mt.IndirizzoCompleto, ''),
					DestinatarioNome = ds.NomeCompleto + ISNULL(' ' + ds.IndirizzoCompleto, ''),
					DestinazioneNome = dz.NomeCompleto + ISNULL(' ' + dz.IndirizzoCompleto, ''),
					TrasportatoreNome = tr.NomeCompleto + ISNULL(' ' + tr.IndirizzoCompleto, '')
				FROM
					dbo.tblMagazziniDdt dd
					LEFT JOIN dbo.tblSedi sd ON dd.IdSede = sd.Id
					LEFT JOIN dbo.tblMagazziniCausali ca ON dd.IdCausale = ca.Id
					LEFT JOIN dbo.tblSedi mt ON dd.IdMittente = mt.Id
					LEFT JOIN dbo.tblSedi ds ON dd.IdDestinatario = ds.Id
					LEFT JOIN dbo.tblSedi dz ON dd.IdDestinazione = dz.Id
					LEFT JOIN dbo.tblSedi tr ON dd.IdTrasportatore = tr.Id
				WHERE dd.IdMovimento = m.Id
				ORDER BY dd.Id
			) d
		WHERE
			e.Id = @IdSessione
			AND m.Lock = 0
			AND (@IdOperazione IS NULL OR m.IdOperazione = @IdOperazione)
			AND (@DallaData IS NULL OR IIF(@DdtEmessi = 1, d.[Data], m.[Data]) >= @DallaData)
			AND (@AllaData IS NULL OR IIF(@DdtEmessi = 1, d.[Data], m.[Data]) <= @AllaData)
			AND (@ConDdt = 0 OR d.Id IS NOT NULL)
			AND (@DdtEmessi = 0 OR ISNULL(d.Sezionale, '') <> 'R')
			AND (@DdtEmessi = 0 OR d.IdSede = @idSede)
			AND (@DdtNumero IS NULL OR d.Numero = @DdtNumero)
			AND (@DdtNumeroFornitore IS NULL OR d.NumeroFornitore LIKE '%' + @DdtNumeroFornitore + '%')
			AND (@DdtMittente IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sm WHERE sm.Id = d.IdMittente AND sm.NomeCompleto + ISNULL(' ' + sm.IndirizzoCompleto, '') LIKE '%' + @DdtMittente + '%'))
			AND (@DdtDestinatario IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sn WHERE sn.Id = d.IdDestinatario AND sn.NomeCompleto + ISNULL(' ' + sn.IndirizzoCompleto, '') LIKE '%' + @DdtDestinatario + '%'))
			AND (@DdtTrasportatore IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi st WHERE st.Id = d.IdTrasportatore AND st.NomeCompleto + ISNULL(' ' + st.IndirizzoCompleto, '') LIKE '%' + @DdtTrasportatore + '%'))
		ORDER BY
			IIF(@DdtEmessi = 1, d.[Data], m.[Data]) DESC,
			IIF(@DdtEmessi = 1, d.Numero, m.Numero) DESC,
			m.Numero DESC
		OPTION (RECOMPILE);

		IF @DdtEmessi = 1
			SELECT
				[Numero] = DdtNumero,
				[Sezionale] = DdtSezionale,
				[Data] = DdtData,
				[Causale] = DdtCausale,
				[Mittente] = DdtMittente,
				[Destinatario] = DdtDestinatario,
				[Destinazione] = DdtDestinazione,
				[Trasportatore] = DdtTrasportatore,
				[Inizio trasporto] = DdtInizioTrasporto,
				[Peso] = DdtPeso,
				[Operazione] = Operazione,
				[Movimento] = MovimentoNumero,
				[Data movimento] = MovimentoData,
				[Righe] = Righe
			FROM #righe
			ORDER BY Ordine;
		ELSE
			SELECT
				[Numero] = MovimentoNumero,
				[Data] = MovimentoData,
				[Operazione] = Operazione,
				[Righe] = Righe,
				[DDT nr] = DdtNumero,
				[DDT sezionale] = DdtSezionale,
				[DDT nr fornitore] = DdtNumeroFornitore,
				[DDT data] = DdtData,
				[DDT sede] = DdtSede,
				[DDT causale] = DdtCausale,
				[DDT mittente] = DdtMittente,
				[DDT destinatario] = DdtDestinatario,
				[DDT destinazione] = DdtDestinazione,
				[DDT trasportatore] = DdtTrasportatore,
				[DDT inizio trasporto] = DdtInizioTrasporto,
				[DDT peso] = DdtPeso
			FROM #righe
			ORDER BY Ordine;

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
