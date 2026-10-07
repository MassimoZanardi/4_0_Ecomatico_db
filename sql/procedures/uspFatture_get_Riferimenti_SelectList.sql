SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture a cui può riferirsi una nota di credito: quelle attive e numerate (non pre-fatture né altre
-- note di credito) dello stesso cliente o fornitore, dalla più recente. @IdFattura è la nota di credito
-- in modifica, esclusa dall'elenco.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Riferimenti_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), @idSediciZeri);
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

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

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: fatture dell'azienda interna corrente della sessione
		SELECT TOP 200 Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0,
				DataEmissione = CAST(NULL AS DATE),
				Numero = CAST(NULL AS INT)

			UNION ALL

			SELECT
				f.Id,
				[Text] = CAST('n. ' + ISNULL(f.NumeroFornitore, CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '')) + ' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103) + ' - ' + FORMAT(t.Totale, 'N2', 'it-IT') AS VARCHAR(200)),
				Selected = CAST(IIF(f.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				f.DataEmissione,
				f.Numero
			FROM
				dbo.tblFatture f
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
			WHERE
				e.Id = @IdSessione
				AND f.IdClienteFornitore = @IdClienteFornitore
				AND f.Id <> ISNULL(@IdFattura, @idSediciZeri)
				AND f.IdTipo NOT IN ('TD00', 'TD04')
				AND f.Lock = 0
		) x
		ORDER BY
			Pos,
			DataEmissione DESC,
			Numero DESC;

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
