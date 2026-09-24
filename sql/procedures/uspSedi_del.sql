CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0,
	@InternaEsterna CHAR(1) = NULL,
	@IdTipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @InternaEsterna = NULLIF(LTRIM(RTRIM(@InternaEsterna)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');

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
		IF @InternaEsterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @InternaEsterna non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idFunzione CHAR(3) = IIF(@InternaEsterna = 'I', 'AZI', 'ANS');
		DECLARE @permesso TINYINT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI) — trattata come cancellazione già avvenuta con successo,
			-- non come errore.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''azienda non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			IF @InternaEsterna = 'I'
			BEGIN
				-- Titolarità: Admin dello stesso Dominio della sede, oppure Admin di un Dominio Master.
				-- Il bypass Master è intenzionale (confermato dall'utente): un Master-admin deve poter
				-- cancellare/modificare aziende interne di qualsiasi dominio, non solo del proprio.
				IF NOT EXISTS (
					SELECT 1
					FROM dbo.tblSedi s
					INNER JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
					INNER JOIN dbo.tblUtenti a ON i.IdDominio = a.IdDominio
					INNER JOIN dbo.tblSessioni e ON a.Id = e.IdUtente
					WHERE
						s.Id = @Id
						AND e.Id = @IdSessione
						AND a.IdRuolo = 'AD'
						AND a.Lock = 0
				)
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblSessioni e
					INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
					INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
					WHERE
						e.Id = @IdSessione
						AND ut.IdRuolo = 'AD'
						AND ut.Lock = 0
						AND d.[Master] = 1
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Non si dispone dei diritti necessari';
					GOTO BRANCH_END;
				END

				IF EXISTS (
					SELECT 1
					FROM dbo.tblSediEsterne e
					INNER JOIN dbo.tblSedi s ON e.Id = s.Id
					WHERE
						e.IdSedeInterna = @Id
						AND s.Lock = 0
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Un''azienda che ha sedi associate non può essere cancellata';
					GOTO BRANCH_END;
				END
			END

			IF @InternaEsterna = 'E'
			BEGIN
				IF NOT EXISTS (
					SELECT 1
					FROM dbo.tblSedi s
					INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
					WHERE
						s.Id = @Id
						AND e.Id = @IdSessione
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Una sede condivisa da altre aziende non può essere cancellata';
					GOTO BRANCH_END;
				END
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda (solo sedi interne);
			-- Lotti/Righe hanno IdSede = sede operativa (può essere una sede figlia);
			-- IdSede del DDT è sempre una sede interna (fissata alla creazione)
			IF @InternaEsterna = 'I' AND (
				EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE IdSede = @Id AND Lock = 0)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE IdSede = @Id AND Lock = 0)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id AND Lock = 0)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdSede = @Id)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdSede = @Id)
				OR EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdSede = @Id)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata al modulo Magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- DDT: mittente/destinatario/trasportatore sono campi liberi della testata,
			-- possono essere sedi esterne o interne
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino (mittente/destinatario/trasportatore) non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				-- Per sicurezza: se la sede cancellata era una sede figlia (IdParent valorizzato)
				-- con UnitaLocale=true, il genitore eredita il flag, così il gruppo non resta mai
				-- senza nessuna sede attiva con UnitaLocale=true.
				UPDATE p
				SET p.UnitaLocale = 1
				FROM dbo.tblSedi p
				INNER JOIN dbo.tblSedi s ON s.IdParent = p.Id
				WHERE
					s.Id = @Id
					AND s.UnitaLocale = 1
					AND p.Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblUtentiSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblAreeSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblCalendari
				WHERE IdSede = @Id;
				DELETE dbo.tblEtichette
				WHERE IdSede = @Id;

				-- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE
				-- CASCADE). Ramo di fatto irraggiungibile in pratica (i blocchi sopra su Lock=0
				-- impediscono di arrivare in bozza con dati di magazzino già associati),
				-- mantenuto per difesa dalla FK.
				DELETE rl
				FROM dbo.tblMagazziniMovimentiRigheLotti rl
				INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
				LEFT JOIN dbo.tblMagazziniLotti l ON rl.IdLotto = l.Id
				WHERE r.IdSede = @Id OR l.IdSede = @Id;

				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
				INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
				WHERE re.IdSede = @Id;

				DELETE dbo.tblMagazziniDdt
				WHERE
					IdMittente = @Id
					OR IdDestinatario = @Id
					OR IdTrasportatore = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimentiRighe
				WHERE
					IdSede = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimentiRigheEoW
				WHERE
					IdSede = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimenti
				WHERE IdSede = @Id;

				DELETE dbo.tblMagazziniLotti
				WHERE IdSede = @Id;

				DELETE dbo.tblMagazziniArticoli
				WHERE IdSede = @Id;

				DELETE dbo.tblRifiutiAutorizzazioni
				WHERE IdSede = @Id;
				DELETE dbo.tblRifiutiRegistri
				WHERE IdSede = @Id;
				DELETE dbo.tblTipi
				WHERE IdSede = @Id;
				DELETE dbo.tblSediEsterne
				WHERE IdSedeInterna = @Id;
				DELETE dbo.tblSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblSediEsterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;




