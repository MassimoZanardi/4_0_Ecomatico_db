SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Aggiornamento in blocco dei movimenti portati con successo in conservazione sostitutiva xFIR
-- (Rifiuti/Registrazioni/Index, azione "RENTRI - Conservazione sostitutiva xFIR"): chiamata una sola
-- volta a fine loop lato C# (RentriFormularioService.ConservazioneXfirInviaAsync) con l'elenco degli
-- Id dei movimenti per cui la chiamata all'hub e' andata a buon fine, invece di N round-trip
-- separati - stesso principio di uspRentriRegistrazioni_upd_Sincronizza (unico altro precedente in
-- questo repo per un parametro JSON-array), qui pero' senza cursore perche' e' un semplice elenco di
-- Id, non righe con piu' campi: basta un UPDATE set-based con JOIN su OPENJSON.
-- @Ids: JSON array di Id movimento, es. ["fd73e743a19b44c0","..."]
-- exec dbo.uspRifiutiMovimenti_upd_Conservazione @IdSessione='...', @Ids='["fd73e743a19b44c0"]'
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_upd_Conservazione]
	@IdSessione CHAR(16) = NULL,
	@Ids NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @aggiornati INT = 0;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Ids IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Ids non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		UPDATE m
		SET
			RentriFormularioDataConservazione = GETDATE(),
			RentriFormularioInviiConservazione = ISNULL(m.RentriFormularioInviiConservazione, 0) + 1
		FROM
			dbo.tblRifiutiMovimenti m
			INNER JOIN OPENJSON(@Ids) j ON m.Id = j.[value]
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
		WHERE e.Id = @IdSessione;

		SET @aggiornati = @@ROWCOUNT;

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

	SELECT Aggiornati = @aggiornati;

END
GO
