SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_get_List
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFattura non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: fattura dell'azienda interna corrente della sessione. Una riga senza importi è di sola
		-- descrizione (ConImporti = 0). Imponibile = Quantita x Importo, arrotondato al centesimo
		SELECT
			r.Id,
			r.Pos,
			r.Descrizione,
			ConImporti = CAST(IIF(i.Id IS NULL, 0, 1) AS BIT),
			i.Quantita,
			i.Importo,
			i.IdUnitaMisura,
			UnitaMisuraCodice = u.Codice,
			i.IdAliquotaIva,
			AliquotaIvaNome = a.Nome,
			i.IdConto,
			ContoNome = c.Nome,
			i.RitenutaAcconto,
			Imponibile = CAST(ROUND(i.Quantita * i.Importo, 2) AS DECIMAL(18, 2))
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
			LEFT JOIN dbo.tblUnitaMisura u ON i.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblAliquoteIva a ON i.IdAliquotaIva = a.Id
			LEFT JOIN dbo.tblFattureConti c ON i.IdConto = c.Id
		WHERE
			r.IdFattura = @IdFattura
			AND e.Id = @IdSessione
		ORDER BY
			ISNULL(r.Pos, 0),
			r.Id;

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
