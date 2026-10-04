SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sposta su (@Direzione = -1) o giù (@Direzione = 1) una riga del movimento. La posizione è unica
-- tra tblMagazziniMovimentiRighe (articoli e descrizioni) e tblMagazziniMovimentiRigheEoW
-- (materiali): @Id può essere una riga dell'una o dell'altra tabella. Prima dello scambio le
-- righe vengono rinumerate 1..n nell'ordine corrente, così Pos mancanti (righe precedenti
-- all'introduzione di Pos) o con buchi (righe tolte) non contano. Sulla prima riga "su" e
-- sull'ultima "giù" non fanno nulla.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_upd_Pos
	@Id CHAR(16) = NULL,
	@Direzione SMALLINT = NULL,
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
		IF @Direzione IS NULL OR @Direzione NOT IN (-1, 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Direzione deve essere -1 (su) o 1 (giù)';
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

		DECLARE @idMovimento CHAR(16);
		SELECT @idMovimento = IdMovimento
		FROM dbo.tblMagazziniMovimentiRighe
		WHERE Id = @Id;

		IF @idMovimento IS NULL
		BEGIN
			SELECT @idMovimento = IdMovimento
			FROM dbo.tblMagazziniMovimentiRigheEoW
			WHERE Id = @Id;
		END

		-- Il movimento della riga deve esistere (in bozza o già confermato, non eliminato) e
		-- appartenere all'azienda interna corrente della sessione
		IF @idMovimento IS NULL OR NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @idMovimento
				AND e.Id = @IdSessione
				AND c.Lock IN (0, 2)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		DECLARE @righe TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IsEoW BIT NOT NULL,
			PosAttuale INT NULL,
			PosNuova INT NOT NULL
		);

		BEGIN TRANSACTION;
			-- Stesso ordinamento delle _get_List (Pos NULL per prime, poi Id), a parità le righe EoW dopo
			INSERT @righe (Id, IsEoW, PosAttuale, PosNuova)
			SELECT
				x.Id,
				x.IsEoW,
				x.Pos,
				ROW_NUMBER() OVER (ORDER BY ISNULL(x.Pos, 0), x.IsEoW, x.Id)
			FROM
				(
					SELECT
						Id,
						IsEoW = CAST(0 AS BIT),
						Pos
					FROM dbo.tblMagazziniMovimentiRighe WITH (UPDLOCK, HOLDLOCK)
					WHERE IdMovimento = @idMovimento

					UNION ALL

					SELECT
						Id,
						IsEoW = CAST(1 AS BIT),
						Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW WITH (UPDLOCK, HOLDLOCK)
					WHERE IdMovimento = @idMovimento
				) x;

			DECLARE @pos INT, @posAltra INT;
			SELECT @pos = PosNuova
			FROM @righe
			WHERE Id = @Id;
			SET @posAltra = @pos + @Direzione;

			IF EXISTS (SELECT 1 FROM @righe WHERE PosNuova = @posAltra)
			BEGIN
				UPDATE @righe
				SET PosNuova = IIF(Id = @Id, @posAltra, @pos)
				WHERE PosNuova IN (@pos, @posAltra);
			END

			UPDATE r
			SET Pos = t.PosNuova
			FROM
				dbo.tblMagazziniMovimentiRighe r
				INNER JOIN @righe t ON r.Id = t.Id
			WHERE
				t.IsEoW = 0
				AND ISNULL(t.PosAttuale, -1) <> t.PosNuova;

			UPDATE r
			SET Pos = t.PosNuova
			FROM
				dbo.tblMagazziniMovimentiRigheEoW r
				INNER JOIN @righe t ON r.Id = t.Id
			WHERE
				t.IsEoW = 1
				AND ISNULL(t.PosAttuale, -1) <> t.PosNuova;
		COMMIT TRANSACTION;

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
