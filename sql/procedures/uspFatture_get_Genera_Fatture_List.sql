SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: anteprima delle fatture che la
-- generazione creerebbe con gli stessi criteri ("Visualizza" sulla riga delle fatture previste della finestra
-- "Verifica"). Una riga per fattura: cliente, raggruppamento (la sede del produttore o il contratto, quando la
-- scheda del cliente chiede una fattura per sede o per contratto), documenti, pre-fatture convertite, imponibile.
-- La sede è quella del produttore per le registrazioni dei rifiuti, il destinatario per i DDT di magazzino.
-- Stessi documenti e stessi gruppi di uspFatture_ins_Genera (ufnFattureGenera_get_Documenti).
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_Fatture_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@Servizi BIT = 0,
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
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @Servizi = ISNULL(@Servizi, 0);
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
		-- I servizi entrano solo con il modulo Servizi attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0) = 0
			SET @Servizi = 0;

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			Id = t.IdClienteFornitore,
			Cliente = sc.NomeCompleto,
			Raggruppamento = CAST(CASE
				WHEN t.GruppoSede IS NOT NULL THEN 'Sede: ' + sp.NomeCompleto
				WHEN t.GruppoContratto IS NOT NULL THEN 'Contratto'
					+ ISNULL(' ' + NULLIF(oc.Protocollo, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
					+ ISNULL(' - ' + NULLIF(oc.Descrizione, ''), '')
			END AS VARCHAR(300)),
			t.Documenti,
			t.PreFatture,
			t.Imponibile,
			RowsCount = COUNT(*) OVER ()
		FROM
			(
				SELECT
					d.IdClienteFornitore,
					d.GruppoSede,
					d.GruppoContratto,
					Documenti = COUNT(*),
					PreFatture = COUNT(DISTINCT d.IdPreFattura),
					Imponibile = SUM(ISNULL(d.Imponibile, 0))
				FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino, @Servizi) d
				WHERE
					d.Fatturabile = 1
				GROUP BY d.IdClienteFornitore, d.GruppoSede, d.GruppoContratto
			) t
			LEFT JOIN dbo.tblClientiFornitori c ON t.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			LEFT JOIN dbo.tblSedi sp ON t.GruppoSede = sp.Id
			LEFT JOIN dbo.tblOfferteContratti oc ON t.GruppoContratto = oc.Id
		ORDER BY sc.NomeCompleto, t.IdClienteFornitore, t.GruppoSede, t.GruppoContratto
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
