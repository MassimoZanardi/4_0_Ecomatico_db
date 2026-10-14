SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancellazione di registrazioni dei rifiuti, DDT di magazzino e servizi: tra i documenti @Ids (Id separati da
-- virgola) del modulo @IdModulo (RIF, MAG, SRV), quelli compresi in una fattura o in una pre-fattura non
-- cancellate. La pagina li mostra in una finestra informativa prima di cancellare (regola O7.6 di
-- docs/regole/offerte-contratti.md): la cancellazione resta permessa e la fattura non cambia.
-- Solo i documenti che la sessione vede (ufnFattureDocumenti_get_Documento). Per un DDT Id è l'Id del movimento.
-- Nessuna riga, e nessun errore, se nessuno è fatturato.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Fatturati_List
	@Ids VARCHAR(MAX) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF ISNULL(@IdModulo, '') NOT IN ('RIF', 'MAG', 'SRV')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF, MAG o SRV';
			GOTO BRANCH_END;
		END

		SELECT
			fd.Id,
			Documento = CAST(CASE @IdModulo
				WHEN 'RIF' THEN 'Registrazione' + ISNULL(' n. ' + CAST(r.Numero AS VARCHAR(10)), '') + ISNULL(' del ' + CONVERT(VARCHAR(10), r.[Data], 103), '')
				WHEN 'MAG' THEN 'DDT' + ISNULL(' n. ' + CAST(dd.Numero AS VARCHAR(10)) + ISNULL('/' + dd.Sezionale, ''), '') + ISNULL(' del ' + CONVERT(VARCHAR(10), dd.[Data], 103), '')
				ELSE 'Servizio' + ISNULL(' ' + tp.Nome, '') + ISNULL(' del ' + CONVERT(VARCHAR(10), ev.[Data], 103), '')
			END AS VARCHAR(200)),
			Fattura = CAST(IIF(f.IdTipo = 'TD00', 'Pre-fattura', 'Fattura')
				+ ISNULL(' n. ' + CAST(f.Numero AS VARCHAR(10)) + ISNULL('/' + f.Sezionale, ''), '')
				+ ISNULL(' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103), '') AS VARCHAR(100)),
			IsPreFattura = CAST(IIF(f.IdTipo = 'TD00', 1, 0) AS BIT),
			Cliente = sc.NomeCompleto
		FROM
			(SELECT DISTINCT Id = CAST(LTRIM(RTRIM(value)) AS CHAR(16)) FROM STRING_SPLIT(ISNULL(@Ids, ''), ',') WHERE LTRIM(RTRIM(value)) <> '') k
			INNER JOIN dbo.tblFattureDocumenti fd ON k.Id = fd.Id
			INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
									  AND f.Lock IN (0, 2)
			-- Il documento deve essere accessibile dalla sessione
			CROSS APPLY dbo.ufnFattureDocumenti_get_Documento(fd.Id, @IdModulo, @IdSessione) a
			LEFT JOIN dbo.tblClientiFornitori cf ON f.IdClienteFornitore = cf.Id
			LEFT JOIN dbo.tblSedi sc ON cf.IdSede = sc.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON @IdModulo = 'RIF'
													AND fd.Id = r.Id
			LEFT JOIN dbo.tblMagazziniDdt dd ON @IdModulo = 'MAG'
											 AND fd.Id = dd.IdMovimento
			LEFT JOIN dbo.tblServizi sv ON @IdModulo = 'SRV'
										AND fd.Id = sv.Id
			LEFT JOIN dbo.tblEventi ev ON sv.IdEvento = ev.Id
			LEFT JOIN dbo.tblTipi tp ON sv.IdTipo = tp.Id
		ORDER BY Documento, fd.Id;

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
