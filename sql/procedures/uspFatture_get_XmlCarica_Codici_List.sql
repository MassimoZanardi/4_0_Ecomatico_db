SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture fornitori > Carica file XML: codici con cui l'applicazione (FatturaXmlCaricaService) traduce i
-- valori del file negli Id del database. Un solo elenco, distinto da Elenco:
--   A aliquote IVA attive, di sistema o dell'azienda del contesto: Valore = percentuale, Codice = natura
--     (prima quelle di sistema: a parità di percentuale e natura si usa la prima);
--   M modalità di pagamento, T tipi di documento, V valute: l'Id è il codice del tracciato (MP05, TD01, EUR);
--   U unità di misura: Codice = sigla, Nome = descrizione.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_XmlCarica_Codici_List
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

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

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT Elenco, Id, Codice, Nome, Valore
		FROM (
			SELECT
				Elenco = 'A',
				Id = CAST(a.Id AS VARCHAR(16)),
				Codice = CAST(a.IdNatura AS VARCHAR(10)),
				Nome = CAST(a.Nome AS VARCHAR(100)),
				Valore = a.Valore,
				Pos = IIF(a.IdSede IS NULL, 0, 1)
			FROM dbo.tblAliquoteIva a
			WHERE
				(a.IdSede IS NULL OR a.IdSede = @idAzienda)
				AND a.Lock = 0

			UNION ALL

			SELECT 'M', CAST(Id AS VARCHAR(16)), CAST(NULL AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblPagamentiModalita

			UNION ALL

			SELECT 'T', CAST(Id AS VARCHAR(16)), CAST(NULL AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblFattureTipi

			UNION ALL

			SELECT 'V', CAST(Id AS VARCHAR(16)), CAST(NULL AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblPagamentiValute

			UNION ALL

			SELECT 'U', CAST(Id AS VARCHAR(16)), CAST(Codice AS VARCHAR(10)), CAST(Nome AS VARCHAR(100)), CAST(NULL AS DECIMAL(9, 2)), 0
			FROM dbo.tblUnitaMisura
		) t
		ORDER BY Elenco, Pos, Nome, Id;

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
