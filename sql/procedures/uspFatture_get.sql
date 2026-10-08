SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_get
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

		-- I totali si calcolano dalle righe (ufnFatture_get_Totali), non sono memorizzati
		SELECT
			f.Id,
			f.IdSede,
			f.IdClienteFornitore,
			f.IdTipo,
			f.IdStato,
			f.IdModalita,
			f.IdRata,
			f.IdRataInizio,
			f.IdValuta,
			f.IdBancaCassa,
			f.IdFatturaRiferimento,
			f.Tipo,
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataRegistrazione,
			f.DataEmissione,
			f.Iban,
			RataGiorniInizio = ISNULL(f.RataGiorniInizio, 0),
			f.Ordine,
			f.DataOrdine,
			SplitPayment = ISNULL(f.SplitPayment, 0),
			Bollo = ISNULL(f.Bollo, 0),
			f.CodiceCig,
			f.CodiceCup,
			f.Causale,
			SolaLettura = ISNULL(f.SolaLettura, 0),
			f.Lock,
			NomeCompleto = s.NomeCompleto,
			t.Imponibile,
			t.Iva,
			t.Ritenuta,
			t.Totale,
			t.NettoAPagare
		FROM
			dbo.tblFatture f
			LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
		WHERE f.Id = @Id;

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
