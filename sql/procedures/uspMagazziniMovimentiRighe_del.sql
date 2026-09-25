SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_del
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
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita è trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- La riga è rimovibile mentre il movimento è in bozza o già confermato (non
		-- se eliminato, Lock = 4): come le Registrazioni Rifiuti, la conferma non
		-- congela la riga, salvo un vincolo reale verificato più sotto.
		DECLARE @lockMovimento INT, @idOperazioneMovimento CHAR(1);
		SELECT
			@lockMovimento = c.Lock,
			@idOperazioneMovimento = c.IdOperazione
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti c ON r.IdMovimento = c.Id
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @lockMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Vincolo reale (come le Registrazioni Rifiuti): una riga di carico non è
			-- rimovibile se è già relazionata a uno scarico non eliminato (la giacenza
			-- consumata resterebbe senza origine). Una riga di scarico si può sempre
			-- rimuovere: libera solo disponibilità, non ne consuma.
			IF @idOperazioneMovimento = 'C' AND EXISTS (
				SELECT 1
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel WITH (UPDLOCK, HOLDLOCK)
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel.Id = @Id
					AND mp.Lock IN (0, 2)
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non è possibile togliere la riga: la quantità è già stata utilizzata da uno scarico successivo';
				GOTO BRANCH_END;
			END

			-- Relazioni della riga, in entrambi i versi: come scarico (IdParent) e, per un
			-- carico, quelle residue di scarichi eliminati (Lock = 4, non più attive)
			DELETE dbo.tblMagazziniMovimentiRigheRelazioni
			WHERE
				IdParent = @Id
				OR Id = @Id;

			DELETE dbo.tblMagazziniMovimentiRighe
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
