SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- "Togli la fattura": scollega il documento (registrazione dei rifiuti; DDT e servizi non ancora gestiti) dalla
-- fattura in cui è stato fatturato. La fattura NON viene cancellata né modificata: le sue righe restano come
-- sono. Il documento torna fatturabile, quindi una nuova generazione lo fatturerebbe di nuovo.
-- Cliente indicato e spunta "Non fatturabile" restano; importo e contratto applicati alla generazione vengono
-- azzerati. Serve il permesso di modifica sul documento. Un documento non fatturato non è un errore.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_del_Fattura
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
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
		IF ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle registrazioni e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il documento deve essere accessibile dalla sessione (titolarità sulla sede del registro)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
			WHERE r.Id = @Id
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblFattureDocumenti
			SET
				IdFattura = NULL,
				IdImporto = NULL,
				IdOffertaContratto = NULL
			WHERE Id = @Id;

			-- Nulla da ricordare: né cliente indicato né spunta
			DELETE dbo.tblFattureDocumenti
			WHERE
				Id = @Id
				AND IdClienteFornitore IS NULL
				AND ISNULL(NonFatturabile, 0) = 0;
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
