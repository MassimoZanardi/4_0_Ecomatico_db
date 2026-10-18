SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Riepilogo IVA stampato sulla fattura, una riga per aliquota: stesso calcolo di ufnFatture_get_Totali (IVA
-- sull'imponibile complessivo dell'aliquota, arrotondata al centesimo una volta sola, F4.6). Con l'aliquota a zero
-- la natura (o il riferimento normativo) spiega l'esenzione
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Stampa_Iva
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
			Aliquota = MAX(a.Nome),
			Natura = IIF(ISNULL(MAX(a.Valore), 0) = 0, MAX(ISNULL(a.RiferimentoNormativo, n.Nome)), NULL),
			Imponibile = SUM(g.Imponibile),
			Iva = CAST(ROUND(SUM(g.Imponibile) * ISNULL(MAX(a.Valore), 0) / 100, 2) AS DECIMAL(18, 2))
		FROM
			(
				SELECT
					i.IdAliquotaIva,
					Imponibile = CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2))
				FROM
					dbo.tblFattureRighe r
					INNER JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				WHERE r.IdFattura = @Id) g
					LEFT JOIN dbo.tblAliquoteIva a ON g.IdAliquotaIva = a.Id
					LEFT JOIN dbo.tblAliquoteIvaNatura n ON a.IdNatura = n.Id
		GROUP BY g.IdAliquotaIva
		ORDER BY MAX(a.Valore) DESC;

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