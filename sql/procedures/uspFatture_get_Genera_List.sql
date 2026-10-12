SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuovo > Tramite procedura automatica: verifica prima della generazione.
-- Elenca i documenti (per ora le registrazioni dei rifiuti) dell'azienda interna corrente della sessione con data
-- nell'intervallo, con il cliente, l'importo e l'imponibile che la generazione userebbe e l'esito:
-- Fatturabile = 1 entra in una fattura, altrimenti Avviso dice perché resta fuori. Stesse righe di
-- uspFatture_ins_Genera (ufnFattureDocumenti_get_Rifiuti).
--   @Rifiuti = 0: le registrazioni dei rifiuti non sono state scelte (nessuna riga, finché è l'unico modulo).
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente.
--   @IncludiPreFatture = 1: anche i documenti già in una pre-fattura, che verrà convertita in fattura con le
--        sue righe; l'imponibile della pre-fattura è riportato sul suo primo documento.
--   @SoloFatturabili = 1: solo i documenti che verrebbero fatturati.
-- I documenti già in una fattura non compaiono; quelli annullati sì, con il loro avviso.
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@SoloFatturabili BIT = 0,
	@Rifiuti BIT = 1,
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
		SET @SoloFatturabili = ISNULL(@SoloFatturabili, 0);
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
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

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			t.Id,
			IdModulo = CAST('RIF' AS CHAR(3)),
			t.Documento,
			t.[Data],
			t.Quantita,
			UnitaMisura = t.IdUnitaMisura,
			t.Cliente,
			t.Importo,
			t.Contratto,
			t.PreFattura,
			t.Totale,
			t.Fatturabile,
			t.Avviso,
			RowsCount = COUNT(*) OVER (),
			TotaleFatturabile = SUM(IIF(t.Fatturabile = 1, ISNULL(t.Totale, 0), 0)) OVER (),
			DocumentiFatturabili = SUM(IIF(t.Fatturabile = 1, 1, 0)) OVER ()
		FROM
			(
				SELECT
					d.Id,
					d.[Data],
					d.Numero,
					d.Quantita,
					d.IdUnitaMisura,
					d.Fatturabile,
					Documento = CAST('Registrazione' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)), '')
						+ ISNULL(' - EER ' + e.Nome + IIF(e.Pericoloso = 1, '*', ''), '') AS VARCHAR(100)),
					Cliente = sc.NomeCompleto,
					Importo = CAST(IIF(d.IdPreFattura IS NULL, i.Nome, 'Righe della pre-fattura') AS VARCHAR(50)),
					Contratto = CAST(IIF(d.IdPreFattura IS NULL AND d.IdOffertaContratto IS NOT NULL, 1, 0) AS BIT),
					PreFattura = CAST(IIF(d.IdPreFattura IS NULL, 0, 1) AS BIT),
					-- Pre-fattura: il suo imponibile una volta sola, sul primo dei suoi documenti dell'elenco
					Totale = CASE
						WHEN d.IdPreFattura IS NULL THEN d.Totale
						WHEN ROW_NUMBER() OVER (PARTITION BY d.IdPreFattura ORDER BY d.[Data], d.Numero, d.Id) = 1 THEN pf.Imponibile
					END,
					Avviso = CAST(CASE
						WHEN d.IdPreFattura IS NOT NULL THEN 'In pre-fattura del ' + ISNULL(CONVERT(VARCHAR(10), f.DataEmissione, 103), '') + ': viene convertita in fattura con le sue righe'
						WHEN d.Fatturabile = 1 AND d.IdImportoScartato IS NOT NULL AND d.IdOffertaContratto IS NULL THEN 'Contratto non valido alla data: applicato l''importo standard'
						WHEN d.Fatturabile = 1 THEN NULL
						WHEN d.IsAnnullata = 1 THEN 'Registrazione annullata'
						WHEN d.NonFatturabile = 1 THEN 'Indicata come non fatturabile'
						WHEN d.IdImporto IS NULL THEN 'Nessun importo coincide'
						WHEN d.IdClienteFornitore IS NULL THEN 'Cliente non determinato: il produttore non ha una scheda cliente'
						WHEN d.Righe = 0 THEN 'L''importo non ha righe applicabili'
						WHEN d.SenzaIva > 0 THEN 'Aliquota IVA non indicata né sull''importo né sulla scheda del cliente'
					END AS VARCHAR(200))
				FROM
					dbo.ufnFattureDocumenti_get_Rifiuti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
					LEFT JOIN dbo.tblRifiutiEer e ON d.IdEer = e.Id
					LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
					LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
					LEFT JOIN dbo.tblImporti i ON d.IdImporto = i.Id
					LEFT JOIN dbo.tblFatture f ON d.IdPreFattura = f.Id
					OUTER APPLY dbo.ufnFatture_get_Totali(d.IdPreFattura) pf
				WHERE @Rifiuti = 1
			) t
		WHERE
			@SoloFatturabili = 0
			OR t.Fatturabile = 1
		ORDER BY t.Fatturabile DESC, t.Cliente, t.[Data], t.Numero, t.Id
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
