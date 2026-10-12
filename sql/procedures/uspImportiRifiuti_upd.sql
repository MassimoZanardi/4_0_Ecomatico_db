SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un importo rifiuti e conferma la bozza (Lock 2 -> 0).
-- Le variabili (EER, produttore, trasportatore, destinatario, intermediario, etichetta) sono facoltative: una
-- variabile non indicata vale "qualsiasi" nel confronto con la registrazione.
-- Produttore: @IdProduttoreParent è il soggetto (tutte le sue sedi), @IdProduttore una sua sede precisa. Indicata
-- la sola sede, il soggetto si ricava dalla sede.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdPriorita INT = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProduttoreParent CHAR(16) = NULL,
	@IdProduttore CHAR(16) = NULL,
	@IdTrasportatore CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
	@IdIntermediario CHAR(16) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @IdEer = NULLIF(NULLIF(LTRIM(RTRIM(@IdEer)), ''), REPLICATE('0', 6));
		SET @IdProduttoreParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdProduttoreParent)), ''), @idSediciZeri);
		SET @IdProduttore = NULLIF(NULLIF(LTRIM(RTRIM(@IdProduttore)), ''), @idSediciZeri);
		SET @IdTrasportatore = NULLIF(NULLIF(LTRIM(RTRIM(@IdTrasportatore)), ''), @idSediciZeri);
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), @idSediciZeri);
		SET @IdIntermediario = NULLIF(NULLIF(LTRIM(RTRIM(@IdIntermediario)), ''), @idSediciZeri);
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), @idSediciZeri);

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
		IF @Nome IS NULL OR LEN(@Nome) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome dell''importo (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END
		IF @IdPriorita IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = @IdPriorita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la priorità';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idProduttoreParentAttuale CHAR(16);
		DECLARE @idProduttoreAttuale CHAR(16);
		DECLARE @idTrasportatoreAttuale CHAR(16);
		DECLARE @idDestinatarioAttuale CHAR(16);
		DECLARE @idIntermediarioAttuale CHAR(16);
		DECLARE @idEtichettaAttuale CHAR(16);
		SELECT
			@idAzienda = i.IdSede,
			@idProduttoreParentAttuale = r.IdProduttoreParent,
			@idProduttoreAttuale = r.IdProduttore,
			@idTrasportatoreAttuale = r.IdTrasportatore,
			@idDestinatarioAttuale = r.IdDestinatario,
			@idIntermediarioAttuale = r.IdIntermediario,
			@idEtichettaAttuale = r.IdEtichetta
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
		WHERE
			i.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Nome unico tra gli importi rifiuti attivi dell'azienda
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			WHERE
				i.Id <> @Id
				AND i.IdSede = @idAzienda
				AND i.Lock = 0
				AND i.Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un importo rifiuti con questo nome';
			GOTO BRANCH_END;
		END

		IF @IdEer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiEer WHERE Id = @IdEer)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice EER indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Sede del produttore: è il soggetto stesso o una sua sede; indicata la sola sede, il soggetto si ricava
		IF @IdProduttore IS NOT NULL
		BEGIN
			DECLARE @idParentDellaSede CHAR(16);
			SELECT @idParentDellaSede = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdProduttore;

			IF @IdProduttoreParent IS NULL
				SET @IdProduttoreParent = @idParentDellaSede;
			ELSE IF ISNULL(@idParentDellaSede, '') <> @IdProduttoreParent
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La sede del produttore non appartiene al produttore indicato';
				GOTO BRANCH_END;
			END
		END

		-- Soggetti e sedi: tra quelli che l'utente vede (propri dell'azienda o condivisi nel dominio tramite
		-- un'area), come nelle select; quelli già sull'importo restano validi
		DECLARE @sedi TABLE (
			Ruolo VARCHAR(50) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAttuale CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);
		INSERT @sedi (Ruolo, Id, IdAttuale)
		VALUES
			('Il produttore indicato', @IdProduttoreParent, @idProduttoreParentAttuale),
			('La sede del produttore indicata', @IdProduttore, @idProduttoreAttuale),
			('Il trasportatore indicato', @IdTrasportatore, @idTrasportatoreAttuale),
			('Il destinatario indicato', @IdDestinatario, @idDestinatarioAttuale),
			('L''intermediario indicato', @IdIntermediario, @idIntermediarioAttuale);

		DECLARE @ruoloNonValido VARCHAR(50);
		SELECT TOP (1) @ruoloNonValido = t.Ruolo
		FROM @sedi t
		WHERE
			t.Id IS NOT NULL
			AND (t.IdAttuale IS NULL OR t.Id <> t.IdAttuale)
			AND NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblSessioni e
					CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
				WHERE
					e.Id = @IdSessione
					AND u.Id = t.Id
					AND
						(
							(
							u.IdDominio = e.IdDominio
							AND u.Condivisa = 1
							)
						OR u.IdAziendaInterna = @idAzienda
						)
			);

		IF @ruoloNonValido IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = @ruoloNonValido + ' non esiste o non è accessibile';
			GOTO BRANCH_END;
		END

		-- Etichetta: del modulo Rifiuti, di una sede dell'azienda; quella già sull'importo resta valida
		IF @IdEtichetta IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.Id = @IdEtichetta
				AND t.IdModulo = 'RIF'
				AND s.IdAziendaInterna = @idAzienda
				AND (t.Lock = 0 OR t.Id = @idEtichettaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''etichetta indicata non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblImporti
			SET
				Lock = 0,
				Nome = @Nome,
				IdPriorita = @IdPriorita
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Importo non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblImportiRifiuti
			SET
				IdEer = @IdEer,
				IdProduttoreParent = @IdProduttoreParent,
				IdProduttore = @IdProduttore,
				IdTrasportatore = @IdTrasportatore,
				IdDestinatario = @IdDestinatario,
				IdIntermediario = @IdIntermediario,
				IdEtichetta = @IdEtichetta
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
