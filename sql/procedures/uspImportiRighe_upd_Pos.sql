SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sposta su (@Direzione = -1) o giù (@Direzione = 1) una riga dell'importo. Prima dello scambio le righe
-- vengono rinumerate 1..n nell'ordine corrente, così i buchi lasciati dalle righe tolte non contano. Sulla
-- prima riga "su" e sull'ultima "giù" non fanno nulla.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_upd_Pos
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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo della riga deve esistere (in bozza o attivo), appartenere all'azienda interna corrente
		-- della sessione e il suo modulo deve essere attivo sul dominio
		DECLARE @idImporto CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idImporto = i.Id,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImportiRighe g
			INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			g.Id = @Id
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idImporto IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		DECLARE @righe TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			PosAttuale INT NULL,
			PosNuova INT NOT NULL
		);

		BEGIN TRANSACTION;
			-- Stesso ordinamento di uspImportiRighe_get_List
			INSERT @righe (Id, PosAttuale, PosNuova)
			SELECT
				Id,
				Pos,
				ROW_NUMBER() OVER (ORDER BY ISNULL(Pos, 0), Id)
			FROM dbo.tblImportiRighe WITH (UPDLOCK, HOLDLOCK)
			WHERE IdImporto = @idImporto;

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

			UPDATE g
			SET Pos = t.PosNuova
			FROM
				dbo.tblImportiRighe g
				INNER JOIN @righe t ON g.Id = t.Id
			WHERE ISNULL(t.PosAttuale, -1) <> t.PosNuova;
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
