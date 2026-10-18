SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Layout di stampa (DDT e fatture) dell'azienda interna corrente della sessione, per la pagina Impostazioni >
-- Report layout. Restituisce sempre una riga per l'azienda del contesto, anche se il layout non è ancora stato
-- salvato (valori predefiniti di ufnSediReport_get_Layout); senza azienda nel contesto nessuna riga.
-- Nome, indirizzo, codici e recapiti dell'azienda servono a proporre il testo dell'intestazione.
CREATE OR ALTER PROCEDURE dbo.uspSediReport_get
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
			@IdFunzione = 'AZI',
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
			s.IndirizzoCompleto,
			s.CodiceFiscale,
			s.PartitaIva,
			Telefono = t.Valore,
			Email = m.Valore,
			r.IdLayout,
			r.Intestazione,
			r.PiePagina,
			r.IntestazioneColore,
			r.IntestazioneFontSize,
			r.IntestazioneAllineamento,
			r.PiePaginaColore,
			r.PiePaginaFontSize,
			r.PiePaginaAllineamento,
			r.Logo
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblSedi s ON e.IdAzienda = s.Id
			CROSS APPLY dbo.ufnSediReport_get_Layout(s.Id) r
			LEFT JOIN dbo.tblSediRecapiti t ON s.Id = t.Id AND t.IdRecapito = 'T0'
			LEFT JOIN dbo.tblSediRecapiti m ON s.Id = m.Id AND m.IdRecapito = 'M0'
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
