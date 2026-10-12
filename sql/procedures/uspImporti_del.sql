SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancella un importo (rifiuti, magazzino o servizi) dell'azienda interna corrente della sessione.
-- Importo attivo: cancellazione con ripristino (Lock 4), le righe restano sull'importo cancellato. Bloccata se
-- l'importo è associato a un contratto o a un'offerta: va prima tolto da lì.
-- Importo in bozza: eliminato con le sue righe.
CREATE OR ALTER PROCEDURE dbo.uspImporti_del
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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblImporti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità) e che il modulo dell'importo sia attivo sul dominio
		DECLARE @lock INT;
		DECLARE @idModulo CHAR(3);
		SELECT
			@lock = i.Lock,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @Id
			AND e.Id = @IdSessione;

		IF @lock IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: importo attivo (Lock = 0) → soft delete ──────────────────
		IF @lock = 0
		BEGIN
			-- Un importo associato a un contratto o a un'offerta non cancellati resta
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblOfferteContrattiImporti ci
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
				WHERE
					ci.IdImporto = @Id
					AND oc.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un importo associato a un contratto o a un''offerta non può essere cancellato: toglierlo prima dal contratto';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblImporti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Importo non trovato o già eliminato';
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

		-- ── CASO 2: importo in bozza (Lock = 2) → hard delete, con le sue righe ──
		ELSE IF @lock = 2
		BEGIN
			DECLARE @righe TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

			BEGIN TRANSACTION;
				INSERT @righe (Id)
				SELECT Id
				FROM dbo.tblImportiRighe
				WHERE IdImporto = @Id;

				DELETE d
				FROM dbo.tblImportiRigheDettagli d
				INNER JOIN @righe t ON d.Id = t.Id;
				DELETE dbo.tblImportiRighe
				WHERE IdImporto = @Id;
				DELETE l
				FROM dbo.tblIdLog l
				INNER JOIN @righe t ON l.Id = t.Id;
				DELETE x
				FROM dbo.tblId x
				INNER JOIN @righe t ON x.Id = t.Id;

				DELETE dbo.tblOfferteContrattiImporti
				WHERE IdImporto = @Id;
				DELETE dbo.tblImportiRifiuti
				WHERE Id = @Id;
				DELETE dbo.tblImportiMagazzino
				WHERE Id = @Id;
				DELETE dbo.tblImportiServizi
				WHERE Id = @Id;
				DELETE dbo.tblImporti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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
