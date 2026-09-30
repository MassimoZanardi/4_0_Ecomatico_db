SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_ins
	@IdRegistrazione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M, cioè
		-- tblRifiutiOperazioni.IsMateriale = 1 - vedi feedback_rentri_codice_lookup_pattern,
		-- mai confrontare IdOperazione con un letterale hardcoded)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non ha un materiale prodotto valorizzato';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non è un movimento reale: non riceve quote EoW
		IF EXISTS (SELECT 1
		FROM dbo.viewRifiutiRegistrazioniEffettive
		WHERE
			Id = @IdRegistrazione
			AND IsRettifica = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può ricevere quote EoW';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		DECLARE @dataChiusuraLotto DATE;
		DECLARE @disabilitatoLotto BIT;
		DECLARE @quantitaMaxLotto DECIMAL(18, 2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale,
			@dataChiusuraLotto = l.DataChiusura,
			@disabilitatoLotto = l.Disabilitato,
			@quantitaMaxLotto = l.QuantitaMax
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeLotto <> @idMaterialeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale della registrazione';
			GOTO BRANCH_END;
		END

		IF @dataChiusuraLotto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è chiuso, non può ricevere nuove quantità';
			GOTO BRANCH_END;
		END

		IF ISNULL(@disabilitatoLotto, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è disabilitato, non può ricevere nuove quantità';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock in ordine stabile (sempre Lotto, poi Movimento) per evitare deadlock con
			-- esecuzioni concorrenti che toccano insiemi di lotti/registrazioni sovrapposti.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = Id
			FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @IdLotto;

			DECLARE @quantitaAttribuitaLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAttribuitaLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la capacità residua del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione);
			IF ISNULL(@quantitaAttribuitaRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND IdLotto = @IdLotto
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Questo lotto è già associato alla registrazione: modificare la quantità esistente';
				GOTO BRANCH_END;
			END

			-- Pos = ordine di riempimento: se la quantita' operativa della M scende, le allocazioni si riducono
			-- partendo dall'ultimo lotto riempito (uspEoWLottiRifiutiRegistrazioni_upd_Allinea)
			INSERT dbo.tblEoWLottiRifiutiRegistrazioni (IdRegistrazione, IdLotto, Quantita, Pos)
			SELECT
				@IdRegistrazione,
				@IdLotto,
				@Quantita,
				ISNULL(MAX(Pos), 0) + 1
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE IdRegistrazione = @IdRegistrazione;

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
GO
