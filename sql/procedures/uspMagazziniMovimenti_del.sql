SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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

		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Fase 1/2: nessun DDT ancora collegabile al movimento, nessun controllo aggiuntivo
		DECLARE @lock INT = (SELECT Lock FROM dbo.tblMagazziniMovimenti WHERE Id = @Id);

		-- ── CASO 1: movimento attivo (Lock = 0) → soft delete ────────────────
		-- Un movimento soft-eliminato (Lock = 4) è automaticamente escluso dal calcolo
		-- delle giacenze (che filtrano sempre su Movimento.Lock = 0): la cancellazione
		-- "disfa" retroattivamente e in modo pulito il suo effetto sullo stock.
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;
				-- Un carico le cui righe sono già relazionate a scarichi non eliminati non è
				-- eliminabile: la giacenza consumata resterebbe senza origine (come
				-- uspMagazziniMovimentiRighe_del). Le relazioni di uno scarico eliminato restano
				-- in tabella ma non contano più (filtro sul Lock del movimento di scarico).
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimentiRigheRelazioni rel WITH (UPDLOCK, HOLDLOCK) ON rel.Id = rc.Id
						INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
						INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
					WHERE
						rc.IdMovimento = @Id
						AND mp.Lock IN (0, 2)
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il movimento non è eliminabile: le quantità caricate sono già state utilizzate da scarichi successivi';
					GOTO BRANCH_END;
				END

				UPDATE dbo.tblMagazziniMovimenti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Movimento non trovato o già eliminato';
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

		-- ── CASO 2: movimento in bozza (Lock = 2) → hard delete a cascata ────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				-- Righe tradizionali + relative relazioni carico/scarico (una bozza di carico
				-- non è mai candidata agli scarichi, ma si puliscono entrambi i versi per le FK)
				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
				INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.IdParent = r.Id OR rel.Id = r.Id
				WHERE r.IdMovimento = @Id;

				DELETE dbo.tblMagazziniMovimentiRighe
				WHERE IdMovimento = @Id;

				-- Righe EoW + relative ripartizioni sui lotti EoW (IdMovimento non ha FK:
				-- il join resta comunque valido, solo non vincolato a livello DB)
				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
				INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
				WHERE re.IdMovimento = @Id;

				DELETE dbo.tblMagazziniMovimentiRigheEoW
				WHERE IdMovimento = @Id;

				-- DDT eventualmente associato (0..1, nessun vincolo UNIQUE a livello DB)
				DELETE dbo.tblMagazziniDdt
				WHERE IdMovimento = @Id;

				DELETE dbo.tblMagazziniMovimenti
				WHERE Id = @Id;

				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il movimento è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
