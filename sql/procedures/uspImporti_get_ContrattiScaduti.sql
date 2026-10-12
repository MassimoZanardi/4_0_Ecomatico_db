SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi dell'azienda interna corrente della sessione associati a un contratto scaduto (contratto confermato,
-- non un'offerta, con la fine della validità precedente a oggi), contati per modulo dei documenti: riquadro
-- giallo in testa alla procedura automatica di fatturazione (Fatture clienti > Nuovo > Tramite procedura
-- automatica). Quegli importi non si applicano più ai documenti con data successiva alla scadenza.
-- Una riga per ogni modulo attivo sul dominio che ne ha almeno uno; nessuna riga se non ce ne sono, se manca
-- l'azienda nel contesto o se il modulo Offerte e contratti non è attivo.
-- Si legge con il permesso sulle fatture (FTT) o sugli importi (OCI).
CREATE OR ALTER PROCEDURE dbo.uspImporti_get_ContrattiScaduti
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCI',
				@Permesso = @permesso OUTPUT;
		END
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

		-- Moduli dei documenti attivi sul dominio: pre-calcolati FUORI dalla query
		DECLARE @rifAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0);
		DECLARE @magAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0);
		DECLARE @srvAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0);
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT
			Id = t.IdModulo,
			Importi = COUNT(*)
		FROM
			(
				SELECT
					IdModulo = CAST(CASE
						WHEN r.Id IS NOT NULL AND @rifAttivo = 1 THEN 'RIF'
						WHEN m.Id IS NOT NULL AND @magAttivo = 1 THEN 'MAG'
						WHEN v.Id IS NOT NULL AND @srvAttivo = 1 THEN 'SRV'
					END AS CHAR(3))
				FROM
					dbo.tblImporti i
					INNER JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
					LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
					LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
					LEFT JOIN dbo.tblImportiServizi v ON i.Id = v.Id
				WHERE
					i.IdSede = @idAzienda
					AND i.Lock = 0
					AND oc.Lock = 0
					AND oc.Tipo = 'C'
					AND oc.DataFine < @oggi
					AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			) t
		WHERE t.IdModulo IS NOT NULL
		GROUP BY t.IdModulo
		ORDER BY CASE t.IdModulo WHEN 'RIF' THEN 1 WHEN 'MAG' THEN 2 ELSE 3 END
		OPTION (RECOMPILE);

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
