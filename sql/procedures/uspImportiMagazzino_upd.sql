SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un importo di magazzino e conferma la bozza (Lock 2 -> 0).
-- Le variabili (articolo o materiale, destinatario, etichetta) sono facoltative: una variabile non indicata vale
-- "qualsiasi" nel confronto con le righe del DDT.
-- Articolo e materiale si escludono: l'articolo vale per le righe articolo del DDT, il materiale per le righe EoW.
-- Destinatario: @IdDestinatarioParent è il soggetto (tutte le sue sedi), @IdDestinatario una sua sede precisa.
-- Indicata la sola sede, il soggetto si ricava dalla sede.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdPriorita INT = NULL,
	@IdArticolo CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdDestinatarioParent CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
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
		SET @IdArticolo = NULLIF(NULLIF(LTRIM(RTRIM(@IdArticolo)), ''), @idSediciZeri);
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @IdDestinatarioParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatarioParent)), ''), @idSediciZeri);
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), @idSediciZeri);
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
		IF @IdArticolo IS NOT NULL AND @IdMateriale IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''articolo oppure il materiale EoW, non entrambi';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idArticoloAttuale CHAR(16);
		DECLARE @idDestinatarioParentAttuale CHAR(16);
		DECLARE @idDestinatarioAttuale CHAR(16);
		DECLARE @idEtichettaAttuale CHAR(16);
		SELECT
			@idAzienda = i.IdSede,
			@idArticoloAttuale = r.IdArticolo,
			@idDestinatarioParentAttuale = r.IdDestinatarioParent,
			@idDestinatarioAttuale = r.IdDestinatario,
			@idEtichettaAttuale = r.IdEtichetta
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
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

		-- Nome unico tra gli importi di magazzino attivi dell'azienda
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
			WHERE
				i.Id <> @Id
				AND i.IdSede = @idAzienda
				AND i.Lock = 0
				AND i.Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un importo di magazzino con questo nome';
			GOTO BRANCH_END;
		END

		-- Articolo: dell'azienda; quello già sull'importo resta valido anche se cancellato
		IF @IdArticolo IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli a
			WHERE
				a.Id = @IdArticolo
				AND a.IdSede = @idAzienda
				AND (a.Lock = 0 OR a.Id = @idArticoloAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo indicato non esiste';
			GOTO BRANCH_END;
		END

		IF @IdMateriale IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Sede del destinatario: è il soggetto stesso o una sua sede; indicata la sola sede, il soggetto si ricava
		IF @IdDestinatario IS NOT NULL
		BEGIN
			DECLARE @idParentDellaSede CHAR(16);
			SELECT @idParentDellaSede = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdDestinatario;

			IF @IdDestinatarioParent IS NULL
				SET @IdDestinatarioParent = @idParentDellaSede;
			ELSE IF ISNULL(@idParentDellaSede, '') <> @IdDestinatarioParent
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La sede del destinatario non appartiene al destinatario indicato';
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
			('Il destinatario indicato', @IdDestinatarioParent, @idDestinatarioParentAttuale),
			('La sede del destinatario indicata', @IdDestinatario, @idDestinatarioAttuale);

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

		-- Etichetta: del modulo Magazzino, di una sede dell'azienda; quella già sull'importo resta valida
		IF @IdEtichetta IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.Id = @IdEtichetta
				AND t.IdModulo = 'MAG'
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

			UPDATE dbo.tblImportiMagazzino
			SET
				IdArticolo = @IdArticolo,
				IdMateriale = @IdMateriale,
				IdDestinatarioParent = @IdDestinatarioParent,
				IdDestinatario = @IdDestinatario,
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
