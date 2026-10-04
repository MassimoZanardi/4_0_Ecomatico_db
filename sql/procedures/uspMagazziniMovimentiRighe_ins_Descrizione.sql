SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Riga descrittiva: solo testo libero, da stampare sul DDT nella posizione scelta. Ammessa solo
-- sui movimenti con un DDT associato; non ha articolo, lotto, criterio né quantità, quindi non
-- entra in giacenze e relazioni carico/scarico (tutte le letture filtrano per articolo o lotto).
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_ins_Descrizione
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Descrizione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la descrizione';
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

		-- Il movimento deve esistere (in bozza o già confermato, non eliminato) e appartenere
		-- all'azienda interna corrente della sessione; la riga eredita il Lock del movimento
		DECLARE @lockMovimento INT;
		SELECT @lockMovimento = c.Lock
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @lockMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END

		-- Solo con un DDT associato: la riga prende la sede interna del DDT, come tutte le altre
		DECLARE @idSede CHAR(16);
		SELECT @idSede = IdSede
		FROM dbo.tblMagazziniDdt
		WHERE IdMovimento = @IdMovimento;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le righe descrittive si possono inserire solo in un movimento con DDT';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			-- Posizione: in coda alle righe del movimento, unica tra righe articolo/descrizione e righe EoW
			DECLARE @pos INT;
			SELECT @pos = ISNULL(MAX(x.Pos), 0) + 1
			FROM
				(
					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRighe
					WHERE IdMovimento = @IdMovimento

					UNION ALL

					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW
					WHERE IdMovimento = @IdMovimento
				) x;

			INSERT dbo.tblMagazziniMovimentiRighe (Id, IdMovimento, IdSede, Lock, Descrizione, Pos)
			VALUES (@returnId, @IdMovimento, @idSede, @lockMovimento, @Descrizione, @pos);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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
