SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_ins
	@IdMovimento CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede interna da cui parte la merce';
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

		-- Il movimento deve esistere, essere ancora in bozza (Lock = 2) e appartenere
		-- all'azienda interna corrente della sessione. Il DDT si associa solo mentre il
		-- movimento è ancora in bozza, così il vincolo "righe tutte alla stessa sede
		-- interna" vale fin dalla prima riga inserita dopo la creazione del DDT.
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione
			AND c.Lock = 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non è più in bozza';
			GOTO BRANCH_END;
		END

		-- La sede interna deve appartenere alla stessa azienda del movimento
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @IdSede
				AND (Id = @idAzienda OR IdParent = @idAzienda)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede interna indicata non appartiene all''azienda del movimento';
			GOTO BRANCH_END;
		END

		-- Al massimo un DDT per movimento (nessun vincolo UNIQUE nello schema reale)
		IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMovimento = @IdMovimento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il movimento ha già un DDT associato';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblMagazziniDdt (Id, IdMovimento, IdSede, Lock)
			VALUES (@returnId, @IdMovimento, @IdSede, 2);
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
