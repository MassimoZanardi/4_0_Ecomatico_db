SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Anteprima per la modale di conferma "La modifica operativa andrà a modificare le quantità già allocate":
-- elenca, lotto per lotto, come cambierebbero le allocazioni EoW della registrazione M coinvolta se si
-- salvasse (@Azione = 'U') o cancellasse (@Azione = 'D') la registrazione @Id, con la stessa regola
-- dell'allineamento (ufnEoWLottiRifiutiRegistrazioni_get_Allineamento, applicata al salvataggio da
-- uspEoWLottiRifiutiRegistrazioni_upd_Allinea). Nessuna riga = nessuna allocazione cambia, niente modale.
-- - @Id registrazione normale: 'U' con la quantita' (@Quantita) e il materiale (@IdMateriale, NULL se la
--   causale non e' di materiale prodotto) del form; 'D' = la M cancellata non conta piu' nei lotti
--   (allocazioni conservate per "Annulla cancellazione", QuantitaNuova = 0 indica che non contano).
-- - @Id rettifica: la M coinvolta e' l'originale; 'U' = quantita' operativa dopo il salvataggio (correzione
--   operativa: @Quantita; annullamento operativo: 0; non operativa: invariata, stessa decisione di
--   ufnRifiutiRegistrazioni_get_RettificaOperativa); 'D' = l'originale torna ai valori operativi senza questa
--   rettifica (una bozza mai confermata non ha mai contato: nessun effetto).
-- Scaricata/Giacenza dal saldo del lotto (ufnEoWLotti_get_Saldo); IsSottoScaricato = dopo la modifica il
-- lotto avrebbe meno prodotto di quanto gia' scaricato dal magazzino (anomalia, mai bloccante).
-- Solo con il modulo EoW attivo; permesso della funzione Registrazioni (RRG): la modale compare a chi salva
-- la registrazione, anche senza accesso alla gestione EoW.
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_get_Allineamento_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Azione CHAR(1) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Azione = NULLIF(LTRIM(RTRIM(@Azione)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = ISNULL(NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), ''), 'KG');

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
		IF @Azione IS NULL OR @Azione NOT IN ('U', 'D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Azione deve essere U (salvataggio) o D (cancellazione)';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarita' della registrazione
		DECLARE @lock TINYINT;
		SELECT @lock = ISNULL(r.Lock, 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @Id;

		IF @lock IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRegistrazioneM CHAR(16);
		DECLARE @quantitaNuova DECIMAL(18, 2);
		DECLARE @idMaterialeNuovo CHAR(2);

		IF dbo.ufnModuli_get_IsAttivoBySessione('EOW', @IdSessione) = 1
		BEGIN
			DECLARE @idOriginale CHAR(16);
			DECLARE @isAnnullamento BIT;
			SELECT
				@idOriginale = Id,
				@isAnnullamento = ISNULL(Annullata, 0)
			FROM dbo.tblRentriRegistrazioniRettifiche
			WHERE IdRettifica = @Id;

			IF @idOriginale IS NULL
			BEGIN
				-- Registrazione normale: e' essa stessa la M
				SET @idRegistrazioneM = @Id;
				IF @Azione = 'U'
					SELECT
						@quantitaNuova = ISNULL(@Quantita, 0),
						@idMaterialeNuovo = @IdMateriale;
				ELSE
					SELECT
						@quantitaNuova = 0,
						@idMaterialeNuovo = r.IdMateriale
					FROM dbo.tblRifiutiRegistrazioni r
					WHERE r.Id = @Id;
			END
			ELSE
			BEGIN
				-- Rettifica: la M e' l'originale, il materiale operativo resta quello dell'originale
				SET @idRegistrazioneM = @idOriginale;
				SELECT @idMaterialeNuovo = IIF(ISNULL(o.IsMateriale, 0) = 1, r.IdMateriale, NULL)
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				WHERE r.Id = @idOriginale;

				-- Valori operativi senza questa rettifica (ultima altra rettifica confermata o originale)
				DECLARE @precIdEer CHAR(6), @precIdStatoFisico CHAR(1), @precIdUnitaMisura CHAR(2), @precQuantita DECIMAL(18, 2);
				SELECT
					@precIdEer = IdEer,
					@precIdStatoFisico = IdStatoFisico,
					@precIdUnitaMisura = IdUnitaMisura,
					@precQuantita = Quantita
				FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);

				IF @Azione = 'D'
					-- Cancellando una rettifica confermata l'originale torna ai valori precedenti; una bozza
					-- (Lock 2) non ha mai contato: valori operativi invariati
					SET @quantitaNuova = IIF(@lock = 0, @precQuantita, (SELECT Quantita
					FROM dbo.viewRifiutiRegistrazioniEffettive
					WHERE Id = @idOriginale));
				ELSE IF @isAnnullamento = 1
					SELECT @quantitaNuova = IIF(IsOperativa = 1, 0, Quantita)
					FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, NULL, NULL, NULL, NULL);
				ELSE
				BEGIN
					-- Correzione: per il materiale EER/stato fisico/UM non sono modificabili (stessa
					-- normalizzazione di uspRifiutiRegistrazioni_get_RettificaIsOperativa)
					IF @idMaterialeNuovo IS NOT NULL
						SELECT
							@IdEer = @precIdEer,
							@IdStatoFisico = @precIdStatoFisico,
							@IdUnitaMisura = 'KG';

					SELECT @quantitaNuova = IIF(IsOperativa = 1, ISNULL(@Quantita, 0), Quantita)
					FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@Id, @IdEer, @IdStatoFisico, @IdUnitaMisura, @Quantita);
				END
			END

			-- Solo registrazioni M attive (una cancellata o in bozza non conta nei lotti)
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @idRegistrazioneM
				AND Lock < 2
			)
				SET @idRegistrazioneM = NULL;
		END

		SELECT
			n.IdLotto,
			LottoNome = l.Nome,
			n.Quantita,
			n.QuantitaNuova,
			s.Scaricata,
			s.Giacenza,
			GiacenzaNuova = s.Giacenza - (n.Quantita - n.QuantitaNuova),
			IsSottoScaricato = CAST(IIF(s.Giacenza - (n.Quantita - n.QuantitaNuova) < 0, 1, 0) AS BIT)
		FROM
			dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento(@idRegistrazioneM, @quantitaNuova, @idMaterialeNuovo) n
			INNER JOIN dbo.tblEoWLotti l ON n.IdLotto = l.Id
			CROSS APPLY dbo.ufnEoWLotti_get_Saldo(n.IdLotto) s
		WHERE
			@idRegistrazioneM IS NOT NULL
			-- Modale solo se almeno un'allocazione cambia; in quel caso tutte le allocazioni, per la fotografia
			AND EXISTS (SELECT 1 FROM dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento(@idRegistrazioneM, @quantitaNuova, @idMaterialeNuovo) x WHERE x.QuantitaNuova <> x.Quantita)
		ORDER BY l.Nome;

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
