SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_List
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

		-- Scope: fattura dell'azienda interna corrente della sessione. Pagato = quote dei pagamenti attivi attribuite
		-- alla rata. Stato: saldata (pagato + abbuono coprono l'importo), scaduta, da pagare
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT
			r.Id,
			StatoValore = CASE
				WHEN x.Pagato + ISNULL(r.Abbuono, 0) >= r.Importo THEN 0
				WHEN r.DataScadenza < @oggi THEN 2
				ELSE 1
			END,
			StatoDescrizione = CASE
				WHEN x.Pagato + ISNULL(r.Abbuono, 0) >= r.Importo THEN 'Saldata'
				WHEN r.DataScadenza < @oggi THEN 'Scaduta'
				ELSE 'Da pagare'
			END,
			r.DataScadenza,
			Importo = CAST(r.Importo AS DECIMAL(18, 2)),
			Abbuono = CAST(ISNULL(r.Abbuono, 0) AS DECIMAL(18, 2)),
			Pagato = CAST(x.Pagato AS DECIMAL(18, 2))
		FROM
			dbo.tblFattureRate r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			CROSS APPLY
				(
					SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
					FROM
						dbo.tblFattureRatePagamenti rp
						INNER JOIN dbo.tblPagamenti p ON rp.IdPagamento = p.Id
					WHERE
						rp.IdRata = r.Id
						AND p.Lock = 0
				) x
		WHERE
			r.IdFattura = @IdFattura
			AND e.Id = @IdSessione
		ORDER BY
			r.DataScadenza,
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
