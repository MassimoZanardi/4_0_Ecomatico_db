SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Carichi_List
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
		IF @Vista NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul Lotto/Magazzino indicato
		IF @Vista = 'L' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @Vista = 'M' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini g INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione AS Id,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			LottoNome = l.Nome,
			QuantitaComplessiva = mo.Quantita,
			QuantitaAttribuita = lr.Quantita,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.tblRifiutiMovimenti mo ON r.IdMovimento = mo.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			r.Lock < 2
			AND ((@Vista = 'L' AND l.Id = @Id) OR (@Vista = 'M' AND l.IdMagazzino = @Id))
			AND (@Search IS NULL OR r.Numero = TRY_CAST(@Search AS INT) OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Data DESC, r.Numero DESC
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
