SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Condizioni commerciali della scheda di un cliente o fornitore, da proporre sulla fattura quando lo
-- si sceglie: pagamento, banca, IBAN, split payment, e aliquota IVA e ritenuta per le righe.
-- Si legge con il permesso sulle fatture (FTT), senza quello sulle anagrafiche (ANC / ANF).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Condizioni
	@IdClienteFornitore CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		-- Scope: schede dell'azienda interna corrente della sessione; nessuna riga se la scheda non c'è
		SELECT
			c.Id,
			c.IdModalita,
			c.IdRata,
			c.IdRataInizio,
			c.IdBancaCassa,
			c.IdAliquotaIva,
			c.IdValuta,
			SplitPayment = ISNULL(c.SplitPayment, 0),
			c.Iban,
			RataGiorniInizio = ISNULL(c.RataGiorniInizio, 0),
			RitenutaAcconto = ISNULL(c.RitenutaAcconto, 0)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @IdClienteFornitore
			AND e.Id = @IdSessione
			AND c.Lock = 0;

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
