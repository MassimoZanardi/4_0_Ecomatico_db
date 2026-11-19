/*
	Deploy produzione - 2026-11-19 - Diwass > Allegati VII: Registra nel registro; finestra "Da completare" anche per
	l'acquisizione da formulario digitale; stato nella scheda dell'Allegato VII

	Solo 4_0_ecomatico (DB comune a 40-demo e produzione). Nessuna tabella e nessun dato: solo stored procedure, tutte
	CREATE OR ALTER, quindi rieseguibile. Da eseguire da SSMS sul database 4_0_ecomatico (o con sqlcmd -f 65001 -I).
	Prima il DB, poi l'app (commit 4.0 da 302132e in avanti): le SP nuove restituiscono colonne in piÃ¹ che l'app di
	adesso ignora, quindi il DB si puÃ² pubblicare per primo senza fermare nulla.

	1. uspDiwassAllegatiVii_get: StatoNome (il campo Stato della scheda era vuoto dal 22/10) e solo la registrazione
	   attiva collegata.
	2. uspRifiutiRegistrazioni_del: la cancellazione definitiva toglie il collegamento all'Allegato VII.
	3. uspRifiutiAutorizzazioni_get_MatchImportazione: @ConMotivi = 1 restituisce anche le corrispondenze per ruolo
	   (senza il parametro il risultato non cambia: Rentri > Importazione resta com'Ã¨).
	4. uspRifiutiMovimenti_ins_DaAcquisizioneFormulario: restituisce anche gli avvisi dei soggetti non abbinati.
	5-7. Nuove: uspRifiutiMovimenti_ins_DaAllegatoVii, uspDiwassAllegatiVii_get_Registri_SelectList,
	   uspDiwassAllegatiVii_get_Operazioni_SelectList.
	8-9. uspDiwassAllegatiVii_get_List, _get_Esportazione: filtro "Solo quelli senza registrazione" e registrazione
	   collegata.

	In fondo la verifica: le 9 procedure con data di modifica e QUOTED_IDENTIFIER.
*/

-- ===== 1. uspDiwassAllegatiVii_get
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'Allegato VII (i soggetti in uspDiwassAllegatiVii_get_Soggetti). Modificabile: bozza o annunciato su
-- DIWASS (dopo la partenza DIWASS non ammette modifiche)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND a.Lock <= 2
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			a.IdAziendaInterna,
			AziendaNome = s.NomeCompleto,
			-- Solo una registrazione attiva: una cancellata (Lock 4) o una bozza non si mostrano
			IdRegistrazione = r.Id,
			RegistrazioneNumero = r.Numero,
			RegistrazioneData = r.Data,
			a.Numero,
			a.Stato,
			StatoDescrizione = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			-- La scheda (DiwassAllegatoVii.StatoNome) legge lo stato con questo nome, come l'elenco
			StatoNome = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			-- Un documento ricevuto da DIWASS (organizzato da altri o fuori da Ecomatico) è in sola lettura
			Modificabile = CAST(IIF(ISNULL(a.Ricevuto, 0) = 0 AND (a.Stato IS NULL OR a.Stato = 'ANNOUNCED'), 1, 0) AS BIT),
			Ricevuto = CAST(ISNULL(a.Ricevuto, 0) AS BIT),
			a.Ruoli,
			RuoliNome = dbo.ufnDiwassAllegatiVii_get_RuoliDescrizione(a.Ruoli),
			a.DataLettura,
			a.DaInviare,
			a.DataInvio,
			a.DataStato,
			a.TipoDestinazione,
			a.DataSpedizione,
			a.Quantita,
			a.UnitaQuantita,
			a.Contenitore,
			a.LuogoPartenza,
			a.ResponsabileNome,
			a.ResponsabileTelefono,
			a.ResponsabileEmail,
			a.IdEer,
			EerNome = e.Nome,
			a.Descrizione,
			a.CodiceDoganale,
			a.IdNazioneSpedizione,
			a.IdNazioneDestinazione,
			a.IdNazioneTransito1,
			a.IdNazioneTransito2,
			a.IdAttivita,
			Codice = IIF(a.Codice IS NULL, NULL, a.ListaCodice + '|' + a.Codice),
			a.FirmaNome,
			a.FirmaRuolo,
			a.FirmaEmail,
			a.FirmaData,
			a.ProduttoreFirmaNome,
			a.ProduttoreFirmaRuolo,
			a.ProduttoreFirmaData,
			a.Note,
			a.Lock
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSedi s ON a.IdAziendaInterna = s.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON a.IdRegistrazione = r.Id AND r.Lock < 2
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
		WHERE a.Id = @Id;

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

-- ===== 2. uspRifiutiRegistrazioni_del
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
						AND IdRettifica = @Id
					);

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
						AND
							(
							v.IsAnnullata = 0
							OR l.Id = @idOriginaleRettifica
							)
						AND
							(
							vp.IsAnnullata = 0
							OR l.IdParent = @idOriginaleRettifica
							);

					IF @isAnnullamentoRettifica = 0 AND EXISTS (SELECT 1
					FROM @relazioni)
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
								AND
									(
									ISNULL(@precIdEer, '') <> ISNULL(IdEer, '')
									OR ISNULL(@precIdStatoFisico, '') <> ISNULL(IdStatoFisico, '')
									OR ISNULL(@precIdUnitaMisura, '') <> ISNULL(IdUnitaMisura, '')
									)
						)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0)
						FROM @relazioni
						WHERE Id = @idOriginaleRettifica)
						OR ISNULL(@precQuantita, 0) < (SELECT ISNULL(SUM(Quantita), 0)
						FROM @relazioni
						WHERE IdParent = @idOriginaleRettifica)
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
							AND vc.Quantita < l.Quantita + ( SELECT ISNULL(SUM(l2.Quantita), 0) FROM dbo.tblRifiutiRegistrazioniRelazioni l2 INNER JOIN dbo.tblRifiutiRegistrazioni rp2 ON l2.IdParent = rp2.Id INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp2 ON l2.IdParent = vp2.Id WHERE l2.Id = l.Id AND rp2.Operazione = 'S' AND l2.IdParent <> @idOriginaleRettifica AND l2.Quantita > 0 AND rp2.Lock < 2 AND vp2.IsAnnullata = 0 )
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
					-- Indirizzi di intervento del formulario unico (art. 230, comma 5): restano con il formulario
					DELETE dbo.tblRifiutiMovimentiSediProduzione
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
					-- Allegato VII collegato (nato dalla registrazione o che l'ha creata, docs/regole/diwass.md D5.3 e
					-- D8.6): l'Allegato VII resta e perde la registrazione
					UPDATE dbo.tblDiwassAllegatiVii
					SET IdRegistrazione = NULL
					WHERE IdRegistrazione = @Id;
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

					-- Magazzino EoW allineato al registro operativo: senza questa rettifica l'originale torna ai
					-- valori operativi precedenti; se sono piu' bassi (la correzione cancellata aveva aumentato
					-- una M) le sue allocazioni sui lotti si riducono
					EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginaleRettifica;

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
				-- Indirizzi di intervento del formulario unico (art. 230, comma 5): restano con il formulario
				DELETE dbo.tblRifiutiMovimentiSediProduzione
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
				-- Bozza creata da un Allegato VII (Diwass > Allegati VII, Registra nel registro, docs/regole/diwass.md
				-- D8.6): l'Allegato VII resta e perde la registrazione
				UPDATE dbo.tblDiwassAllegatiVii
				SET IdRegistrazione = NULL
				WHERE IdRegistrazione = @Id;
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

