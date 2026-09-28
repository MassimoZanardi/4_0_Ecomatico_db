CREATE OR ALTER PROCEDURE [dbo].[uspTipi_ins_Proprieta]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipoDato CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipoDato = NULLIF(LTRIM(RTRIM(@IdTipoDato)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
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
		IF @IdTipoDato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdTipoDato non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		-- Trova la prima proprietà disponibile del tipo dato non ancora usata
		DECLARE @idProprieta CHAR(3);
		SELECT TOP 1 @idProprieta = Id
		FROM dbo.tblProprieta
		WHERE
			IdTipoDato = @IdTipoDato
			AND Id NOT IN ( SELECT IdProprieta FROM dbo.tblTipiProprieta WHERE Id = @Id AND Lock = 0 )
		ORDER BY Id;
		IF @idProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Proprietà esaurite per il tipo di dato indicato';
			GOTO BRANCH_END;
		END
		IF EXISTS (
			SELECT 1
			FROM dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND IdProprieta <> @idProprieta
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra proprietà con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END
		-- Posizione = max corrente + 1, oppure 0 se prima proprietà
		DECLARE @pos INT = (
			SELECT MAX(Pos)
			FROM dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND Lock = 0
		);
		BEGIN TRANSACTION;
			INSERT INTO dbo.tblTipiProprieta (Id, IdProprieta, Nome, Pos, Lock)
			VALUES (@Id, @idProprieta, @Nome, ISNULL(@pos + 1, 0), 0);
		COMMIT TRANSACTION;
		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';
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
		THROW 50001, @returnMessage, 1
	END
END;
