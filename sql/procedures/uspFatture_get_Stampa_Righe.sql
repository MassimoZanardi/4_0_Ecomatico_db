SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Righe stampate sulla fattura, nell'ordine di posizione (F4.5). Imponibile di riga = quantità x importo, arrotondato
-- al centesimo (F4.6); una riga di sola descrizione non ha importi (F4.2). I controlli sulla fattura da stampare sono
-- in uspFatture_get_Stampa
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Stampa_Righe
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFatture f
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			WHERE
				f.Id = @Id
				AND e.Id = @IdSessione
				AND f.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			r.Descrizione,
			UnitaMisura = u.Codice,
			Quantita = IIF(i.Id IS NULL, NULL, ISNULL(i.Quantita, 1)),
			i.Importo,
			Imponibile = CAST(ROUND(ISNULL(i.Quantita, 1) * i.Importo, 2) AS DECIMAL(18, 2)),
			AliquotaIva = a.Nome,
			RitenutaAcconto = NULLIF(i.RitenutaAcconto, 0)
		FROM
			dbo.tblFattureRighe r
			LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
			LEFT JOIN dbo.tblUnitaMisura u ON i.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblAliquoteIva a ON i.IdAliquotaIva = a.Id
		WHERE r.IdFattura = @Id
		ORDER BY
			r.Pos,
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