-- ===== 3. uspRifiutiAutorizzazioni_get_MatchImportazione
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Risolve, per ciascun ruolo (Produttore/Destinatario/Trasportatore/Intermediario1/Intermediario2), l'
-- IdAutorizzazione da passare a uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd durante l'importazione
-- di un formulario digitale RENTRI (Rifiuti/Registrazioni e Rifiuti/Formulari, "Acquisisci da formulario
-- digitale"). Nessun controllo bloccante sul match: se non si trova una corrispondenza univoca il relativo
-- Id resta NULL e l'utente completa a mano da Edit (stesso comportamento della SP legacy 3.1
-- uspRifiutiSchede_ins_ImportazioneFormularioDigitale).
--
-- Cascata per ruolo (P/D/T/I), ristretta alle sedi visibili all'azienda interna del registro (stesso
-- calcolo di uspRifiutiAutorizzazioni_get_SelectList):
--   1. Autorizzazione con Numero + CodiceFiscale sede coincidenti
--   2. Solo CodiceFiscale sede, accettato solo se il match è univoco (esattamente 1 riga)
--   3. Solo per il Produttore: nessuna autorizzazione trovata ma esiste una Sede con quel CF tra le
--      visibili, senza un'autorizzazione Nessuna=1 che la blocchi → usa l'Id della Sede stessa
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get_MatchImportazione]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@ProduttoreCodiceFiscale VARCHAR(20) = NULL,
	@ProduttoreAutorizzazione VARCHAR(20) = NULL,
	@DestinatarioCodiceFiscale VARCHAR(20) = NULL,
	@DestinatarioAutorizzazione VARCHAR(20) = NULL,
	@TrasportatoreCodiceFiscale VARCHAR(20) = NULL,
	@TrasportatoreAutorizzazione VARCHAR(20) = NULL,
	@IntermediarioCodiceFiscale VARCHAR(20) = NULL,
	@IntermediarioAutorizzazione VARCHAR(20) = NULL,
	@Intermediario2CodiceFiscale VARCHAR(20) = NULL,
	@Intermediario2Autorizzazione VARCHAR(20) = NULL,
	-- 1 = anche il numero di corrispondenze per ogni ruolo non abbinato (acquisizione da formulario digitale); 0 = solo
	-- gli Id, come lo legge uspRentriImportazioni_upd_Analisi
	@ConMotivi BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @ProduttoreCodiceFiscale = NULLIF(LTRIM(RTRIM(@ProduttoreCodiceFiscale)), '');
		SET @ProduttoreAutorizzazione = NULLIF(LTRIM(RTRIM(@ProduttoreAutorizzazione)), '');
		SET @DestinatarioCodiceFiscale = NULLIF(LTRIM(RTRIM(@DestinatarioCodiceFiscale)), '');
		SET @DestinatarioAutorizzazione = NULLIF(LTRIM(RTRIM(@DestinatarioAutorizzazione)), '');
		SET @TrasportatoreCodiceFiscale = NULLIF(LTRIM(RTRIM(@TrasportatoreCodiceFiscale)), '');
		SET @TrasportatoreAutorizzazione = NULLIF(LTRIM(RTRIM(@TrasportatoreAutorizzazione)), '');
		SET @IntermediarioCodiceFiscale = NULLIF(LTRIM(RTRIM(@IntermediarioCodiceFiscale)), '');
		SET @IntermediarioAutorizzazione = NULLIF(LTRIM(RTRIM(@IntermediarioAutorizzazione)), '');
		SET @Intermediario2CodiceFiscale = NULLIF(LTRIM(RTRIM(@Intermediario2CodiceFiscale)), '');
		SET @Intermediario2Autorizzazione = NULLIF(LTRIM(RTRIM(@Intermediario2Autorizzazione)), '');

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

		DECLARE @idAziendaInterna CHAR(16), @idUtente CHAR(16);
		SELECT
			@idAziendaInterna = s.IdAziendaInterna,
			@idUtente = e.IdUtente
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblRifiutiRegistri r ON e.Id = @IdSessione AND r.Id = @IdRegistro
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id;

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Sedi visibili all'utente (interne dell'azienda + condivise) - stesso calcolo di
		-- uspRifiutiAutorizzazioni_get_SelectList, evita di richiamare la function per ogni ruolo
		SELECT
			Id, IdAziendaInterna, Condivisa, Disabilitata
		INTO #sediUtente
		FROM dbo.ufnSedi_get_SediByUtente_List(@idUtente);

		CREATE UNIQUE CLUSTERED INDEX IX_sediUtente_Id ON #sediUtente (Id);

		DECLARE
			@idAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
			@idAutorizzazioneDestinatario CHAR(16) = NULL,
			@idAutorizzazioneTrasportatore1 CHAR(16) = NULL,
			@idAutorizzazioneIntermediario1 CHAR(16) = NULL,
			@idAutorizzazioneIntermediario2 CHAR(16) = NULL,
			@cnt INT,
			@nProduttore INT = NULL,
			@nDestinatario INT = NULL,
			@nTrasportatore INT = NULL,
			@nIntermediario1 INT = NULL,
			@nIntermediario2 INT = NULL;

		-- ── PRODUTTORE ───────────────────────────────────────────────────────────
		IF @ProduttoreCodiceFiscale IS NOT NULL
		BEGIN
			IF @ProduttoreAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneProduttoreDetentore = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'P' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @ProduttoreCodiceFiscale
					AND a.Numero = @ProduttoreAutorizzazione;

			IF @idAutorizzazioneProduttoreDetentore IS NULL
			BEGIN
				SELECT @idAutorizzazioneProduttoreDetentore = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'P' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @ProduttoreCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneProduttoreDetentore = NULL;
				SET @nProduttore = @cnt;
			END

			IF @idAutorizzazioneProduttoreDetentore IS NULL
			BEGIN
				SELECT @idAutorizzazioneProduttoreDetentore = MIN(s.Id), @cnt = COUNT(*)
				FROM
					dbo.tblSedi s
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @ProduttoreCodiceFiscale
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRifiutiAutorizzazioni na
						WHERE na.IdSede = s.Id AND na.IdRuolo = 'P' AND na.Nessuna = 1 AND na.Lock = 0
					);
				IF @cnt <> 1 SET @idAutorizzazioneProduttoreDetentore = NULL;
				-- Più autorizzazioni da produttore contano più delle sedi: è quella la scelta da fare
				IF ISNULL(@nProduttore, 0) <= 1 SET @nProduttore = @cnt;
			END
		END

		-- ── DESTINATARIO ─────────────────────────────────────────────────────────
		IF @DestinatarioCodiceFiscale IS NOT NULL
		BEGIN
			IF @DestinatarioAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneDestinatario = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'D' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @DestinatarioCodiceFiscale
					AND a.Numero = @DestinatarioAutorizzazione;

			IF @idAutorizzazioneDestinatario IS NULL
			BEGIN
				SELECT @idAutorizzazioneDestinatario = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'D' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @DestinatarioCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneDestinatario = NULL;
				SET @nDestinatario = @cnt;
			END
		END

		-- ── TRASPORTATORE (Pos 0) ────────────────────────────────────────────────
		IF @TrasportatoreCodiceFiscale IS NOT NULL
		BEGIN
			IF @TrasportatoreAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneTrasportatore1 = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'T' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @TrasportatoreCodiceFiscale
					AND a.Numero = @TrasportatoreAutorizzazione;

			IF @idAutorizzazioneTrasportatore1 IS NULL
			BEGIN
				SELECT @idAutorizzazioneTrasportatore1 = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'T' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @TrasportatoreCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneTrasportatore1 = NULL;
				SET @nTrasportatore = @cnt;
			END
		END

		-- ── INTERMEDIARIO 1 ──────────────────────────────────────────────────────
		IF @IntermediarioCodiceFiscale IS NOT NULL
		BEGIN
			IF @IntermediarioAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneIntermediario1 = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @IntermediarioCodiceFiscale
					AND a.Numero = @IntermediarioAutorizzazione;

			IF @idAutorizzazioneIntermediario1 IS NULL
			BEGIN
				SELECT @idAutorizzazioneIntermediario1 = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @IntermediarioCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneIntermediario1 = NULL;
				SET @nIntermediario1 = @cnt;
			END
		END

		-- ── INTERMEDIARIO 2 ──────────────────────────────────────────────────────
		IF @Intermediario2CodiceFiscale IS NOT NULL
		BEGIN
			IF @Intermediario2Autorizzazione IS NOT NULL
				SELECT @idAutorizzazioneIntermediario2 = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @Intermediario2CodiceFiscale
					AND a.Numero = @Intermediario2Autorizzazione;

			IF @idAutorizzazioneIntermediario2 IS NULL
			BEGIN
				SELECT @idAutorizzazioneIntermediario2 = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @Intermediario2CodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneIntermediario2 = NULL;
				SET @nIntermediario2 = @cnt;
			END
		END

		IF @ConMotivi = 1
			-- Per ogni ruolo indicato nel formulario e non abbinato, quante corrispondenze ci sono (0 = nessuna, più
			-- di una = da scegliere): servono all'avviso "Da completare" dell'acquisizione da formulario digitale
			SELECT
				IdAutorizzazioneProduttoreDetentore = @idAutorizzazioneProduttoreDetentore,
				IdAutorizzazioneDestinatario = @idAutorizzazioneDestinatario,
				IdAutorizzazioneTrasportatore1 = @idAutorizzazioneTrasportatore1,
				IdAutorizzazioneIntermediario1 = @idAutorizzazioneIntermediario1,
				IdAutorizzazioneIntermediario2 = @idAutorizzazioneIntermediario2,
				CorrispondenzeProduttore = IIF(@ProduttoreCodiceFiscale IS NOT NULL AND @idAutorizzazioneProduttoreDetentore IS NULL, ISNULL(@nProduttore, 0), NULL),
				CorrispondenzeDestinatario = IIF(@DestinatarioCodiceFiscale IS NOT NULL AND @idAutorizzazioneDestinatario IS NULL, ISNULL(@nDestinatario, 0), NULL),
				CorrispondenzeTrasportatore = IIF(@TrasportatoreCodiceFiscale IS NOT NULL AND @idAutorizzazioneTrasportatore1 IS NULL, ISNULL(@nTrasportatore, 0), NULL),
				CorrispondenzeIntermediario1 = IIF(@IntermediarioCodiceFiscale IS NOT NULL AND @idAutorizzazioneIntermediario1 IS NULL, ISNULL(@nIntermediario1, 0), NULL),
				CorrispondenzeIntermediario2 = IIF(@Intermediario2CodiceFiscale IS NOT NULL AND @idAutorizzazioneIntermediario2 IS NULL, ISNULL(@nIntermediario2, 0), NULL);
		ELSE
			SELECT
				IdAutorizzazioneProduttoreDetentore = @idAutorizzazioneProduttoreDetentore,
				IdAutorizzazioneDestinatario = @idAutorizzazioneDestinatario,
				IdAutorizzazioneTrasportatore1 = @idAutorizzazioneTrasportatore1,
				IdAutorizzazioneIntermediario1 = @idAutorizzazioneIntermediario1,
				IdAutorizzazioneIntermediario2 = @idAutorizzazioneIntermediario2;

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

