SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_Lotto
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

		SELECT
			l.Id,
			l.IdSede,
			SedeNome = s.Nome,
			l.IdArticolo,
			ArticoloNome = art.Nome,
			UnitaMisuraNome = u.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			Disponibilita = ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.Caricato, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0)
		FROM
			dbo.tblMagazziniLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
			LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			OUTER APPLY (
				SELECT
					Caricato = SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl.Quantita ELSE 0 END),
					Scaricato = SUM(CASE WHEN mv.IdOperazione = 'S' THEN rl.Quantita ELSE 0 END)
				FROM
					dbo.tblMagazziniMovimentiRigheLotti rl
					INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
					INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
				WHERE
					rl.IdLotto = l.Id
					AND r.Lock = 0
					AND mv.Lock = 0
			) q
		WHERE
			l.Lock = 0
			AND (@IdSede IS NULL OR l.IdSede = @IdSede)
			AND (@IdArticolo IS NULL OR l.IdArticolo = @IdArticolo)
		ORDER BY art.Nome, l.Nome
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
