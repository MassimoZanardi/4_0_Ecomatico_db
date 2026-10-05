SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_Carichi_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza @Id: tutti i carichi in giacenza della sede del contesto; con @Id: quelli
		-- dell'articolo (@Vista = A) o del lotto (@Vista = L) indicato, sempre nella sede del contesto
		IF @Id IS NOT NULL AND ISNULL(@Vista, '') NOT IN ('A', 'L')
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

		-- Carichi che compongono la giacenza: righe di carico di movimenti confermati con un residuo,
		-- cioè quantità caricata meno relazioni degli scarichi confermati su quella riga
		SELECT
			rc.Id,
			rc.IdMovimento,
			mc.Numero,
			mc.[Data],
			ArticoloNome = art.Nome,
			LottoNome = l.Nome,
			UnitaMisuraNome = u.Nome,
			IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			rc.Quantita,
			Scaricata = ISNULL(x.Scaricata, 0),
			Residuo = rc.Quantita - ISNULL(x.Scaricata, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniMovimentiRighe rc
			INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON rc.IdSede = i.Id
			INNER JOIN dbo.tblMagazziniArticoli art ON rc.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
			OUTER APPLY (
				SELECT Scaricata = SUM(rel.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel.Id = rc.Id
					AND rp.Lock = 0
					AND mp.Lock = 0
			) x
		WHERE
			rc.IdSede = @idSede
			AND mc.IdOperazione = 'C'
			AND rc.Lock = 0
			AND mc.Lock = 0
			AND rc.Quantita - ISNULL(x.Scaricata, 0) <> 0
			AND (
				@Id IS NULL
				OR (@Vista = 'A' AND rc.IdArticolo = @Id)
				OR (@Vista = 'L' AND rc.IdLotto = @Id)
			)
			AND (
				@Search IS NULL
				OR mc.Numero = TRY_CAST(@Search AS INT)
				OR art.Nome LIKE '%' + @Search + '%'
				OR l.Nome LIKE '%' + @Search + '%'
			)
		ORDER BY mc.[Data] DESC, mc.Numero DESC, rc.Pos, rc.Id
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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
