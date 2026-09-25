SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheRelazioni_ins
	@IdParent CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@Tutte BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Tutte = ISNULL(@Tutte, 0);

		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND @Tutte = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il carico da associare';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
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

		-- Riga di scarico (padre): azienda interna corrente della sessione, movimento non
		-- eliminato. L'associazione manuale vale solo per il criterio Manuale (IdCriterio
		-- NULL): con FIFO/LIFO/FEFO le relazioni le costruisce uspMagazziniMovimenti_upd.
		DECLARE @idSede CHAR(16), @idArticolo CHAR(16), @idCriterio CHAR(1), @data DATE, @numero INT;
		SELECT
			@idSede = r.IdSede,
			@idArticolo = r.IdArticolo,
			@idCriterio = r.IdCriterio,
			@data = ISNULL(m.[Data], CAST(GETDATE() AS DATE)),
			@numero = m.Numero
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			r.Id = @IdParent
			AND e.Id = @IdSessione
			AND m.IdOperazione = 'S'
			AND m.Lock IN (0, 2);

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga di scarico non esiste';
			GOTO BRANCH_END;
		END
		IF @idCriterio IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con un criterio di scarico automatico i carichi vengono associati al salvataggio del movimento';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			DECLARE @pos INT;
			SELECT @pos = ISNULL(MAX(Pos), -1)
			FROM dbo.tblMagazziniMovimentiRigheRelazioni WITH (UPDLOCK, HOLDLOCK)
			WHERE IdParent = @IdParent;

			-- Righe di carico associabili (stessi filtri di
			-- uspMagazziniMovimentiRighe_get_CarichiDaAssociare_List), in ordine cronologico;
			-- la quantità viene distribuita al salvataggio del movimento, in ordine di Pos
			INSERT dbo.tblMagazziniMovimentiRigheRelazioni (Id, IdParent, Quantita, Pos)
			SELECT
				rc.Id,
				@IdParent,
				0,
				@pos + ROW_NUMBER() OVER (ORDER BY mc.[Data], mc.Numero)
			FROM
				dbo.tblMagazziniMovimentiRighe rc
				INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
				OUTER APPLY (
					SELECT Consumata = SUM(rel.Quantita)
					FROM
						dbo.tblMagazziniMovimentiRigheRelazioni rel
						INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
						INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
					WHERE
						rel.Id = rc.Id
						AND mp.Lock IN (0, 2)
				) c
			WHERE
				(@Tutte = 1 OR rc.Id = @Id)
				AND mc.IdOperazione = 'C'
				AND mc.Lock = 0
				AND rc.Lock = 0
				AND rc.IdSede = @idSede
				AND rc.IdArticolo = @idArticolo
				AND (
					mc.[Data] < @data
					OR (mc.[Data] = @data AND (@numero IS NULL OR mc.Numero < @numero))
				)
				AND rc.Quantita - ISNULL(c.Consumata, 0) > 0
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheRelazioni x WHERE x.Id = rc.Id AND x.IdParent = @IdParent);

			SET @returnValue = @@ROWCOUNT;

			IF @returnValue = 0 AND @Tutte = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Il carico selezionato non è associabile a questa riga di scarico';
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
