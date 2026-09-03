SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0,
	@IsMultipla BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id);

		-- Se @Id è una registrazione di rettifica, @idOriginaleRettifica è l'Id della registrazione
		-- rettificata (tblRentriRegistrazioniRettifiche.Id) - NULL per una registrazione normale.
		DECLARE @idOriginaleRettifica CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: registrazione mai esistita o già cancellata (es. doppio invio della
			-- richiesta di annullamento lato UI) — trattata come cancellazione già avvenuta con
			-- successo, non come errore. Salta anche il controllo di titolarità sottostante e
			-- l'intera catena Lock, che non hanno senso su un record inesistente.
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica non ancora inviata al RENTRI è sempre cancellata in modo
		-- irreversibile (mai soft-delete/Undo, vedi sotto) tramite una modale dedicata con conferma
		-- esplicita: la cancellazione multipla (checkbox in elenco) non è ammessa su di essa.
		IF @IsMultipla = 1 AND @idOriginaleRettifica IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND RentriIdentificativo IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica non ancora inviata al RENTRI va cancellata singolarmente';
			GOTO BRANCH_END;
		END

		DECLARE @idMovimento CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @isFormulario BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @conservazioneSostitutiva BIT;

		-- ── CASO 1: registrazione attiva (Lock = 0) → soft delete, o hard delete se è una rettifica ──
		IF @lock = 0
		BEGIN
			SELECT @rentriIdentificativo = RentriIdentificativo, @rentriData = RentriData, @conservazioneSostitutiva = ConservazioneSostitutiva
			FROM dbo.tblRifiutiRegistrazioni
			WHERE Id = @Id;

			-- Una registrazione già trasmessa a RENTRI non può più essere cancellata (vale anche per una rettifica)
			IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			-- Una registrazione bloccata per la conservazione sostitutiva non può più essere cancellata
			IF ISNULL(@conservazioneSostitutiva, 0) = 1
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni a
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.IdParent = r.Id
				WHERE
					a.Id = @Id
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione associata ad altre non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Recupero dati registrazione
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id,
				@operazione = r.Operazione,
				@idOperazione = m.IdOperazione
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
			WHERE r.Id = @Id;

			IF @idOriginaleRettifica IS NOT NULL
			BEGIN
				-- Rettifica confermata (Lock = 0) ma non ancora inviata al RENTRI: cancellazione sempre
				-- irreversibile (punto 6 della specifica, mai passa da Lock = 4/Undo). Ripristina prima
				-- sull'originale i valori precedenti la rettifica (no-op se non erano mai stati modificati,
				-- caso in cui l'originale aveva relazioni carico/scarico attive - punto 4), poi hard delete
				-- completo della rettifica, stessa sequenza del CASO 3 sotto.
				BEGIN TRANSACTION;

					UPDATE mo
					SET
						IdEer = t.IdEer,
						EerDescrizione = t.EerDescrizione,
						IdStatoFisico = t.IdStatoFisico,
						IdUnitaMisura = t.IdUnitaMisura,
						Quantita = t.Quantita
					FROM
						dbo.tblRentriRegistrazioniRettifiche t
						INNER JOIN dbo.tblRifiutiRegistrazioni ro ON t.Id = ro.Id
						INNER JOIN dbo.tblRifiutiMovimenti mo ON ro.IdMovimento = mo.Id
					WHERE
						t.Id = @idOriginaleRettifica
						AND t.IdRettifica = @Id;

					DELETE dbo.tblRifiutiRegistrazioniRelazioni
					WHERE
						Id = @Id
						OR IdParent = @Id;
					DELETE dbo.tblRifiutiMovimentiClassiPericolo
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiProduttori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiDestinatari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiTrasportatori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiIntermediari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiLog
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiRegistrazioniEtichette
					WHERE Id = @Id;
					UPDATE dbo.tblEoWMovimenti
					SET IdRegistrazione = NULL
					WHERE IdRegistrazione = @Id;
					DELETE dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id;
					DELETE dbo.tblRifiutiRegistrazioni
					WHERE Id = @Id;
					DELETE dbo.tblRifiutiFormulari
					WHERE
						IdMovimento = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimenti
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblIdLog
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);
					DELETE dbo.tblId
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);

				COMMIT TRANSACTION;
			END
			ELSE
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblRifiutiRegistrazioni
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Registrazione non trovata o già eliminata';
						GOTO BRANCH_END;
					END

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
		END

		-- ── CASO 2: registrazione non confermata (Lock = 1) ──────────────────
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- ── CASO 3: registrazione in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id
			FROM
				dbo.tblRifiutiRegistrazioni r
				LEFT JOIN dbo.tblRifiutiFormulari f ON r.IdMovimento = f.IdMovimento
			WHERE r.Id = @Id;

			BEGIN TRANSACTION;
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE
					Id = @Id
					OR IdParent = @Id;
				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				-- (stesso gap trovato e corretto in uspRifiutiFormulari_del il 2026-08-21)
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiRegistrazioniEtichette
				WHERE Id = @Id;
				-- Gestione EoW: tblEoWMovimenti.IdRegistrazione (nullable) può referenziare questa
				-- registrazione se l'automatismo sulla causale K l'ha già collegata a un movimento
				-- di magazzino EoW - si azzera il collegamento anziché bloccare la cancellazione,
				-- il movimento resta un record di magazzino valido anche senza la registrazione di
				-- origine (stesso pattern di uspSYS_del_RegistroCascade).
				UPDATE dbo.tblEoWMovimenti
				SET IdRegistrazione = NULL
				WHERE IdRegistrazione = @Id;
				-- Bozza di rettifica mai confermata: nessun valore è mai stato propagato sull'originale
				-- (la propagazione avviene solo in uspRifiutiRegistrazioni_upd_Rettifica al salvataggio),
				-- quindi qui basta rimuovere il collegamento, nessun ripristino necessario.
				DELETE dbo.tblRentriRegistrazioniRettifiche
				WHERE IdRettifica = @Id;
				DELETE dbo.tblRifiutiRegistrazioni
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE
					IdMovimento = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimenti
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
			COMMIT TRANSACTION;
		END

		-- ── CASO 4: Lock in stato non gestito ────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
