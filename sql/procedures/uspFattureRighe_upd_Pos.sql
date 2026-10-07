SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sposta su (@Direzione = -1) o giù (@Direzione = 1) una riga della fattura. Prima dello scambio le
-- righe vengono rinumerate 1..n nell'ordine corrente, così i buchi lasciati dalle righe tolte non
-- contano. Sulla prima riga "su" e sull'ultima "giù" non fanno nulla.
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_upd_Pos
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La fattura della riga deve esistere (in bozza o attiva, non eliminata), appartenere
		-- all'azienda interna corrente della sessione e non essere in sola lettura
		DECLARE @idFattura CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idFattura = f.Id,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		DECLARE @righe TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			PosAttuale INT NULL,
			PosNuova INT NOT NULL
		);

		BEGIN TRANSACTION;
			-- Stesso ordinamento di uspFattureRighe_get_List
			INSERT @righe (Id, PosAttuale, PosNuova)
			SELECT
				Id,
				Pos,
				ROW_NUMBER() OVER (ORDER BY ISNULL(Pos, 0), Id)
			FROM dbo.tblFattureRighe WITH (UPDLOCK, HOLDLOCK)
			WHERE IdFattura = @idFattura;

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
				dbo.tblFattureRighe r
				INNER JOIN @righe t ON r.Id = t.Id
			WHERE ISNULL(t.PosAttuale, -1) <> t.PosNuova;
		COMMIT TRANSACTION;

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
