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
				-- irreversibile (punto 6 della specifica, mai passa da Lock = 4/Undo), hard delete completo
				-- della rettifica, stessa sequenza del CASO 3 sotto. L'originale non e' mai stato modificato:
				-- cancellando la rettifica tornano operativi i valori precedenti (quelli scritti dalla rettifica
				-- confermata precedente o i valori propri dell'originale; per un annullamento, la quantita'
				-- piena). Va quindi rifiutata se nel frattempo le relazioni carico/scarico si sono basate sui
				-- valori rettificati e con i valori precedenti una giacenza andrebbe sotto zero. Una rettifica
				-- non applicata a Ecomatico (valori operativi = precedenti) si cancella sempre.
				BEGIN TRANSACTION;

					DECLARE @isAnnullamentoRettifica BIT = (SELECT ISNULL(Annullata, 0)
					FROM dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id);

					-- Relazioni attive dell'originale (controparte non in bozza e non annullata), bloccate fino
					-- alla fine della transazione: nessuna nuova associazione puo' nascere durante il controllo
					DECLARE @relazioni TABLE (Id CHAR(16), IdParent CHAR(16), Quantita DECIMAL(18, 2));
					INSERT @relazioni (Id, IdParent, Quantita)
					SELECT l.Id, l.IdParent, l.Quantita
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l WITH (UPDLOCK, HOLDLOCK)
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON l.Id = v.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON l.IdParent = vp.Id
					WHERE
						(
						l.Id = @idOriginaleRettifica
						OR l.IdParent = @idOriginaleRettifica
						)
						AND l.Quantita > 0
						AND r.Lock < 2
						AND rp.Lock < 2
						AND (v.IsAnnullata = 0 OR l.Id = @idOriginaleRettifica)
						AND (vp.IsAnnullata = 0 OR l.IdParent = @idOriginaleRettifica);

					IF @isAnnullamentoRettifica = 0 AND EXISTS (SELECT 1 FROM @relazioni)
					BEGIN
						-- Correzione: valori operativi senza questa rettifica = quelli scritti dall'ultima altra
						-- rettifica confermata, altrimenti i valori propri dell'originale
						DECLARE @precIdEer CHAR(6), @precIdStatoFisico CHAR(1), @precIdUnitaMisura CHAR(2), @precQuantita DECIMAL(18, 2);

						SELECT
							@precIdEer = IdEer,
							@precIdStatoFisico = IdStatoFisico,
							@precIdUnitaMisura = IdUnitaMisura,
							@precQuantita = Quantita
						FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);

						IF EXISTS (
							SELECT 1
							FROM dbo.viewRifiutiRegistrazioniEffettive
							WHERE
								Id = @idOriginaleRettifica
								AND (
									ISNULL(@precIdEer, '') <> ISNULL(IdEer, '')
									OR ISNULL(@precIdStatoFisico, '') <> ISNULL(IdStatoFisico, '')
									OR ISNULL(@precIdUnitaMisura, '') <> ISNULL(IdUnitaMisura, '')
								)
						)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0) FROM @relazioni WHERE Id = @idOriginaleRettifica)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0) FROM @relazioni WHERE IdParent = @idOriginaleRettifica)
						BEGIN
							ROLLBACK TRANSACTION;
							SET @returnValue = -1;
							SET @returnMessage = 'La registrazione rettificata è stata associata ad altre con i valori corretti: la rettifica non può più essere cancellata';
							GOTO BRANCH_END;
						END
					END

					-- Annullamento di uno scarico: cancellandolo lo scarico torna a consumare i suoi carichi, che
					-- nel frattempo potrebbero essere stati scaricati da altre registrazioni. (Un carico annullato
					-- invece non poteva essere consumato ne' associato: torna disponibile senza problemi.)
					IF @isAnnullamentoRettifica = 1 AND EXISTS (
						SELECT 1
						FROM
							@relazioni l
							INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vc ON l.Id = vc.Id
							INNER JOIN dbo.tblRifiutiRegistrazioni ro ON l.IdParent = ro.Id
						WHERE
							l.IdParent = @idOriginaleRettifica
							AND ro.Operazione = 'S'
							AND vc.Quantita < l.Quantita + (
								SELECT ISNULL(SUM(l2.Quantita), 0)
								FROM
									dbo.tblRifiutiRegistrazioniRelazioni l2
									INNER JOIN dbo.tblRifiutiRegistrazioni rp2 ON l2.IdParent = rp2.Id
									INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp2 ON l2.IdParent = vp2.Id
								WHERE
									l2.Id = l.Id
									AND rp2.Operazione = 'S'
									AND l2.IdParent <> @idOriginaleRettifica
									AND l2.Quantita > 0
									AND rp2.Lock < 2
									AND vp2.IsAnnullata = 0
							)
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'I carichi dello scarico annullato sono stati scaricati da altre registrazioni: l''annullamento non può più essere cancellato';
						GOTO BRANCH_END;
					END

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
					-- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione è NOT NULL (fa parte
					-- della PK composta con IdLotto) - non si può azzerare come il vecchio
					-- tblEoWMovimenti.IdRegistrazione (nullable), va rimossa la riga di collegamento.
					DELETE dbo.tblEoWLottiRifiutiRegistrazioni
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
				-- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione è NOT NULL (fa parte
				-- della PK composta con IdLotto) - non si può azzerare come il vecchio
				-- tblEoWMovimenti.IdRegistrazione (nullable), va rimossa la riga di collegamento.
				DELETE dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @Id;
				-- Bozza di rettifica mai confermata: non ha mai contato nei valori effettivi
				-- (viewRifiutiRegistrazioniEffettive considera solo Lock = 0), basta rimuovere il collegamento.
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
