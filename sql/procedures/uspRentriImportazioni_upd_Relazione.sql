SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: l'utente corregge le quantità attribuite da una registrazione (padre) alle sue associate
-- (figli che RENTRI riporta: non se ne aggiungono altri), oppure ripristina la proposta FIFO (@Ripristina = 1).
-- @Quantita: array JSON [{ "figlioAnno": 2025, "figlioProgressivo": 12, "quantita": 10.5 }, ...].
-- Le quantità corrette restano anche rileggendo l'analisi (IsModificata); i controlli (disponibilità, somma uguale
-- alla quantità della registrazione) sono quelli dell'analisi, rilanciata subito dopo.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_upd_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@PadreAnno SMALLINT = NULL,
	@PadreProgressivo INT = NULL,
	@Quantita NVARCHAR(MAX) = NULL,
	@Ripristina BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Ripristina = ISNULL(@Ripristina, 0);

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
		IF @PadreAnno IS NULL OR @PadreProgressivo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @PadreAnno/@PadreProgressivo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Ripristina = 0 AND (@Quantita IS NULL OR ISJSON(@Quantita) = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Quantita non è valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @stato CHAR(1);
		SELECT @stato = m.Stato
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE m.Id = @Id;

		IF @stato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END
		IF @stato <> 'P'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importazione è già stata eseguita';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriImportazioniRelazioni
			WHERE IdImportazione = @Id AND PadreAnno = @PadreAnno AND PadreProgressivo = @PadreProgressivo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non ha registrazioni associate';
			GOTO BRANCH_END;
		END

		CREATE TABLE #quantita (FiglioAnno SMALLINT, FiglioProgressivo INT, Quantita DECIMAL(18, 4), Testo NVARCHAR(40));

		IF @Ripristina = 0
		BEGIN
			INSERT #quantita (FiglioAnno, FiglioProgressivo, Quantita, Testo)
			SELECT j.FiglioAnno, j.FiglioProgressivo, TRY_CONVERT(DECIMAL(18, 4), j.Testo), j.Testo
			FROM
				OPENJSON(@Quantita)
				WITH (
					FiglioAnno SMALLINT '$.figlioAnno',
					FiglioProgressivo INT '$.figlioProgressivo',
					Testo NVARCHAR(40) '$.quantita'
				) j;

			IF EXISTS (SELECT 1 FROM #quantita WHERE Quantita IS NULL OR Quantita < 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare quantità non negative';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM #quantita WHERE Quantita <> ROUND(Quantita, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Le quantità possono avere al massimo 2 decimali';
				GOTO BRANCH_END;
			END
			IF EXISTS (
				SELECT 1
				FROM #quantita q
				WHERE NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE
						l.IdImportazione = @Id AND l.PadreAnno = @PadreAnno AND l.PadreProgressivo = @PadreProgressivo
						AND l.FiglioAnno = q.FiglioAnno AND l.FiglioProgressivo = q.FiglioProgressivo))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Si possono indicare quantità solo per le registrazioni associate su RENTRI';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;

			IF @Ripristina = 1
				UPDATE dbo.tblRentriImportazioniRelazioni
				SET IsModificata = 0
				WHERE IdImportazione = @Id AND PadreAnno = @PadreAnno AND PadreProgressivo = @PadreProgressivo;
			ELSE
				UPDATE l
				SET
					Quantita = ISNULL(q.Quantita, l.Quantita),
					IsModificata = 1
				FROM
					dbo.tblRentriImportazioniRelazioni l
					LEFT JOIN #quantita q ON q.FiglioAnno = l.FiglioAnno AND q.FiglioProgressivo = l.FiglioProgressivo
				WHERE l.IdImportazione = @Id AND l.PadreAnno = @PadreAnno AND l.PadreProgressivo = @PadreProgressivo;

		COMMIT TRANSACTION;

		EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @Id;

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
