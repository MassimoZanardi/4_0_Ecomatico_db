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
		-- sempre calcolata dalle righe di carico confermate meno le relazioni degli scarichi
		-- confermati su quelle righe (Movimento.Lock = 0)
		SELECT
			art.Id AS IdArticolo,
			ArticoloNome = art.Nome,
			g.IdSede,
			SedeNome = s.Nome,
			UnitaMisuraNome = u.Nome,
			IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			Disponibilita = ISNULL(SUM(g.Quantita), 0)
		FROM
			(
				SELECT
					rc.IdArticolo,
					rc.IdSede,
					rc.Quantita
				FROM
					dbo.tblMagazziniMovimentiRighe rc
					INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
				WHERE
					mc.IdOperazione = 'C'
					AND rc.Lock = 0
					AND mc.Lock = 0

				UNION ALL

				SELECT
					rc.IdArticolo,
					rc.IdSede,
					-rel.Quantita
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rp.Lock = 0
					AND mp.Lock = 0
			) g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			INNER JOIN dbo.tblMagazziniArticoli art ON g.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
		WHERE
			(@IdSede IS NULL OR g.IdSede = @IdSede)
			AND (@IdArticolo IS NULL OR g.IdArticolo = @IdArticolo)
		GROUP BY art.Id, art.Nome, art.IdUnitaMisura, g.IdSede, s.Nome, u.Nome
		HAVING ISNULL(SUM(g.Quantita), 0) <> 0
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
