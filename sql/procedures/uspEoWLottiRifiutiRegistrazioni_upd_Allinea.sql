SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Magazzino EoW allineato al registro operativo (Registro > EoW > Magazzino): adegua le allocazioni EoW della
-- registrazione M @IdRegistrazione alla sua quantita' operativa (viewRifiutiRegistrazioniEffettive: ultima
-- rettifica confermata, 0 se annullata) e al suo materiale, con la regola di
-- ufnEoWLottiRifiutiRegistrazioni_get_Allineamento (riduzione dall'ultimo lotto riempito, lotti di materiale
-- diverso azzerati, nessun aumento automatico). Le allocazioni a 0 vengono rimosse.
-- SP interna, senza sessione: chiamata dentro la transazione delle SP che cambiano il valore operativo di una
-- registrazione (uspRifiutiRegistrazioni_upd, _upd_Rettifica, _upd_Annullamento, _del di una rettifica,
-- uspRifiutiFormulari_upd), che hanno gia' verificato permessi e titolarita'. Registrazioni non attive
-- (Lock >= 2: bozza o cancellata) non vengono toccate: una registrazione cancellata non conta nei lotti
-- (filtro Lock < 2 dei lettori) e mantiene le allocazioni per "Annulla cancellazione". Nessun controllo sul
-- materiale gia' scaricato dal magazzino: il registro prevale, l'eventuale anomalia resta visibile sul lotto.
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea
	@IdRegistrazione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Nessuna allocazione: niente da allineare (caso di gran lunga piu' frequente)
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLottiRifiutiRegistrazioni
		WHERE IdRegistrazione = @IdRegistrazione)
			GOTO BRANCH_END;

		DECLARE @isAttiva BIT = 0;
		DECLARE @idMateriale CHAR(2);
		DECLARE @quantita DECIMAL(18, 2);
		SELECT
			@isAttiva = 1,
			-- Materiale solo se la causale e' ancora di materiale prodotto (flag da LEFT JOIN: ISNULL)
			@idMateriale = IIF(ISNULL(o.IsMateriale, 0) = 1, r.IdMateriale, NULL),
			@quantita = ISNULL(v.Quantita, 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND v.IsRettifica = 0;

		IF @isAttiva = 0
			GOTO BRANCH_END;

		BEGIN TRANSACTION;

			DECLARE @allineamento TABLE (
				IdLotto CHAR(16) COLLATE DATABASE_DEFAULT PRIMARY KEY,
				Quantita DECIMAL(18, 2) NOT NULL,
				QuantitaNuova DECIMAL(18, 2) NOT NULL
			);

			-- Righe della registrazione bloccate fino alla fine della transazione del chiamante
			INSERT INTO @allineamento (IdLotto, Quantita, QuantitaNuova)
			SELECT
				n.IdLotto,
				n.Quantita,
				n.QuantitaNuova
			FROM
				dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento(@IdRegistrazione, @quantita, @idMateriale) n
				INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni q WITH (UPDLOCK, HOLDLOCK)
					ON q.IdRegistrazione = @IdRegistrazione
					AND q.IdLotto = n.IdLotto
			WHERE n.QuantitaNuova <> n.Quantita;

			DELETE q
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN @allineamento a ON q.IdLotto = a.IdLotto
			WHERE
				q.IdRegistrazione = @IdRegistrazione
				AND a.QuantitaNuova <= 0;

			UPDATE q
			SET q.Quantita = a.QuantitaNuova
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN @allineamento a ON q.IdLotto = a.IdLotto
			WHERE
				q.IdRegistrazione = @IdRegistrazione
				AND a.QuantitaNuova > 0;

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
END;
GO
