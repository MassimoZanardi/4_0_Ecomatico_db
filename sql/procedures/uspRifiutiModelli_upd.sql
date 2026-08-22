CREATE PROCEDURE [dbo].[uspRifiutiModelli_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdTipoTrasporto1 CHAR(1) = NULL,
	@IdAdr CHAR(2) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Note VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

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
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione — chiunque avesse permesso RMD≥2 poteva
		-- modificare il modello di un'altra azienda conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro record con lo stesso nome
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiModelli
			WHERE
				Id <> @Id
				AND IdRegistro = @IdRegistro
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro modello con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Aggiorna le classi di pericolo
			DELETE dbo.tblRifiutiModelliClassiPericolo
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiModelliClassiPericolo
				(Id, IdClasse)
			SELECT
				@Id,
				c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Aggiorna le etichette
			DELETE dbo.tblRifiutiModelliEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiModelliEtichette
				(Id, IdEtichetta)
			SELECT TOP 3
				@Id,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			UPDATE dbo.tblRifiutiModelli
			SET
				Nome = @Nome,
				IdEer = @IdEer,
				IdStatoFisico = @IdStatoFisico,
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				IdImballo = @IdImballo,
				IdAdr = @IdAdr,
				IdAutorizzazioneProduttoreDetentore = @IdAutorizzazioneProduttoreDetentore,
				IdAutorizzazioneDestinatario = @IdAutorizzazioneDestinatario,
				IdAutorizzazioneTrasportatore1 = @IdAutorizzazioneTrasportatore1,
				IdAutorizzazioneIntermediario1 = @IdAutorizzazioneIntermediario1,
				IdTipoTrasporto1 = @IdTipoTrasporto1,
				Note = @Note,
				UtenteNote = @UtenteNote,
				Etichette = dbo.ufnRifiutiModelli_get_Etichette(Id),
				Lock = 0
			WHERE Id = @Id;

			-- @@ROWCOUNT mancante in origine — stesso pattern già corretto altrove nel progetto.
			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Modello non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Aggiorna il log per il movimento
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
