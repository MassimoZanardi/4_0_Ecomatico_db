SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati fiscali dell'azienda interna corrente della sessione, per la pagina Fatturazione > Dati fiscali.
-- Restituisce sempre una riga per l'azienda del contesto, anche se i dati fiscali non sono ancora stati
-- salvati (campi vuoti); senza azienda nel contesto nessuna riga.
CREATE OR ALTER PROCEDURE dbo.uspFattureDatiFiscali_get
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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda)
		SELECT
			s.Id,
			s.NomeCompleto,
			s.PartitaIva,
			s.CodiceFiscale,
			d.IdRegimeFiscale,
			d.IdProvinciaRea,
			d.IdRitenutaTipo,
			d.IdRitenutaCausale,
			d.NumeroRea,
			d.CapitaleSociale,
			d.SocioUnico,
			d.StatoLiquidazione
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblSedi s ON e.IdAzienda = s.Id
			LEFT JOIN dbo.tblFattureDatiFiscali d ON s.Id = d.Id
		WHERE e.Id = @IdSessione;

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
