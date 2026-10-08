SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pagamenti attivi di una rata, dal più vecchio: Quota è la parte del pagamento attribuita alla rata,
-- Importo l'intero pagamento, Rate il numero di rate che il pagamento copre.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_List
	@IdRata CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRata = NULLIF(LTRIM(RTRIM(@IdRata)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRata IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRata non può essere vuoto';
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

		-- Scope: rata di una fattura dell'azienda interna corrente della sessione
		SELECT
			p.Id,
			[Data] = p.DataContabile,
			p.DataRegistrazione,
			BancaCassaNome = b.Nome,
			ModalitaNome = m.Nome,
			p.Causale,
			Quota = CAST(rp.Importo AS DECIMAL(18, 2)),
			Importo = CAST(p.Importo AS DECIMAL(18, 2)),
			Rate = (SELECT COUNT(*) FROM dbo.tblFattureRatePagamenti q WHERE q.IdPagamento = p.Id)
		FROM
			dbo.tblFattureRatePagamenti rp
			INNER JOIN dbo.tblPagamenti p ON rp.IdPagamento = p.Id
			INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblBancheCasse b ON p.IdBancaCassa = b.Id
			LEFT JOIN dbo.tblPagamentiModalita m ON p.IdModalita = m.Id
		WHERE
			rp.IdRata = @IdRata
			AND e.Id = @IdSessione
			AND p.Lock = 0
		ORDER BY
			p.DataContabile,
			p.Id;

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
