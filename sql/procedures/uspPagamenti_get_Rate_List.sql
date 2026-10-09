SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rate coperte da un pagamento, per il dettaglio del movimento nella prima nota: fattura (Tipo C cliente,
-- F fornitore; Numero = quello che si legge sul documento, per un fornitore il numero del suo documento),
-- cliente o fornitore, scadenza della rata e Quota, la parte del pagamento attribuita alla rata.
-- Scope: pagamento dell'azienda interna corrente della sessione.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_Rate_List
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

		SELECT
			Id = r.Id,
			r.IdFattura,
			f.Tipo,
			Numero = CAST(ISNULL(IIF(f.Tipo = 'F', NULLIF(f.NumeroFornitore, ''), NULL), CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '')) AS VARCHAR(40)),
			f.DataEmissione,
			NotaCredito = CAST(IIF(f.IdTipo = 'TD04', 1, 0) AS BIT),
			s.NomeCompleto,
			r.DataScadenza,
			Quota = CAST(rp.Importo AS DECIMAL(18, 2))
		FROM
			dbo.tblPagamenti p
			INNER JOIN dbo.tblSessioni e ON p.IdSede = e.IdAzienda
			INNER JOIN dbo.tblFattureRatePagamenti rp ON p.Id = rp.IdPagamento
			INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			p.Id = @Id
			AND e.Id = @IdSessione
			AND p.Lock = 0
		ORDER BY
			r.DataScadenza,
			f.DataEmissione,
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
