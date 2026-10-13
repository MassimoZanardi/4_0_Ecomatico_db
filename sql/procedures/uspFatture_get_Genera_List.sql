SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: elenco di dettaglio della verifica
-- ("Visualizza" sulle righe della finestra "Verifica"; i conteggi sono in uspFatture_get_Genera_Riepilogo).
-- Elenca i documenti (registrazioni dei rifiuti e DDT di magazzino) dell'azienda interna corrente della sessione con data
-- nell'intervallo, con il cliente, l'importo e l'imponibile che la generazione userebbe e l'esito:
-- Fatturabile = 1 entra in una fattura, altrimenti Avviso dice perché resta fuori. Stesse righe di
-- uspFatture_ins_Genera (ufnFattureGenera_get_Documenti).
--   @Rifiuti, @Magazzino: da quali documenti generare (registrazioni dei rifiuti, DDT di magazzino). I DDT
--        entrano solo con il modulo Magazzino attivo sul dominio; per un DDT Id è l'Id del movimento.
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente.
--   @IncludiPreFatture = 1: anche i documenti già in una pre-fattura, che verrà convertita in fattura con le
--        sue righe; l'imponibile della pre-fattura è riportato sul suo primo documento.
--   @Esito: solo i documenti con quell'esito (codici di ufnFattureGenera_get_Documenti.Esito); F = tutti quelli
--        che entrano in una fattura (F, S e P). NULL: tutti.
-- I documenti già in una fattura non compaiono; quelli annullati sì, con il loro avviso.
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Esito CHAR(1) = NULL,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@IncludiPreFatture BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Esito = NULLIF(UPPER(LTRIM(RTRIM(@Esito))), '');
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 1000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I DDT entrano solo con il modulo Magazzino attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
			SET @Magazzino = 0;

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			d.Id,
			d.IdModulo,
			Documento = CAST(IIF(d.IdModulo = 'MAG',
				'DDT' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)) + ISNULL('/' + dd.Sezionale, ''), '') + ISNULL(' - ' + sd.NomeCompleto, ''),
				'Registrazione' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)), '')
					+ ISNULL(' - EER ' + e.Nome + IIF(e.Pericoloso = 1, '*', ''), '')) AS VARCHAR(200)),
			d.[Data],
			d.Quantita,
			UnitaMisura = d.IdUnitaMisura,
			Cliente = sc.NomeCompleto,
			Importo = CAST(IIF(d.IdPreFattura IS NULL, i.Nome, 'Righe della pre-fattura') AS VARCHAR(50)),
			Contratto = CAST(IIF(d.IdPreFattura IS NULL AND d.IdOffertaContratto IS NOT NULL, 1, 0) AS BIT),
			PreFattura = CAST(IIF(d.IdPreFattura IS NULL, 0, 1) AS BIT),
			-- Pre-fattura: il suo imponibile una volta sola, sul primo dei suoi documenti
			Totale = d.Imponibile,
			d.Fatturabile,
			d.Esito,
			Avviso = CAST(CASE d.Esito
				WHEN 'P' THEN 'In pre-fattura del ' + ISNULL(CONVERT(VARCHAR(10), f.DataEmissione, 103), '') + ': viene convertita in fattura con le sue righe'
				WHEN 'S' THEN 'Contratto non valido alla data: applicato l''importo standard'
				WHEN 'A' THEN 'Registrazione annullata'
				WHEN 'N' THEN IIF(d.IdModulo = 'MAG', 'Indicato', 'Indicata') + ' come non fatturabile'
				WHEN 'I' THEN IIF(d.IdModulo = 'MAG' AND d.IdImporto IS NOT NULL,
					'L''importo "' + ISNULL(i.Nome, '') + '" non ha una riga per tutti gli articoli o i materiali del DDT',
					IIF(d.IdModulo = 'MAG', 'Nessun importo coincide, o il DDT non ha righe di articoli o materiali', 'Nessun importo coincide'))
				WHEN 'C' THEN 'Cliente non determinato: ' + IIF(d.IdModulo = 'MAG', 'il destinatario', 'il produttore') + ' non ha una scheda cliente'
				WHEN 'R' THEN 'L''importo non ha righe applicabili'
				WHEN 'V' THEN 'Aliquota IVA non indicata né sull''importo né sulla scheda del cliente'
			END AS VARCHAR(300)),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino) d
			LEFT JOIN dbo.tblRifiutiEer e ON d.IdEer = e.Id
			-- DDT: sezionale e destinatario (per un DDT d.Id è il movimento e d.IdProduttore il destinatario)
			LEFT JOIN dbo.tblMagazziniDdt dd ON d.IdModulo = 'MAG'
										  AND d.Id = dd.IdMovimento
			LEFT JOIN dbo.tblSedi sd ON d.IdModulo = 'MAG'
									 AND d.IdProduttore = sd.Id
			LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			LEFT JOIN dbo.tblImporti i ON d.IdImporto = i.Id
			LEFT JOIN dbo.tblFatture f ON d.IdPreFattura = f.Id
		WHERE
				(
				@Esito IS NULL
				OR (@Esito = 'F' AND d.Fatturabile = 1)
				OR (@Esito <> 'F' AND d.Esito = @Esito)
				)
		ORDER BY d.Fatturabile DESC, sc.NomeCompleto, d.[Data], d.Numero, d.Id
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
