SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un importo dei servizi e conferma la bozza (Lock 2 -> 0).
-- L'importo dei servizi è un listino: le risorse (persone e oggetti) stanno sulle sue righe (uspImportiRighe_upd).
-- Le variabili (tipo di servizio, richiedente, sede interna, etichetta) sono facoltative: una variabile non
-- indicata vale "qualsiasi" nel confronto con il servizio.
-- Tipo: un tipo del modulo Servizi, di sistema o dell'azienda.
-- Richiedente: @IdRichiedenteParent è il soggetto (tutte le sue sedi), @IdRichiedente una sua sede precisa.
-- Indicata la sola sede, il soggetto si ricava dalla sede.
-- Sede interna: una sede interna dell'azienda, quella del calendario che ospita il servizio.
CREATE OR ALTER PROCEDURE dbo.uspImportiServizi_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdPriorita INT = NULL,
	@IdTipo CHAR(16) = NULL,
	@IdRichiedenteParent CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@IdSedeInterna CHAR(16) = NULL,
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
		SET @IdTipo = NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), @idSediciZeri);
		SET @IdRichiedenteParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdRichiedenteParent)), ''), @idSediciZeri);
		SET @IdRichiedente = NULLIF(NULLIF(LTRIM(RTRIM(@IdRichiedente)), ''), @idSediciZeri);
		SET @IdSedeInterna = NULLIF(NULLIF(LTRIM(RTRIM(@IdSedeInterna)), ''), @idSediciZeri);
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

		-- Controlla il permesso sulla funzione e che il modulo Servizi sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idTipoAttuale CHAR(16);
		DECLARE @idRichiedenteParentAttuale CHAR(16);
		DECLARE @idRichiedenteAttuale CHAR(16);
		DECLARE @idSedeInternaAttuale CHAR(16);
		DECLARE @idEtichettaAttuale CHAR(16);
		SELECT
			@idAzienda = i.IdSede,
			@idTipoAttuale = r.IdTipo,
			@idRichiedenteParentAttuale = r.IdRichiedenteParent,
			@idRichiedenteAttuale = r.IdRichiedente,
			@idSedeInternaAttuale = r.IdSedeInterna,
			@idEtichettaAttuale = r.IdEtichetta
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiServizi r ON i.Id = r.Id
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

		-- Nome unico tra gli importi dei servizi attivi dell'azienda
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiServizi r ON i.Id = r.Id
			WHERE
				i.Id <> @Id
				AND i.IdSede = @idAzienda
				AND i.Lock = 0
				AND i.Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un importo dei servizi con questo nome';
			GOTO BRANCH_END;
		END

		-- Tipo di servizio: del modulo Servizi, di sistema o dell'azienda; quello già sull'importo resta valido
		IF @IdTipo IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi t
			WHERE
				t.Id = @IdTipo
				AND t.IdModulo = 'SRV'
				AND (t.IdSede IS NULL OR t.IdSede = @idAzienda)
				AND (t.Lock = 0 OR t.Id = @idTipoAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di servizio indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Sede interna: una sede interna dell'azienda; quella già sull'importo resta valida
		IF @IdSedeInterna IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSedeInterna
				AND s.InternaEsterna = 'I'
				AND s.IdAziendaInterna = @idAzienda
				AND (s.Lock = 0 OR s.Id = @idSedeInternaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede interna indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Sede richiedente: è il soggetto stesso o una sua sede; indicata la sola sede, il soggetto si ricava
		IF @IdRichiedente IS NOT NULL
		BEGIN
			DECLARE @idParentDellaSede CHAR(16);
			SELECT @idParentDellaSede = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdRichiedente;

			IF @IdRichiedenteParent IS NULL
				SET @IdRichiedenteParent = @idParentDellaSede;
			ELSE IF ISNULL(@idParentDellaSede, '') <> @IdRichiedenteParent
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La sede richiedente non appartiene al richiedente indicato';
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
			('Il richiedente indicato', @IdRichiedenteParent, @idRichiedenteParentAttuale),
			('La sede richiedente indicata', @IdRichiedente, @idRichiedenteAttuale);

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

		-- Etichetta: del modulo Servizi, di una sede dell'azienda; quella già sull'importo resta valida
		IF @IdEtichetta IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.Id = @IdEtichetta
				AND t.IdModulo = 'SRV'
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

			UPDATE dbo.tblImportiServizi
			SET
				IdTipo = @IdTipo,
				IdRichiedenteParent = @IdRichiedenteParent,
				IdRichiedente = @IdRichiedente,
				IdSedeInterna = @IdSedeInterna,
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
