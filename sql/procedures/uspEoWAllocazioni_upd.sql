SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdAllocazioneTipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAllocazioneTipo = NULLIF(LTRIM(RTRIM(@IdAllocazioneTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);

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
		IF @IdAllocazioneTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAllocazioneTipo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale dell'allocazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblEoWAllocazioniTipi WHERE Id = @IdAllocazioneTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di allocazione indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se l'allocazione ha già lotti collegati, anche se non
		-- ancora salvata (uspEoWAllocazioni_ins_Lotto memorizza il tipo con il primo lotto)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id = @Id
				AND IdAllocazioneTipo <> @IdAllocazioneTipo
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo di un''allocazione con lotti associati';
			GOTO BRANCH_END;
		END

		-- I lotti presenti devono rispettare il tipo (stessi vincoli di uspEoWAllocazioni_ins_Lotto):
		-- intercetta anche lotti aggiunti quando il tipo non era ancora salvato
		IF @IdAllocazioneTipo = 'U' AND (SELECT COUNT(*) FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id) > 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @IdAllocazioneTipo = 'P' AND (
			EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE
					IdAllocazione = @Id
					AND (Valore IS NULL OR Valore <= 0 OR Valore > 100)
			)
			OR (SELECT ISNULL(SUM(Valore), 0) FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id) > 100
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le percentuali dei lotti devono essere maggiori di zero e la loro somma non può superare 100';
			GOTO BRANCH_END;
		END

		IF @IdAllocazioneTipo = 'C' AND (
			EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE
					IdAllocazione = @Id
					AND (Valore IS NULL OR Valore <= 0)
			)
			OR EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE IdAllocazione = @Id
				GROUP BY Valore
				HAVING COUNT(*) > 1
			)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ogni lotto deve avere una priorità diversa: togliere e aggiungere di nuovo i lotti con la stessa priorità';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra allocazione attiva con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra allocazione con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWAllocazioni
			SET
				Lock = 0,
				IdAllocazioneTipo = @IdAllocazioneTipo,
				Nome = @Nome
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allocazione non trovata o già eliminata';
				GOTO BRANCH_END;
			END
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
