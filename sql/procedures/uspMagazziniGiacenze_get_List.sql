SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF ISNULL(@Vista, '') NOT IN ('A', 'L')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere A (Articolo) o L (Lotto)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

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

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Giacenza (coerente con Rifiuti/Giacenze ed EoW/Giacenze): mai memorizzata, sempre calcolata
		-- carico per carico come quantità della riga di carico confermata meno le relazioni degli
		-- scarichi confermati su quella riga (Movimento.Lock = 0). Quantita = somma dei residui;
		-- CarichiNumero = carichi con un residuo, cioè quelli che compongono la giacenza;
		-- GiacenzaGiorni = giorni dal più vecchio di quei carichi. In elenco solo le giacenze diverse da 0.
		-- La disponibilità del lotto (CapacitaResidua) resta riferita al caricato: quantità massima
		-- meno caricata, gli scarichi non la fanno risalire.
		SELECT
			c.Id,
			c.IdArticolo,
			c.IdLotto,
			c.[Data],
			c.Quantita,
			Residuo = c.Quantita - ISNULL(x.Scaricata, 0)
		INTO #Carichi
		FROM
			(
				SELECT
					rc.Id,
					rc.IdArticolo,
					rc.IdLotto,
					mc.[Data],
					rc.Quantita
				FROM
					dbo.tblMagazziniMovimentiRighe rc
					INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
					INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON rc.IdSede = i.Id
				WHERE
					rc.IdSede = @idSede
					AND mc.IdOperazione = 'C'
					-- Le righe descrittive del DDT (senza articolo) non sono carichi
					AND rc.IdArticolo IS NOT NULL
					AND rc.Lock = 0
					AND mc.Lock = 0
			) c
			OUTER APPLY (
				SELECT Scaricata = SUM(rel.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel.Id = c.Id
					AND rp.Lock = 0
					AND mp.Lock = 0
			) x
		OPTION (RECOMPILE);

		IF @Vista = 'A'
		BEGIN
			SELECT
				art.Id,
				StatoValore = 0,
				StatoDescrizione = 'OK',
				art.Nome,
				ArticoloNome = CAST(NULL AS VARCHAR(100)),
				UnitaMisuraNome = u.Nome,
				IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				g.Quantita,
				GiacenzaGiorni = DATEDIFF(DAY, g.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				g.CarichiNumero,
				RowsCount = COUNT(*) OVER ()
			FROM
				(
					SELECT
						IdArticolo,
						Quantita = SUM(Residuo),
						CarichiNumero = SUM(IIF(Residuo <> 0, 1, 0)),
						PrimaData = MIN(IIF(Residuo <> 0, [Data], NULL))
					FROM #Carichi
					GROUP BY IdArticolo
				) g
				INNER JOIN dbo.tblMagazziniArticoli art ON g.IdArticolo = art.Id
				LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			WHERE
				g.Quantita <> 0
				AND (@Search IS NULL OR art.Nome LIKE '%' + @Search + '%' OR art.Codice LIKE '%' + @Search + '%')
			ORDER BY art.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END
		ELSE
		BEGIN
			SELECT
				l.Id,
				StatoValore = 0,
				StatoDescrizione = 'OK',
				l.Nome,
				ArticoloNome = art.Nome,
				UnitaMisuraNome = u.Nome,
				IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
				l.QuantitaMax,
				g.Quantita,
				GiacenzaGiorni = DATEDIFF(DAY, g.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - g.Caricata END,
				g.CarichiNumero,
				RowsCount = COUNT(*) OVER ()
			FROM
				(
					SELECT
						IdLotto,
						Caricata = SUM(Quantita),
						Quantita = SUM(Residuo),
						CarichiNumero = SUM(IIF(Residuo <> 0, 1, 0)),
						PrimaData = MIN(IIF(Residuo <> 0, [Data], NULL))
					FROM #Carichi
					GROUP BY IdLotto
				) g
				INNER JOIN dbo.tblMagazziniLotti l ON g.IdLotto = l.Id
				LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
				LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			WHERE
				g.Quantita <> 0
				AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
			ORDER BY l.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END

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