-- ===== 4. uspRifiutiMovimenti_ins_DaAcquisizioneFormulario
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Crea, in un'unica transazione, la bozza (Lock=2) di una Registrazione o di un Formulario a partire dai
-- dati di un formulario digitale RENTRI ("RENTRI - Acquisisci da formulario digitale", Rifiuti/Registrazioni
-- e Rifiuti/Formulari) - stesso ruolo della SP legacy 3.1 uspRifiutiSchede_ins_ImportazioneFormularioDigitale,
-- riscritta sullo schema 4.0. @ModalitaRitorno ('R'/'F') decide quale sola entità creare (mai entrambe:
-- in 4.0 Registrazioni e Formulari sono percorsi di creazione separati, a differenza della legacy).
--
-- Risoluzione FK/lookup interamente qui dentro, riusando le SP già esistenti invece di duplicarne la
-- logica: uspRifiutiAutorizzazioni_get_MatchImportazione (Produttore/Destinatario/Trasportatore/
-- Intermediario per Codice Fiscale) e uspRifiutiRegistrazioni_get_MatchCodiciImportazione (stato
-- fisico/attività R-D/esito/causale respingimento/analisi/ADR/unità di misura). Nessun match trovato -> il
-- relativo campo resta NULL, l'utente completa a mano da Edit; i soggetti non abbinati (nessuna o più
-- corrispondenze) tornano con l'Id in Avvisi (JSON) per la finestra "Da completare" della scheda.
--
-- La bozza risultante (Lock=2) segue esattamente lo stesso ciclo di vita di "Nuova registrazione"/"Nuovo
-- formulario": se l'utente preme Annulla in Edit, uspRifiutiRegistrazioni_del/uspRifiutiFormulari_del la
-- cancellano (hard delete, verificato che coprano tutte le tabelle popolate qui); se preme Salva, il
-- normale uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd la finalizza con tutte le sue validazioni.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_ins_DaAcquisizioneFormulario]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@ModalitaRitorno CHAR(1) = NULL, -- 'R' Registrazione, 'F' Formulario

	@Numero VARCHAR(20) = NULL,
	@Stato VARCHAR(40) = NULL,
	@DataEmissione DATE = NULL,
	@Esito VARCHAR(5) = NULL,
	@EsitoCausaleRespingimento VARCHAR(5) = NULL,
	@RespingimentoMotivo VARCHAR(500) = NULL,
	@DataOraFineTrasporto DATETIME2(0) = NULL,
	@Eer CHAR(6) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@StatoFisico VARCHAR(5) = NULL,
	@ClassiPericolo VARCHAR(200) = NULL,
	@Provenienza CHAR(1) = NULL,
	@Quantita DECIMAL(18, 3) = NULL,
	@QuantitaDestino DECIMAL(18, 3) = NULL,
	@UnitaMisura VARCHAR(5) = NULL,
	@Note VARCHAR(500) = NULL,

	@ProduttoreAutorizzazione VARCHAR(20) = NULL,
	@ProduttoreCodiceFiscale VARCHAR(20) = NULL,
	@DestinatarioAutorizzazione VARCHAR(20) = NULL,
	@DestinatarioCodiceFiscale VARCHAR(20) = NULL,
	@TrasportatoreAutorizzazioneAlbo VARCHAR(20) = NULL,
	@TrasportatoreCodiceFiscale VARCHAR(20) = NULL,
	@IntermediarioAutorizzazioneAlbo VARCHAR(20) = NULL,
	@IntermediarioCodiceFiscale VARCHAR(20) = NULL,
	@Intermediario2AutorizzazioneAlbo VARCHAR(20) = NULL,
	@Intermediario2CodiceFiscale VARCHAR(20) = NULL,

	@Destinazione VARCHAR(5) = NULL,
	@DataOraInizioTrasporto VARCHAR(20) = NULL, -- "yyyy-MM-dd HH:mm", come restituito dall'hub
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@TargaMotrice VARCHAR(10) = NULL,
	@TargaRimorchio VARCHAR(10) = NULL,
	@Percorso VARCHAR(200) = NULL,
	@Colli VARCHAR(50) = NULL,
	@NumeroONU VARCHAR(20) = NULL,
	@ClasseADR VARCHAR(5) = NULL,
	@AdrNote VARCHAR(200) = NULL,
	@Analisi VARCHAR(20) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData VARCHAR(20) = NULL,
	@QuantitaVerificataPartenza BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @returnId CHAR(16) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @ModalitaRitorno = NULLIF(LTRIM(RTRIM(@ModalitaRitorno)), '');
		SET @Numero = NULLIF(UPPER(LTRIM(RTRIM(@Numero))), '');
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @EerDescrizione = NULLIF(LTRIM(RTRIM(@EerDescrizione)), '');
		SET @ClassiPericolo = NULLIF(LTRIM(RTRIM(@ClassiPericolo)), '');
		SET @Note = NULLIF(LTRIM(RTRIM(@Note)), '');
		SET @RespingimentoMotivo = NULLIF(LTRIM(RTRIM(@RespingimentoMotivo)), '');
		SET @ConducenteNome = NULLIF(LTRIM(RTRIM(@ConducenteNome)), '');
		SET @ConducenteCognome = NULLIF(LTRIM(RTRIM(@ConducenteCognome)), '');
		SET @TargaMotrice = NULLIF(LTRIM(RTRIM(@TargaMotrice)), '');
		SET @TargaRimorchio = NULLIF(LTRIM(RTRIM(@TargaRimorchio)), '');
		SET @Percorso = NULLIF(LTRIM(RTRIM(@Percorso)), '');
		SET @NumeroONU = NULLIF(LTRIM(RTRIM(@NumeroONU)), '');
		SET @AdrNote = NULLIF(LTRIM(RTRIM(@AdrNote)), '');
		SET @AnalisiNumero = NULLIF(LTRIM(RTRIM(@AnalisiNumero)), '');

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
		IF @ModalitaRitorno NOT IN ('R', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @ModalitaRitorno deve essere ''R'' o ''F''';
			GOTO BRANCH_END;
		END
		IF @Numero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Numero formulario non valorizzato';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		DECLARE @idFunzionePermesso CHAR(3) = IIF(@ModalitaRitorno = 'F', 'RFR', 'RRG');
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzionePermesso,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE
			@operazione CHAR(1), @isProduttore BIT, @isTrasportatore BIT, @isDestinatario BIT,
			@isIntermediario BIT, @isEsito BIT, @isAttivitaRs BIT, @isIntegrazioneFir BIT, @isFormulario BIT,
			@isFormularioUnico BIT;
		SELECT
			@operazione = Operazione, @isProduttore = IsProduttore, @isTrasportatore = IsTrasportatore,
			@isDestinatario = IsDestinatario, @isIntermediario = IsIntermediario, @isEsito = IsEsito,
			@isAttivitaRs = IsAttivitaRs, @isIntegrazioneFir = IsIntegrazioneFir, @isFormulario = IsFormulario,
			@isFormularioUnico = ISNULL(IsFormularioUnico, 0)
		FROM dbo.tblRifiutiOperazioni
		WHERE Id = @IdOperazione;

		IF @operazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Causale non valida';
			GOTO BRANCH_END;
		END
		-- Il formulario unico degli spurghisti (art. 230, comma 5) si vidima su Vi.Vi.FIR: un FIR del RENTRI non lo diventa
		IF (@ModalitaRitorno = 'R' AND ISNULL(@isIntegrazioneFir, 0) = 0) OR (@ModalitaRitorno = 'F' AND ISNULL(@isFormulario, 0) = 0)
			OR @isFormularioUnico = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è valida per l''acquisizione da formulario digitale';
			GOTO BRANCH_END;
		END

		-- Duplicato: stesso numero di formulario già presente e attivo nel registro, scopato alla sola
		-- entità della modalità corrente (Registrazioni e Formulari sono percorsi di acquisizione
		-- indipendenti: lo stesso FIR può esistere come Registrazione e, separatamente, come Formulario)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiMovimenti m
			WHERE
				m.IdRegistro = @IdRegistro
				AND m.FormularioNumero = @Numero
				AND
					(
						(
						@ModalitaRitorno = 'R'
						AND EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.IdMovimento = m.Id AND r.Lock < 2)
						)
					OR
						(
						@ModalitaRitorno = 'F'
						AND EXISTS (SELECT 1 FROM dbo.tblRifiutiFormulari f WHERE f.IdMovimento = m.Id AND f.Lock < 2)
						)
					)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra registrazione o formulario con lo stesso numero di formulario è già presente in questo registro';
			GOTO BRANCH_END;
		END

		-- ── Risoluzione FK/lookup, riusando le SP dedicate già esistenti ─────────────────────
		CREATE TABLE #match (
			IdAutorizzazioneProduttoreDetentore CHAR(16) NULL,
			IdAutorizzazioneDestinatario CHAR(16) NULL,
			IdAutorizzazioneTrasportatore1 CHAR(16) NULL,
			IdAutorizzazioneIntermediario1 CHAR(16) NULL,
			IdAutorizzazioneIntermediario2 CHAR(16) NULL,
			CorrispondenzeProduttore INT NULL,
			CorrispondenzeDestinatario INT NULL,
			CorrispondenzeTrasportatore INT NULL,
			CorrispondenzeIntermediario1 INT NULL,
			CorrispondenzeIntermediario2 INT NULL
		);
		INSERT #match
		EXEC dbo.uspRifiutiAutorizzazioni_get_MatchImportazione
			@ConMotivi = 1,
			@IdSessione = @IdSessione, @IdRegistro = @IdRegistro,
			@ProduttoreCodiceFiscale = @ProduttoreCodiceFiscale, @ProduttoreAutorizzazione = @ProduttoreAutorizzazione,
			@DestinatarioCodiceFiscale = @DestinatarioCodiceFiscale, @DestinatarioAutorizzazione = @DestinatarioAutorizzazione,
			@TrasportatoreCodiceFiscale = @TrasportatoreCodiceFiscale, @TrasportatoreAutorizzazione = @TrasportatoreAutorizzazioneAlbo,
			@IntermediarioCodiceFiscale = @IntermediarioCodiceFiscale, @IntermediarioAutorizzazione = @IntermediarioAutorizzazioneAlbo,
			@Intermediario2CodiceFiscale = @Intermediario2CodiceFiscale, @Intermediario2Autorizzazione = @Intermediario2AutorizzazioneAlbo;

		CREATE TABLE #codici (
			IdStatoFisico CHAR(1) NULL,
			IdAttivitaRs CHAR(2) NULL,
			IdAnalisiTipo CHAR(1) NULL,
			IdAdr CHAR(2) NULL,
			IdUnitaMisura CHAR(2) NULL,
			IdEsito CHAR(1) NULL,
			IdCausaleRespingimento CHAR(1) NULL
		);
		INSERT #codici
		EXEC dbo.uspRifiutiRegistrazioni_get_MatchCodiciImportazione
			@StatoFisicoCodice = @StatoFisico, @AttivitaRsCodice = @Destinazione, @AnalisiTipoCodice = @Analisi,
			@AdrCodice = @ClasseADR, @UnitaMisuraCodice = @UnitaMisura, @EsitoCodice = @Esito,
			@CausaleRespingimentoCodice = @EsitoCausaleRespingimento;

		DECLARE
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idAnalisiTipo CHAR(1), @idAdr CHAR(2), @idUnitaMisura CHAR(2),
			@idEsito CHAR(1), @idCausaleRespingimento CHAR(1);
		SELECT TOP 1
			@idAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore,
			@idAutorizzazioneDestinatario = IdAutorizzazioneDestinatario,
			@idAutorizzazioneTrasportatore1 = IdAutorizzazioneTrasportatore1,
			@idAutorizzazioneIntermediario1 = IdAutorizzazioneIntermediario1,
			@idAutorizzazioneIntermediario2 = IdAutorizzazioneIntermediario2
		FROM #match;
		SELECT TOP 1
			@idStatoFisico = IdStatoFisico, @idAttivitaRs = IdAttivitaRs, @idAnalisiTipo = IdAnalisiTipo,
			@idAdr = IdAdr, @idUnitaMisura = IdUnitaMisura, @idEsito = IdEsito, @idCausaleRespingimento = IdCausaleRespingimento
		FROM #codici;

		-- Autorizzazioni non applicabili al ruolo dell'operazione: azzerate, stesso principio di
		-- uspRifiutiRegistrazioni_upd (righe "IF @isProduttore = 0 ... SET NULL")
		IF ISNULL(@isProduttore, 0) = 0 SET @idAutorizzazioneProduttoreDetentore = NULL;
		IF ISNULL(@isDestinatario, 0) = 0 SET @idAutorizzazioneDestinatario = NULL;
		IF ISNULL(@isTrasportatore, 0) = 0 SET @idAutorizzazioneTrasportatore1 = NULL;
		IF ISNULL(@isIntermediario, 0) = 0
		BEGIN
			SET @idAutorizzazioneIntermediario1 = NULL;
			SET @idAutorizzazioneIntermediario2 = NULL;
		END
		IF ISNULL(@isEsito, 0) = 0
		BEGIN
			SET @idEsito = NULL;
			SET @idCausaleRespingimento = NULL;
			SET @RespingimentoMotivo = NULL;
		END
		IF ISNULL(@isAttivitaRs, 0) = 0 SET @idAttivitaRs = NULL;

		-- Soggetti del formulario non abbinati (nessuna o più corrispondenze in anagrafica): restano vuoti e l'elenco
		-- va nella finestra "Da completare" della scheda, solo per i ruoli che la causale prevede: ruolo (in grassetto
		-- nella finestra) e testo "codice fiscale e autorizzazione – motivo"
		DECLARE @mancanti TABLE (Pos INT, Ruolo NVARCHAR(60), Testo NVARCHAR(400), Mancante BIT);
		-- Mancante = 1: soggetto da inserire in anagrafica; 0: più corrispondenze, solo da scegliere
		INSERT INTO @mancanti (Pos, Ruolo, Testo, Mancante)
		SELECT
			r.Pos,
			r.Ruolo,
			N'codice fiscale ' + r.CodiceFiscale + ISNULL(N', autorizzazione ' + r.Autorizzazione, N'') + N' – '
			+ IIF(r.Corrispondenze = 0, N'non è in anagrafica',
				CAST(r.Corrispondenze AS NVARCHAR(10)) + N' corrispondenze in anagrafica, sceglierne una'),
			CAST(IIF(r.Corrispondenze = 0, 1, 0) AS BIT)
		FROM
			#match m
			CROSS APPLY (
				VALUES
					(1, N'Produttore', @ProduttoreCodiceFiscale, @ProduttoreAutorizzazione, m.CorrispondenzeProduttore, ISNULL(@isProduttore, 0)),
					(2, N'Destinatario', @DestinatarioCodiceFiscale, @DestinatarioAutorizzazione, m.CorrispondenzeDestinatario, ISNULL(@isDestinatario, 0)),
					(3, N'Trasportatore', @TrasportatoreCodiceFiscale, @TrasportatoreAutorizzazioneAlbo, m.CorrispondenzeTrasportatore, ISNULL(@isTrasportatore, 0)),
					(4, N'Intermediario', @IntermediarioCodiceFiscale, @IntermediarioAutorizzazioneAlbo, m.CorrispondenzeIntermediario1, ISNULL(@isIntermediario, 0)),
					(5, N'Secondo intermediario', @Intermediario2CodiceFiscale, @Intermediario2AutorizzazioneAlbo, m.CorrispondenzeIntermediario2, ISNULL(@isIntermediario, 0))
			) r (Pos, Ruolo, CodiceFiscale, Autorizzazione, Corrispondenze, Previsto)
		WHERE
			r.Previsto = 1
			AND r.Corrispondenze IS NOT NULL;

		DECLARE @avvisi NVARCHAR(MAX) = (SELECT Ruolo, Testo, Mancante
		FROM @mancanti
		ORDER BY Pos
		FOR JSON PATH);

		-- ── Normalizzazione quantità/date con sentinella (stesso principio della legacy) ─────
		DECLARE @quantitaFinale DECIMAL(18, 3) = IIF(@Quantita >= 0, @Quantita, 0);
		DECLARE @quantitaVerificataFinale DECIMAL(18, 3) = IIF(@QuantitaDestino >= 0, @QuantitaDestino, NULL);

		DECLARE @dataOraInizioTrasportoFinale DATETIME2(0) = TRY_CAST(@DataOraInizioTrasporto AS DATETIME2(0));
		IF @dataOraInizioTrasportoFinale >= '20500101' SET @dataOraInizioTrasportoFinale = NULL;

		IF @DataOraFineTrasporto >= '20500101' SET @DataOraFineTrasporto = NULL;

		DECLARE @dataEmissioneFinale DATE = IIF(ISNULL(@DataEmissione, '19000101') < '20000101', CAST(GETDATE() AS DATE), @DataEmissione);

		DECLARE @analisiDataFinale DATE = TRY_CAST(@AnalisiData AS DATE);

		-- Data di registrazione proposta: sempre quella odierna (non le date del trasporto del FIR)
		DECLARE @registrazioneData DATE = CAST(GETDATE() AS DATE);

		CREATE TABLE #numero (Rtn INT);
		INSERT #numero EXEC dbo.uspRifiutiRegistrazioni_get_UltimoNumero @IdRegistro = @IdRegistro, @Data = @registrazioneData, @IdSessione = @IdSessione;
		DECLARE @registrazioneNumero INT = (SELECT TOP 1 Rtn + 1 FROM #numero);

		-- ── Creazione ─────────────────────────────────────────────────────────────────────
		DECLARE @idMovimento CHAR(16), @idRegistrazione CHAR(16), @idFormulario CHAR(16);

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		-- Produttore senza autorizzazioni: uspRifiutiAutorizzazioni_get_MatchImportazione (passo 3) restituisce
		-- l'Id della Sede, che va convertito nell'autorizzazione "Nessuna" della sede, creata se manca - stesso
		-- principio di uspRifiutiRegistrazioni_upd (la FK di tblRifiutiMovimentiProduttori non accetta una Sede)
		DECLARE @idSedeProduttoreNessuna CHAR(16) = NULL;
		IF EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @idAutorizzazioneProduttoreDetentore)
		BEGIN
			DECLARE @idSedeProduttore CHAR(16) = @idAutorizzazioneProduttoreDetentore;
			SET @idAutorizzazioneProduttoreDetentore = NULL;

			SELECT @idAutorizzazioneProduttoreDetentore = Id
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @idSedeProduttore
				AND IdRuolo = 'P'
				AND Nessuna = 1
				AND Lock = 0;

			IF @idAutorizzazioneProduttoreDetentore IS NULL
			BEGIN
				SET @idSedeProduttoreNessuna = @idSedeProduttore;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idAutorizzazioneProduttoreDetentore OUTPUT;
			END
		END

		IF @ModalitaRitorno = 'R'
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRegistrazione OUTPUT;
		ELSE
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idFormulario OUTPUT;

		BEGIN TRANSACTION;

			IF @idSedeProduttoreNessuna IS NOT NULL
				INSERT dbo.tblRifiutiAutorizzazioni
					(Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
				VALUES
					(@idAutorizzazioneProduttoreDetentore, @idSedeProduttoreNessuna, 'P', '19000101', '20501231', 1, 0, 0);

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, FormularioNumero, RentriFormularioStato, DataInizioTrasporto, Note)
			VALUES
				(@idMovimento, @IdRegistro, @IdOperazione, @Eer, @EerDescrizione, @idStatoFisico, @idAttivitaRs, @idUnitaMisura, @Provenienza, @quantitaFinale, @Numero, @Stato, @dataOraInizioTrasportoFinale, @Note);

			IF @idAutorizzazioneProduttoreDetentore IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @idAutorizzazioneProduttoreDetentore, @quantitaFinale, 0);

			IF @idAutorizzazioneDestinatario IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneDestinatario, 0);

			-- Solo il trasporto su strada e' estratto dal FIR (conducente/targhe/percorso): se presente uno
			-- di questi dati si assume 'G' (terrestre), altrimenti si lascia decidere all'utente da Edit.
			DECLARE @isTrasportoStrada BIT = CAST(IIF(@TargaMotrice IS NOT NULL OR @ConducenteNome IS NOT NULL, 1, 0) AS BIT);
			IF @idAutorizzazioneTrasportatore1 IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
				VALUES (@idMovimento, @idAutorizzazioneTrasportatore1, IIF(@isTrasportoStrada = 1, 'G', NULL), 0);

			IF @idAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneIntermediario1, 0);

				IF @idAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @idAutorizzazioneIntermediario2, 1);
			END

			IF @ClassiPericolo IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
				SELECT @idMovimento, c.Id
				FROM
					STRING_SPLIT(@ClassiPericolo, ';') v
					INNER JOIN dbo.tblRifiutiClassiPericolo c ON c.Codice = v.value;

			IF @ModalitaRitorno = 'R'
			BEGIN
				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, [Data], Numero, IdEsito, QuantitaVerificata, DataFineTrasporto, IdCausaleRespingimento, CausaleRespingimentoAltro, Lock)
				VALUES
					(@idRegistrazione, @idMovimento, @operazione, @registrazioneData, @registrazioneNumero, @idEsito, @quantitaVerificataFinale, @DataOraFineTrasporto, @idCausaleRespingimento, LEFT(@RespingimentoMotivo, 100), 2);

				SET @returnId = @idRegistrazione;
			END
			ELSE
			BEGIN
				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdAdr, IdAnalisiTipo, TrasportoAdr, DataEmissione, AnalisiData, AnalisiNumero, VerificatoInPartenza, NumeroOnu, AdrNote, ColliNumero, Lock)
				VALUES
					(@idFormulario, @idMovimento, @idAdr, @idAnalisiTipo, CAST(IIF(@ClasseADR IS NOT NULL, 1, 0) AS BIT), @dataEmissioneFinale, @analisiDataFinale, @AnalisiNumero, @QuantitaVerificataPartenza, @NumeroONU, @AdrNote, @Colli, 2);

				IF @isTrasportoStrada = 1
					INSERT dbo.tblRifiutiFormulariTrasportiTerresti (Id, TargaMotrice, TargaRimorchio, ConducenteNome, ConducenteCognome, Percorso)
					VALUES (@idFormulario, @TargaMotrice, @TargaRimorchio, @ConducenteNome, @ConducenteCognome, @Percorso);

				SET @returnId = @idFormulario;
			END

		COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT
		Id = @returnId,
		Avvisi = @avvisi;

END;
GO

-- ===== 5. uspRifiutiMovimenti_ins_DaAllegatoVii
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Crea la bozza (Lock = 2) di una registrazione dai dati di un Allegato VII dell'azienda del contesto, inviato o
-- ricevuto da DIWASS (Diwass > Allegati VII, Azioni > Registra nel registro; docs/regole/diwass.md D8), come
-- l'acquisizione da formulario digitale (uspRifiutiMovimenti_ins_DaAcquisizioneFormulario): l'utente controlla la
-- bozza in Rifiuti > Registrazioni, Salva la finalizza con uspRifiutiRegistrazioni_upd, Annulla la cancella con
-- uspRifiutiRegistrazioni_del. Causali ammesse (filtro proprio di questa funzione): trasporto T*aT (T) se l'azienda è
-- un trasportatore, carico da terzi T* (Z) se è l'impianto, scarico a terzi aT (S) se è il produttore o chi organizza.
-- La registrazione si fa solo dopo il passaggio su DIWASS che la giustifica: T*aT dopo la presa in carico del suo
-- trasportatore, T* dopo la ricezione al suo impianto, aT dopo la prima presa in carico (decisione dell'utente del
-- 2026-11-19). I soggetti si prendono dalle sedi in anagrafica collegate agli operatori DIWASS del documento, con
-- un'autorizzazione valida alla data del trasporto per il trasportatore e il destinatario: quelli non trovati restano
-- vuoti, l'utente li sceglie nella scheda della registrazione (come nell'acquisizione da formulario digitale) e gli
-- avvisi restituiti con l'Id dicono quali sono (decisione dell'utente del 2026-11-19).
-- Documento di trasporto Allegato VII (IdTrasportoTransfrontalieroTipo = 'D'), numero DIWASS nelle note del movimento,
-- registrazione collegata all'Allegato VII (tblDiwassAllegatiVii.IdRegistrazione)
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_ins_DaAllegatoVii]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(2000) = NULL;
		DECLARE @returnId CHAR(16) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro';
			GOTO BRANCH_END;
		END
		IF @IdOperazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la causale';
			GOTO BRANCH_END;
		END

		-- Permessi: Allegati VII in lettura e registrazioni in scrittura
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
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

		-- Allegato VII dell'azienda del contesto
		DECLARE
			@idAzienda CHAR(16), @numero VARCHAR(50), @stato VARCHAR(20), @ruoli VARCHAR(10), @dataSpedizione DATE,
			@quantita DECIMAL(18, 5), @unitaQuantita CHAR(1), @idEer CHAR(6), @descrizione VARCHAR(500),
			@idAttivita CHAR(2), @idRegistrazioneEsistente CHAR(16);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@numero = a.Numero,
			@stato = a.Stato,
			@ruoli = ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')),
			@dataSpedizione = a.DataSpedizione,
			@quantita = a.Quantita,
			@unitaQuantita = a.UnitaQuantita,
			@idEer = a.IdEer,
			@descrizione = a.Descrizione,
			@idAttivita = a.IdAttivita,
			@idRegistrazioneEsistente = a.IdRegistrazione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END
		IF @numero IS NULL OR @stato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII non è ancora stato inviato a DIWASS';
			GOTO BRANCH_END;
		END
		IF @stato = 'CANCELLED'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII è annullato su DIWASS: non si registra';
			GOTO BRANCH_END;
		END

		-- Una sola registrazione attiva per Allegato VII (una bozza abbandonata non conta)
		DECLARE @esistenteNumero INT, @esistenteData DATE;
		SELECT
			@esistenteNumero = r.Numero,
			@esistenteData = r.[Data]
		FROM dbo.tblRifiutiRegistrazioni r
		WHERE
			r.Id = @idRegistrazioneEsistente
			AND r.Lock < 2;
		IF @esistenteData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII ha già la registrazione n. ' + CAST(@esistenteNumero AS VARCHAR(10)) + ' del ' + CONVERT(VARCHAR(10), @esistenteData, 103);
			GOTO BRANCH_END;
		END

		-- Registro di una sede interna dell'azienda, visibile all'utente, del tipo che ammette la causale
		DECLARE @idSedeRegistro CHAR(16), @idTipoRegistro CHAR(1);
		SELECT
			@idSedeRegistro = g.IdSede,
			@idTipoRegistro = g.IdTipo
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
		WHERE
			g.Id = @IdRegistro
			AND g.Lock = 0
			AND s.IdAziendaInterna = @idAzienda;

		IF @idSedeRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è di una sede dell''azienda dell''Allegato VII';
			GOTO BRANCH_END;
		END

		DECLARE
			@operazione CHAR(1), @codiceOperazione VARCHAR(5), @isProduttore BIT, @isTrasportatore BIT,
			@isDestinatario BIT, @isEsito BIT, @isAttivitaRs BIT, @produttoreSede BIT, @trasportatoreSede BIT,
			@destinatarioSede BIT;
		SELECT
			@operazione = o.Operazione,
			@codiceOperazione = o.Codice,
			@isProduttore = ISNULL(o.IsProduttore, 0),
			@isTrasportatore = ISNULL(o.IsTrasportatore, 0),
			@isDestinatario = ISNULL(o.IsDestinatario, 0),
			@isEsito = ISNULL(o.IsEsito, 0),
			@isAttivitaRs = ISNULL(o.IsAttivitaRs, 0),
			@produttoreSede = ISNULL(o.ProduttoreSede, 0),
			@trasportatoreSede = ISNULL(o.TrasportatoreSede, 0),
			@destinatarioSede = ISNULL(o.DestinatarioSede, 0)
		FROM dbo.tblRifiutiOperazioni o
		WHERE
			o.Id = @IdOperazione
			AND o.Id IN ('T', 'Z', 'S');

		IF @operazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è valida per la registrazione da Allegato VII';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiOperazioniRegistriTipi
			WHERE
				Id = @IdOperazione
				AND IdTipo = @idTipoRegistro
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è ammessa nel registro selezionato';
			GOTO BRANCH_END;
		END

		-- Ruolo dell'azienda richiesto dalla causale
		IF (@IdOperazione = 'T' AND @ruoli NOT LIKE '%T%')
			OR (@IdOperazione = 'Z' AND @ruoli NOT LIKE '%I%')
			OR (@IdOperazione = 'S' AND @ruoli NOT LIKE '%P%' AND @ruoli NOT LIKE '%O%')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con la causale ' + @codiceOperazione + ' l''azienda deve essere '
				+ CASE @IdOperazione
					WHEN 'T' THEN 'un trasportatore'
					WHEN 'Z' THEN 'l''impianto'
					ELSE 'il produttore o chi organizza la spedizione'
				END + ' nell''Allegato VII';
			GOTO BRANCH_END;
		END

		-- Soggetti del documento con l'operatore DIWASS (della sede in anagrafica o letto da DIWASS), la sede in
		-- anagrafica dell'azienda collegata allo stesso operatore (prima quella del documento, poi le interne) e se
		-- l'operatore è di una sede interna dell'azienda
		DECLARE @soggetti TABLE (
			Ruolo CHAR(1),
			Pos TINYINT,
			OperatorInternalId BIGINT,
			Nome NVARCHAR(250),
			MezzoTrasporto CHAR(1),
			IdSede CHAR(16),
			NSedi INT,
			DellAzienda BIT
		);
		-- Sede: quella del documento se è dell'azienda, altrimenti l'unica sede dell'azienda collegata allo stesso
		-- operatore; con più sedi collegate allo stesso operatore non si sceglie (NSedi > 1, la sceglie l'utente)
		INSERT INTO @soggetti (Ruolo, Pos, OperatorInternalId, Nome, MezzoTrasporto, IdSede, NSedi, DellAzienda)
		SELECT
			x.Ruolo,
			x.Pos,
			v.OperatorInternalId,
			ISNULL(sd.NomeCompleto, x.Nome),
			x.MezzoTrasporto,
			ISNULL(sv.Id, IIF(sc.N = 1, sc.IdUnico, NULL)),
			IIF(sv.Id IS NOT NULL, 1, sc.N),
			CAST(IIF(si.Id IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			LEFT JOIN dbo.tblSedi sd ON x.IdSede = sd.Id
			LEFT JOIN dbo.tblSedi sv ON x.IdSede = sv.Id AND sv.IdAziendaInterna = @idAzienda AND sv.Lock = 0
			LEFT JOIN dbo.tblDiwassOperatori od ON x.IdSede = od.Id
			CROSS APPLY (SELECT OperatorInternalId = ISNULL(od.OperatorInternalId, x.OperatorInternalId)) v
			OUTER APPLY (
				SELECT
					N = COUNT(*),
					IdUnico = MIN(z.Id)
				FROM
					dbo.tblSedi z
					INNER JOIN dbo.tblDiwassOperatori oz ON z.Id = oz.Id
				WHERE
					z.IdAziendaInterna = @idAzienda
					AND z.Lock = 0
					AND oz.OperatorInternalId = v.OperatorInternalId
			) sc
					OUTER APPLY (
				SELECT TOP 1 z.Id
				FROM
					dbo.tblDiwassOperatori oz
					INNER JOIN dbo.tblSedi z ON oz.Id = z.Id
				WHERE
					oz.OperatorInternalId = v.OperatorInternalId
					AND z.InternaEsterna = 'I'
					AND z.IdAziendaInterna = @idAzienda
					) si
		WHERE x.Id = @Id;

		-- Passaggio su DIWASS che giustifica la registrazione (le ricezioni e il recupero lette prima della correzione
		-- dell'hub del 2026-11-09 hanno l'operatore 0: valgono per l'unico impianto)
		DECLARE @dataPresaInCarico DATE, @dataRicezione DATE, @quantitaRespinta DECIMAL(18, 5);
		IF @IdOperazione = 'T'
			SELECT @dataPresaInCarico = MIN(k.Data)
			FROM
				@soggetti s
				INNER JOIN dbo.tblDiwassAllegatiViiConferme k ON k.Id = @Id AND k.Tipo = 'T' AND k.OperatorInternalId = s.OperatorInternalId
			WHERE
				s.Ruolo = 'T'
				AND s.DellAzienda = 1;
		ELSE
			SELECT @dataPresaInCarico = MIN(k.Data)
			FROM dbo.tblDiwassAllegatiViiConferme k
			WHERE
				k.Id = @Id
				AND k.Tipo = 'T';

		SELECT TOP 1
			@dataRicezione = k.Data,
			@quantitaRespinta = k.QuantitaRespinta
		FROM
			@soggetti s
			INNER JOIN dbo.tblDiwassAllegatiViiConferme k ON k.Id = @Id AND k.Tipo = 'I' AND (k.OperatorInternalId = s.OperatorInternalId OR ISNULL(k.OperatorInternalId, 0) = 0)
		WHERE
			s.Ruolo = 'I'
			AND k.Data IS NOT NULL
			AND
				(
				@IdOperazione <> 'Z'
				OR s.DellAzienda = 1
				)
		ORDER BY s.Pos;

		IF @IdOperazione IN ('T', 'S') AND @dataPresaInCarico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@IdOperazione = 'T', N'La presa in carico del trasportatore', N'La presa in carico')
				+ N' non risulta ancora su DIWASS: la registrazione si fa dopo (Azioni > DIWASS – Leggi stato la aggiorna)';
			GOTO BRANCH_END;
		END
		IF @IdOperazione = 'Z' AND @dataRicezione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = N'La ricezione all''impianto non risulta ancora su DIWASS: la registrazione si fa dopo (Azioni > DIWASS – Leggi stato la aggiorna)';
			GOTO BRANCH_END;
		END

		DECLARE @dataTrasporto DATE = ISNULL(@dataPresaInCarico, @dataSpedizione);

		-- ── Soggetti della registrazione ────────────────────────────────────────────────────────────────────────────
		-- Un soggetto per riga: la sede (fissa, quella del registro o dell'azienda, oppure dal documento) e
		-- l'autorizzazione del ruolo valida alla data del trasporto. Si compila solo con una corrispondenza unica; con
		-- nessuna o più corrispondenze il campo resta vuoto e l'avviso dice quale e perché (lo sceglie l'utente nella
		-- registrazione, come nell'acquisizione da formulario digitale)
		DECLARE @idAziendaRegistro CHAR(16) = (SELECT IdAziendaInterna
		FROM dbo.tblSedi
		WHERE Id = @idSedeRegistro);
		DECLARE @dataTesto NVARCHAR(10) = CONVERT(NVARCHAR(10), @dataTrasporto, 103);

		DECLARE @req TABLE (
			Ordine INT IDENTITY(1, 1),
			Tipo CHAR(1),
			PosTrasportatore TINYINT,
			Etichetta NVARCHAR(60),
			Nome NVARCHAR(250),
			OperatorInternalId BIGINT,
			MezzoTrasporto CHAR(1),
			IdSede CHAR(16),
			NSedi INT,
			IdAutorizzazione CHAR(16),
			NAutorizzazioni INT
		);

		-- Produttore: la sede del registro (scarico a terzi) o il produttore del documento, se manca chi organizza
		IF @isProduttore = 1
		BEGIN
			IF @produttoreSede = 1
				INSERT INTO @req (Tipo, Etichetta, Nome, IdSede, NSedi)
				SELECT 'P', N'Produttore', NomeCompleto, Id, 1
				FROM dbo.tblSedi
				WHERE Id = @idSedeRegistro;
			ELSE
				INSERT INTO @req (Tipo, Etichetta, Nome, OperatorInternalId, IdSede, NSedi)
				SELECT TOP 1 'P', IIF(Ruolo = 'P', N'Produttore', N'Chi organizza la spedizione (produttore)'), Nome, OperatorInternalId, IdSede, NSedi
				FROM @soggetti
				WHERE Ruolo IN ('P', 'O')
				ORDER BY IIF(Ruolo = 'P', 0, 1), Pos;
		END

		-- Destinatario: la sede del registro (carico da terzi) o il primo impianto del documento
		IF @isDestinatario = 1
		BEGIN
			IF @destinatarioSede = 1
				INSERT INTO @req (Tipo, Etichetta, Nome, IdSede, NSedi)
				SELECT 'D', N'Destinatario', NomeCompleto, Id, 1
				FROM dbo.tblSedi
				WHERE Id = @idSedeRegistro;
			ELSE
				INSERT INTO @req (Tipo, Etichetta, Nome, OperatorInternalId, IdSede, NSedi)
				SELECT TOP 1 'D', N'Impianto', Nome, OperatorInternalId, IdSede, NSedi
				FROM @soggetti
				WHERE Ruolo = 'I'
				ORDER BY Pos;
		END

		-- Trasportatori: l'azienda del registro (trasporto) o fino a tre trasportatori del documento; mezzo dal documento
		IF @isTrasportatore = 1
		BEGIN
			IF @trasportatoreSede = 1
				INSERT INTO @req (Tipo, PosTrasportatore, Etichetta, Nome, MezzoTrasporto, IdSede, NSedi)
				SELECT TOP 1 'T', 0, N'Trasportatore', z.NomeCompleto, s.MezzoTrasporto, @idAziendaRegistro, 1
				FROM
					@soggetti s
					INNER JOIN dbo.tblSedi z ON z.Id = @idAziendaRegistro
				WHERE
					s.Ruolo = 'T'
					AND s.DellAzienda = 1
				ORDER BY s.Pos;
			ELSE
				INSERT INTO @req (Tipo, PosTrasportatore, Etichetta, Nome, OperatorInternalId, MezzoTrasporto, IdSede, NSedi)
				SELECT TOP 3 'T', ROW_NUMBER() OVER (ORDER BY Pos) - 1, N'Trasportatore', Nome, OperatorInternalId, MezzoTrasporto, IdSede, NSedi
				FROM @soggetti
				WHERE Ruolo = 'T'
				ORDER BY Pos;
		END

		-- Autorizzazione del ruolo valida alla data del trasporto (non "Nessuna"): della sede o, se la sede non ne ha,
		-- della sua azienda (per destinatario e trasportatore); compilata solo se è una
		UPDATE q
		SET
			NAutorizzazioni = au.N,
			IdAutorizzazione = IIF(au.N = 1, au.IdUnico, NULL)
		FROM
			@req q
			INNER JOIN dbo.tblSedi z ON q.IdSede = z.Id
			CROSS APPLY (
				SELECT TOP 1
					N = COUNT(*),
					IdUnico = MIN(a.Id)
				FROM dbo.tblRifiutiAutorizzazioni a
				WHERE
					(
					a.IdSede = z.Id
					OR
						(
						q.Tipo IN ('D', 'T')
						AND a.IdSede = z.IdParent
						)
					)
					AND a.IdRuolo = q.Tipo
					AND a.Lock = 0
					AND ISNULL(a.Disabilitata, 0) = 0
					AND ISNULL(a.Nessuna, 0) = 0
					AND @dataTrasporto BETWEEN a.DataInizio AND a.DataFine
				GROUP BY IIF(a.IdSede = z.Id, 0, 1)
				ORDER BY IIF(a.IdSede = z.Id, 0, 1)
			) au
		WHERE q.NSedi = 1;

		UPDATE @req
		SET NAutorizzazioni = 0
		WHERE
			NSedi = 1
			AND NAutorizzazioni IS NULL;

		-- Produttore senza autorizzazioni da produttore: l'autorizzazione "Nessuna" della sede (creata se manca)
		DECLARE @idSedeProduttoreNessuna CHAR(16) = NULL;
		UPDATE q
		SET IdAutorizzazione = ( SELECT TOP 1 a.Id FROM dbo.tblRifiutiAutorizzazioni a WHERE a.IdSede = q.IdSede AND a.IdRuolo = 'P' AND a.Nessuna = 1 AND a.Lock = 0 )
		FROM @req q
		WHERE
			q.Tipo = 'P'
			AND q.NSedi = 1
			AND q.NAutorizzazioni = 0;

		SELECT @idSedeProduttoreNessuna = IdSede
		FROM @req
		WHERE
			Tipo = 'P'
			AND NSedi = 1
			AND NAutorizzazioni = 0
			AND IdAutorizzazione IS NULL;

		-- Avvisi, uno per soggetto da completare
		-- Avvisi, uno per soggetto da completare: ruolo (in grassetto nella finestra) e testo "soggetto – motivo"
		DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Ruolo NVARCHAR(60), Testo NVARCHAR(400), Mancante BIT);
		-- Mancante = 1: soggetto o autorizzazione da inserire in anagrafica; 0: più corrispondenze, solo da scegliere
		INSERT INTO @mancanti (Ruolo, Testo, Mancante)
		SELECT
			q.Etichetta,
			ISNULL(q.Nome, N'') + ISNULL(N' (operatore DIWASS ' + CAST(q.OperatorInternalId AS NVARCHAR(20)) + N')', N'') + N' – '
			+ CASE
				WHEN ISNULL(q.NSedi, 0) = 0 THEN N'non è in anagrafica'
				WHEN q.NSedi > 1 THEN CAST(q.NSedi AS NVARCHAR(10)) + N' soggetti in anagrafica collegati allo stesso operatore, sceglierne uno'
				WHEN q.NAutorizzazioni = 0 THEN N'nessuna autorizzazione da ' + IIF(q.Tipo = 'D', N'destinatario', N'trasportatore') + N' valida al ' + @dataTesto
				ELSE CAST(q.NAutorizzazioni AS NVARCHAR(10)) + N' autorizzazioni valide al ' + @dataTesto + N', sceglierne una'
			END,
			CAST(IIF(ISNULL(q.NSedi, 0) = 0 OR (q.NSedi = 1 AND q.NAutorizzazioni = 0), 1, 0) AS BIT)
		FROM @req q
		WHERE
			q.IdAutorizzazione IS NULL
			AND NOT (q.Tipo = 'P' AND q.NSedi = 1 AND q.NAutorizzazioni = 0)
		ORDER BY q.Ordine;

		IF @isTrasportatore = 1 AND NOT EXISTS (SELECT 1
		FROM @req
		WHERE Tipo = 'T')
			INSERT INTO @mancanti (Ruolo, Testo, Mancante)
			VALUES (N'Trasportatore', N'il documento non ne indica nessuno', 0);

		-- Elenco per la finestra "Da completare" della scheda della registrazione
		DECLARE @avvisi NVARCHAR(MAX) = (SELECT Ruolo, Testo, Mancante
		FROM @mancanti
		ORDER BY Pos
		FOR JSON PATH);

		DECLARE @idAutorizzazioneProduttore CHAR(16) = (SELECT IdAutorizzazione
		FROM @req
		WHERE Tipo = 'P');
		DECLARE @idAutorizzazioneDestinatario CHAR(16) = (SELECT IdAutorizzazione
		FROM @req
		WHERE Tipo = 'D');
		DECLARE @trasportatori TABLE (Pos TINYINT, IdAutorizzazione CHAR(16), IdTipo CHAR(1));
		INSERT INTO @trasportatori (Pos, IdAutorizzazione, IdTipo)
		SELECT
			PosTrasportatore,
			IdAutorizzazione,
			CASE MezzoTrasporto
				WHEN 'R' THEN 'G'
				WHEN 'T' THEN 'T'
				WHEN 'S' THEN 'N'
			END
		FROM @req
		WHERE
			Tipo = 'T'
			AND IdAutorizzazione IS NOT NULL;

		-- ── Dati del movimento e della registrazione ────────────────────────────────────────────────────────────────
		DECLARE @idUnitaMisura CHAR(2) = IIF(@unitaQuantita = 'M', 'MC', 'TN');
		DECLARE @quantitaMovimento DECIMAL(18, 3) = ISNULL(@quantita, 0);
		IF @isAttivitaRs = 0 SET @idAttivita = NULL;
		-- Esito solo se l'impianto ha accettato tutto: con una quantità respinta lo completa l'utente
		DECLARE @idEsito CHAR(1) = IIF(@isEsito = 1 AND @dataRicezione IS NOT NULL AND ISNULL(@quantitaRespinta, 0) = 0, 'A', NULL);
		DECLARE @dataFineTrasporto SMALLDATETIME = IIF(@IdOperazione IN ('T', 'Z') OR @idEsito IS NOT NULL, @dataRicezione, NULL);
		DECLARE @note VARCHAR(500) = LEFT('Allegato VII ' + @numero, 500);

		-- Data di registrazione proposta: oggi, come nell'acquisizione da formulario digitale
		DECLARE @registrazioneData DATE = CAST(GETDATE() AS DATE);
		CREATE TABLE #numero (Rtn INT);
		INSERT #numero EXEC dbo.uspRifiutiRegistrazioni_get_UltimoNumero @IdRegistro = @IdRegistro, @Data = @registrazioneData, @IdSessione = @IdSessione;
		DECLARE @registrazioneNumero INT = (SELECT TOP 1 Rtn + 1
		FROM #numero);

		-- uspId_get FUORI dalla transazione
		DECLARE @idMovimento CHAR(16);
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;
		IF @idSedeProduttoreNessuna IS NOT NULL
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idAutorizzazioneProduttore OUTPUT;

		BEGIN TRANSACTION;

			IF @idSedeProduttoreNessuna IS NOT NULL
				INSERT INTO dbo.tblRifiutiAutorizzazioni (Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
				VALUES (@idAutorizzazioneProduttore, @idSedeProduttoreNessuna, 'P', '19000101', '20501231', 1, 0, 0);

			INSERT INTO dbo.tblRifiutiMovimenti (Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdAttivita, IdUnitaMisura, Quantita, DataInizioTrasporto, Note)
			VALUES (@idMovimento, @IdRegistro, @IdOperazione, @idEer, LEFT(@descrizione, 200), @idAttivita, @idUnitaMisura, @quantitaMovimento, @dataTrasporto, @note);

			IF @idAutorizzazioneProduttore IS NOT NULL
				INSERT INTO dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @idAutorizzazioneProduttore, @quantitaMovimento, 0);

			IF @idAutorizzazioneDestinatario IS NOT NULL
				INSERT INTO dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneDestinatario, 0);

			INSERT INTO dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
			SELECT @idMovimento, IdAutorizzazione, IdTipo, ROW_NUMBER() OVER (ORDER BY Pos) - 1
			FROM @trasportatori;

			INSERT INTO dbo.tblRifiutiRegistrazioni (Id, IdMovimento, Operazione, [Data], Numero, IdEsito, DataFineTrasporto, IdTrasportoTransfrontalieroTipo, Lock)
			VALUES (@returnId, @idMovimento, @operazione, @registrazioneData, @registrazioneNumero, @idEsito, @dataFineTrasporto, 'D', 2);

			UPDATE dbo.tblDiwassAllegatiVii
			SET IdRegistrazione = @returnId
			WHERE Id = @Id;

		COMMIT TRANSACTION;

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

	SELECT
		Id = @returnId,
		Avvisi = @avvisi;

END;
GO

-- ===== 6. uspDiwassAllegatiVii_get_Registri_SelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registri in cui registrare un Allegato VII dell'azienda del contesto (docs/regole/diwass.md D8.2): registri attivi
-- delle sedi interne dell'azienda visibili all'utente, prima quelli della sede che compare nel documento con il ruolo
-- dell'azienda (stesso operatore DIWASS), poi per nome. Casella di ricerca a fianco della select (@Search sul testo,
-- come Copia/incolla delle registrazioni): al massimo 20 voci, il registro scelto (@IdSelected) resta sempre in elenco
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Registri_SelectList]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = a.IdAziendaInterna
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT TOP 20
			g.Id,
			[Text] = g.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto
		FROM
			dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			INNER JOIN dbo.tblRifiutiRegistri g ON i.Id = g.IdSede
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			OUTER APPLY (
				SELECT TOP 1 Nel = 1
				FROM
					dbo.tblDiwassAllegatiViiSoggetti x
					LEFT JOIN dbo.tblDiwassOperatori ox ON x.IdSede = ox.Id
					LEFT JOIN dbo.tblDiwassOperatori os ON os.Id = s.Id
				WHERE
					x.Id = @Id
					AND
						(
						x.IdSede = s.Id
						OR ISNULL(ox.OperatorInternalId, x.OperatorInternalId) = os.OperatorInternalId
						)
			) d
		WHERE
			g.Lock = 0
			AND s.IdAziendaInterna = @idAzienda
			AND
				(
				@Search IS NULL
				OR g.Id = @IdSelected
				OR (g.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto) LIKE '%' + @Search + '%'
				)
		ORDER BY IIF(g.Id = @IdSelected, 0, 1), ISNULL(d.Nel, 0) DESC, g.Nome, s.Nome
		OPTION (RECOMPILE);

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

-- ===== 7. uspDiwassAllegatiVii_get_Operazioni_SelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Causali proposte per registrare un Allegato VII dell'azienda del contesto (docs/regole/diwass.md D8.2), secondo il
-- ruolo dell'azienda nel documento: trasporto T*aT (T) se è un trasportatore, carico da terzi T* (Z) se è l'impianto,
-- scarico a terzi aT (S) se è il produttore o chi organizza; prima la proposta (nell'ordine T, Z, S). Il filtro è
-- proprio di questa funzione (decisione dell'utente del 2026-11-19) e lo ripete uspRifiutiMovimenti_ins_DaAllegatoVii
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Operazioni_SelectList]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @ruoli VARCHAR(10);
		SELECT @ruoli = ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', ''))
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @ruoli IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT
			o.Id,
			[Text] = CAST(o.Pos AS VARCHAR(2)) + '. ' + o.Nome
		FROM dbo.tblRifiutiOperazioni o
		WHERE
			(
			o.Id = 'T'
			AND @ruoli LIKE '%T%'
			)
			OR
				(
				o.Id = 'Z'
				AND @ruoli LIKE '%I%'
				)
			OR
				(
				o.Id = 'S'
				AND
					(
					@ruoli LIKE '%P%'
					OR @ruoli LIKE '%O%'
					)
				)
		ORDER BY CASE o.Id WHEN 'T' THEN 0 WHEN 'Z' THEN 1 ELSE 2 END;

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

-- ===== 8. uspDiwassAllegatiVii_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Allegati VII: documenti dell'azienda del contesto, inviati da Ecomatico o ricevuti da DIWASS (Ricevuto = 1),
-- dal più recente, con i ruoli dell'azienda, l'avanzamento e il passaggio che le spetta (docs/regole/diwass.md D6)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@Ruolo CHAR(1) = NULL,
	@DaFare BIT = NULL,
	@SenzaRegistrazione BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda del contesto (senza azienda nessuna riga). @Stato: B = bozze, altrimenti lo stato DIWASS; @Ruolo:
		-- uno dei ruoli dell'azienda (O, P, D, I, T); @DaFare = 1: solo i documenti con un passaggio che spetta all'azienda
		SELECT
			a.Id,
			StatoValore = CASE
				WHEN a.Stato IS NULL OR a.DaInviare = 1 THEN 1
				WHEN a.Stato IN ('CANCELLED', 'TAKE_BACK') THEN 2
				ELSE 0
			END,
			StatoDescrizione = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato)
				+ IIF(a.DaInviare = 1, ' - modifiche da inviare a DIWASS', ''),
			a.Numero,
			a.Stato,
			StatoNome = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			a.DataSpedizione,
			EerNome = e.Nome,
			a.Descrizione,
			DestinatarioNome = ISNULL(d.NomeCompleto, x.Nome),
			OrganizzatoreNome = ISNULL(so.NomeCompleto, xo.Nome),
			Ricevuto = CAST(ISNULL(a.Ricevuto, 0) AS BIT),
			a.Ruoli,
			RuoliNome = dbo.ufnDiwassAllegatiVii_get_RuoliDescrizione(a.Ruoli),
			v.Trasportatori,
			v.PreseInCarico,
			v.PresaInCaricoData,
			v.RicezioneDestinatarioPrevista,
			v.RicezioneDestinatarioData,
			v.RicezioneImpiantoData,
			v.CompletamentoData,
			v.DaFare,
			v.Scadenza,
			PaeseDestinazione = n.Nome,
			a.Quantita,
			a.UnitaQuantita,
			IdRegistrazione = r.Id,
			RegistrazioneNumero = r.Numero,
			RegistrazioneData = r.[Data],
			-- Documento che l'azienda può registrare (D8.1): senza registrazione la colonna lo dice
			Registrabile = CAST(IIF(a.Numero IS NOT NULL AND ISNULL(a.Stato, '') <> 'CANCELLED' AND ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')) LIKE '%[TIPO]%', 1, 0) AS BIT),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni s ON a.IdAziendaInterna = s.IdAzienda
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti x ON a.Id = x.Id AND x.Ruolo = 'D' AND x.Pos = 1
			LEFT JOIN dbo.tblSedi d ON x.IdSede = d.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti xo ON a.Id = xo.Id AND xo.Ruolo = 'O' AND xo.Pos = 1
			LEFT JOIN dbo.tblSedi so ON xo.IdSede = so.Id
			LEFT JOIN dbo.tblNazioni n ON a.IdNazioneDestinazione = n.Id
			-- Registrazione collegata, solo se attiva (D8.6)
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON a.IdRegistrazione = r.Id AND r.Lock < 2
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Avanzamento(a.Id) v
		WHERE
			s.Id = @IdSessione
			AND a.Lock = 0
			AND
				(
				@Stato IS NULL
				OR
					(
					@Stato = 'B'
					AND a.Stato IS NULL
					)
				OR a.Stato = @Stato
				)
			AND
				(
				@Search IS NULL
				OR a.Numero LIKE '%' + @Search + '%'
				OR a.Descrizione LIKE '%' + @Search + '%'
				OR e.Nome LIKE '%' + @Search + '%'
				OR ISNULL(d.NomeCompleto, x.Nome) LIKE '%' + @Search + '%'
				OR ISNULL(so.NomeCompleto, xo.Nome) LIKE '%' + @Search + '%'
				)
			AND
				(
				@Ruolo IS NULL
				OR ISNULL(a.Ruoli, 'O') LIKE '%' + @Ruolo + '%'
				)
			AND
				(
				ISNULL(@DaFare, 0) = 0
				OR v.DaFare IS NOT NULL
				)
			-- @SenzaRegistrazione = 1: documenti inviati o ricevuti, non annullati, che l'azienda può registrare (trasportatore,
			-- impianto, produttore o chi organizza, D8.1) e senza una registrazione attiva collegata (D8.6)
			AND
				(
				ISNULL(@SenzaRegistrazione, 0) = 0
				OR
					(
					a.Numero IS NOT NULL
					AND ISNULL(a.Stato, '') <> 'CANCELLED'
					AND ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')) LIKE '%[TIPO]%'
					AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.Id = a.IdRegistrazione AND r.Lock < 2)
					)
				)
		ORDER BY a.DataSpedizione DESC, a.Id DESC
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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

-- ===== 9. uspDiwassAllegatiVii_get_Esportazione
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Allegati VII: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassAllegatiVii_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassAllegatiVii_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@Ruolo CHAR(1) = NULL,
	@DaFare BIT = NULL,
	@SenzaRegistrazione BIT = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Numero DIWASS] = a.Numero,
			[Stato] = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato) + IIF(a.DaInviare = 1, ' - modifiche da inviare a DIWASS', ''),
			[Data della spedizione] = a.DataSpedizione,
			[EER] = e.Nome,
			[Codice internazionale] = a.Codice,
			[Descrizione] = a.Descrizione,
			[Quantità] = a.Quantita,
			[Unità] = IIF(a.UnitaQuantita = 'M', 'm³', 't'),
			[Ruolo dell'azienda] = dbo.ufnDiwassAllegatiVii_get_RuoliDescrizione(a.Ruoli),
			[Ricevuto da DIWASS] = IIF(a.Ricevuto = 1, 'Sì', 'No'),
			[Organizzatore] = ISNULL(so.NomeCompleto, xo.Nome),
			[Destinatario] = ISNULL(d.NomeCompleto, x.Nome),
			[Paese di spedizione] = ns.Nome,
			[Paese di destinazione] = n.Nome,
			[Inviato il] = a.DataInvio,
			[Presa in carico] = v.PresaInCaricoData,
			[Ricezione del destinatario] = IIF(v.RicezioneDestinatarioPrevista = 0, NULL, v.RicezioneDestinatarioData),
			[Ricezione all'impianto] = v.RicezioneImpiantoData,
			[Recupero completato] = v.CompletamentoData,
			[Da fare] = v.DaFare,
			[Scadenza] = v.Scadenza,
			[Registrazione n.] = r.Numero,
			[Registrazione del] = r.[Data]
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni s ON a.IdAziendaInterna = s.IdAzienda
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti x ON a.Id = x.Id AND x.Ruolo = 'D' AND x.Pos = 1
			LEFT JOIN dbo.tblSedi d ON x.IdSede = d.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti xo ON a.Id = xo.Id AND xo.Ruolo = 'O' AND xo.Pos = 1
			LEFT JOIN dbo.tblSedi so ON xo.IdSede = so.Id
			LEFT JOIN dbo.tblNazioni n ON a.IdNazioneDestinazione = n.Id
			LEFT JOIN dbo.tblNazioni ns ON a.IdNazioneSpedizione = ns.Id
			-- Registrazione collegata, solo se attiva (D8.6)
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON a.IdRegistrazione = r.Id AND r.Lock < 2
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Avanzamento(a.Id) v
		WHERE
			s.Id = @IdSessione
			AND a.Lock = 0
			AND
				(
				@Stato IS NULL
				OR
					(
					@Stato = 'B'
					AND a.Stato IS NULL
					)
				OR a.Stato = @Stato
				)
			AND
				(
				@Search IS NULL
				OR a.Numero LIKE '%' + @Search + '%'
				OR a.Descrizione LIKE '%' + @Search + '%'
				OR e.Nome LIKE '%' + @Search + '%'
				OR ISNULL(d.NomeCompleto, x.Nome) LIKE '%' + @Search + '%'
				OR ISNULL(so.NomeCompleto, xo.Nome) LIKE '%' + @Search + '%'
				)
			AND
				(
				@Ruolo IS NULL
				OR ISNULL(a.Ruoli, 'O') LIKE '%' + @Ruolo + '%'
				)
			AND
				(
				ISNULL(@DaFare, 0) = 0
				OR v.DaFare IS NOT NULL
				)
			-- @SenzaRegistrazione = 1: documenti inviati o ricevuti, non annullati, che l'azienda può registrare (trasportatore,
			-- impianto, produttore o chi organizza, D8.1) e senza una registrazione attiva collegata (D8.6)
			AND
				(
				ISNULL(@SenzaRegistrazione, 0) = 0
				OR
					(
					a.Numero IS NOT NULL
					AND ISNULL(a.Stato, '') <> 'CANCELLED'
					AND ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')) LIKE '%[TIPO]%'
					AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.Id = a.IdRegistrazione AND r.Lock < 2)
					)
				)
		ORDER BY a.DataSpedizione DESC, a.Id DESC
		OPTION (RECOMPILE);

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

-- ===== Verifica: le 9 procedure, modificate ora e con QUOTED_IDENTIFIER ON
SELECT
	Procedura = o.name,
	Modificata = o.modify_date,
	QuotedIdentifier = OBJECTPROPERTY(o.object_id, 'ExecIsQuotedIdentOn')
FROM sys.objects o
WHERE o.name IN (
	N'uspDiwassAllegatiVii_get', N'uspRifiutiRegistrazioni_del', N'uspRifiutiAutorizzazioni_get_MatchImportazione',
	N'uspRifiutiMovimenti_ins_DaAcquisizioneFormulario', N'uspRifiutiMovimenti_ins_DaAllegatoVii',
	N'uspDiwassAllegatiVii_get_Registri_SelectList', N'uspDiwassAllegatiVii_get_Operazioni_SelectList',
	N'uspDiwassAllegatiVii_get_List', N'uspDiwassAllegatiVii_get_Esportazione')
ORDER BY o.name;
GO