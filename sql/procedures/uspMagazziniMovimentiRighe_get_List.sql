SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdArticolo,
			ArticoloNome = a.Nome,
			UnitaMisuraNome = u.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Riga di scarico: quantità già relazionata alle righe di carico consumate
			-- (le righe di carico non hanno relazioni proprie, sono esse stesse la giacenza)
			Relazionata = ISNULL(q.Relazionata, 0),
			r.IdLotto,
			LottoNome = l.Nome,
			IsNumero = CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON r.IdLotto = l.Id
			OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
		WHERE r.IdMovimento = @IdMovimento
		ORDER BY r.Id
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
