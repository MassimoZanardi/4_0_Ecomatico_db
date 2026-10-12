SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva sul documento (registrazione dei rifiuti; DDT e servizi non ancora gestiti) il cliente a cui fatturarlo
-- e la spunta "Non fatturabile". Si salvano da soli, senza il "Salva" della scheda: valgono anche per una
-- registrazione già inviata al RENTRI, che non si può più modificare, perché non fanno parte del registro.
--   @IdClienteFornitore NULL: nessun cliente indicato (lo decide l'importo applicato).
-- Serve il permesso di modifica sul documento; il documento deve essere confermato e non ancora fatturato.
-- Senza cliente e senza spunta la riga di tblFattureDocumenti viene tolta.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_upd
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@NonFatturabile BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @NonFatturabile = ISNULL(@NonFatturabile, 0);

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

		-- Il documento: accessibile dalla sessione (titolarità sulla sede del registro), di un'operazione
		-- fatturabile, non una rettifica
		DECLARE @idAzienda CHAR(16);
		DECLARE @lock INT;
		DECLARE @idFattura CHAR(16);
		DECLARE @idClienteAttuale CHAR(16);
		SELECT
			@idAzienda = a.IdAzienda,
			@lock = a.Lock,
			@idFattura = a.IdFattura,
			@idClienteAttuale = a.IdClienteIndicato
		FROM
			dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
		WHERE
			a.IsFatturabile = 1
			AND a.IsRettifica = 0;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la registrazione non è fatturabile';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Salvare la registrazione prima di indicare il cliente';
			GOTO BRANCH_END;
		END
		IF @idFattura IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata fatturata: cliente e spunta non si possono più modificare';
			GOTO BRANCH_END;
		END

		-- Cliente: una scheda cliente attiva dell'azienda del documento; quella già indicata resta valida
		IF @IdClienteFornitore IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'C'
				AND (Lock = 0 OR Id = @idClienteAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il cliente indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @IdClienteFornitore IS NULL AND @NonFatturabile = 0
			BEGIN
				-- Nulla da ricordare: la riga resta solo se porta ancora il legame con una fattura cancellata
				DELETE dbo.tblFattureDocumenti
				WHERE
					Id = @Id
					AND IdFattura IS NULL;

				UPDATE dbo.tblFattureDocumenti
				SET
					IdClienteFornitore = NULL,
					NonFatturabile = 0
				WHERE Id = @Id;
			END
			ELSE
			BEGIN
				UPDATE dbo.tblFattureDocumenti WITH (UPDLOCK, HOLDLOCK)
				SET
					IdClienteFornitore = @IdClienteFornitore,
					NonFatturabile = @NonFatturabile
				WHERE Id = @Id;

				IF @@ROWCOUNT = 0
					INSERT dbo.tblFattureDocumenti (Id, IdModulo, IdClienteFornitore, NonFatturabile)
					VALUES (@Id, 'RIF', @IdClienteFornitore, @NonFatturabile);
			END
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
