SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_List
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

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

		-- Giacenza per Articolo + Sede, aggregata su tutti i lotti: mai memorizzata,
		-- sempre calcolata da carichi - scarichi confermati (Movimento.Lock = 0)
		SELECT
			art.Id AS IdArticolo,
			ArticoloNome = art.Nome,
			r.IdSede,
			SedeNome = s.Nome,
			UnitaMisuraNome = u.Nome,
			Disponibilita = ISNULL(SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl.Quantita ELSE -rl.Quantita END), 0)
		FROM
			dbo.tblMagazziniMovimentiRigheLotti rl
			INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
			INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON r.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			INNER JOIN dbo.tblMagazziniArticoli art ON r.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
		WHERE
			r.Lock = 0
			AND mv.Lock = 0
			AND (@IdSede IS NULL OR r.IdSede = @IdSede)
			AND (@IdArticolo IS NULL OR r.IdArticolo = @IdArticolo)
		GROUP BY art.Id, art.Nome, r.IdSede, s.Nome, u.Nome
		HAVING ISNULL(SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl.Quantita ELSE -rl.Quantita END), 0) <> 0
		ORDER BY art.Nome, s.Nome
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
