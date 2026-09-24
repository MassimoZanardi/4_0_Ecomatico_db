SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_esegui_Criterio
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

		-- La riga deve esistere, appartenere a un movimento non eliminato (bozza o
		-- già confermato) e all'azienda interna corrente della sessione
		DECLARE @idSedeRiga CHAR(16), @idArticoloRiga CHAR(16), @quantitaRiga DECIMAL(18, 2), @idCriterio CHAR(1), @idOperazione CHAR(1);
		SELECT
			@idSedeRiga = r.IdSede,
			@idArticoloRiga = r.IdArticolo,
			@quantitaRiga = r.Quantita,
			@idCriterio = r.IdCriterio,
			@idOperazione = m.IdOperazione
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND m.Lock IN (0, 2);

		IF @idSedeRiga IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END
		IF @idOperazione <> 'S'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il criterio automatico si applica solo alle righe di scarico';
			GOTO BRANCH_END;
		END
		IF @idCriterio IS NULL OR @idCriterio NOT IN ('F', 'L', 'E')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La riga non ha un criterio di scarico automatico valido (F/L/E)';
			GOTO BRANCH_END;
		END

		DECLARE @allocataRiga DECIMAL(18, 2) = ISNULL((SELECT SUM(Quantita) FROM dbo.tblMagazziniMovimentiRigheLotti WHERE Id = @Id), 0);
		DECLARE @daAllocare DECIMAL(18, 2) = @quantitaRiga - @allocataRiga;

		IF @daAllocare <= 0
		BEGIN
			SET @returnMessage = 'La riga è già completamente allocata';
			SELECT ReturnValue = @returnValue, ReturnMessage = @returnMessage;
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lotti candidati: stessa Sede+Articolo della riga, attivi, non disabilitati,
			-- non chiusi, con disponibilità > 0. Lock di riga (UPDLOCK/HOLDLOCK) sulle
			-- righe di allocazione già presenti, per serializzare eventuali esecuzioni
			-- concorrenti sugli stessi lotti.
			CREATE TABLE #Candidati (
				RowNum INT IDENTITY(1, 1) PRIMARY KEY,
				IdLotto CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
				Disponibile DECIMAL(18, 2) NOT NULL
			);

			INSERT INTO #Candidati (IdLotto, Disponibile)
			SELECT
				l.Id,
				ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0)
			FROM
				dbo.tblMagazziniLotti l
				OUTER APPLY (
					SELECT
						Caricato = SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl.Quantita ELSE 0 END),
						Scaricato = SUM(CASE WHEN mv.IdOperazione = 'S' THEN rl.Quantita ELSE 0 END)
					FROM
						dbo.tblMagazziniMovimentiRigheLotti rl WITH (UPDLOCK, HOLDLOCK)
						INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
						INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
					WHERE
						rl.IdLotto = l.Id
						AND r.Lock = 0
						AND mv.Lock = 0
				) q
			WHERE
				l.IdSede = @idSedeRiga
				AND l.IdArticolo = @idArticoloRiga
				AND l.Lock = 0
				AND ISNULL(l.Disabilitato, 0) = 0
				AND (l.DataChiusura IS NULL OR l.DataChiusura >= CAST(GETDATE() AS DATE))
				AND (ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0)) > 0
			ORDER BY
				CASE WHEN @idCriterio = 'F' THEN l.DataApertura END ASC,
				CASE WHEN @idCriterio = 'L' THEN l.DataApertura END DESC,
				CASE WHEN @idCriterio = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC;

			-- Allocazione greedy, lotto per lotto, nell'ordine determinato dal criterio
			DECLARE @rowNum INT = 1, @maxRow INT = ISNULL((SELECT MAX(RowNum) FROM #Candidati), 0);
			DECLARE @idLottoCorrente CHAR(16), @dispCorrente DECIMAL(18, 2), @allocaQui DECIMAL(18, 2);

			WHILE @daAllocare > 0 AND @rowNum <= @maxRow
			BEGIN
				SELECT @idLottoCorrente = IdLotto, @dispCorrente = Disponibile FROM #Candidati WHERE RowNum = @rowNum;

				SET @allocaQui = CASE WHEN @dispCorrente < @daAllocare THEN @dispCorrente ELSE @daAllocare END;

				IF @allocaQui > 0
				BEGIN
					IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheLotti WHERE Id = @Id AND IdLotto = @idLottoCorrente)
						UPDATE dbo.tblMagazziniMovimentiRigheLotti
						SET Quantita = Quantita + @allocaQui
						WHERE Id = @Id AND IdLotto = @idLottoCorrente;
					ELSE
						INSERT dbo.tblMagazziniMovimentiRigheLotti (Id, IdLotto, Quantita)
						VALUES (@Id, @idLottoCorrente, @allocaQui);

					SET @daAllocare -= @allocaQui;
				END

				SET @rowNum += 1;
			END

			IF @daAllocare > 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Disponibilità complessiva insufficiente sui lotti candidati (mancano ' + FORMAT(@daAllocare, 'N2', 'it-IT') + ')';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
