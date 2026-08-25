SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_ins_Etichette]
	@Id CHAR(16) = NULL,
	@Etichette VARCHAR(8000) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Etichette = NULLIF(LTRIM(RTRIM(@Etichette)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Etichette IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Etichette non può essere vuoto';
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
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul limite padre + recupero IdSede
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- @Etichette: lista di Id separati da ';'. Ristretta alle etichette della stessa
		-- sede e modulo Rifiuti, coerente col picker _get_Etichette_List.
		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiLimitiEtichette (IdLimite, IdEtichetta)
			SELECT
				@Id,
				e.Id
			FROM
				STRING_SPLIT(@Etichette, ';') s
				INNER JOIN dbo.tblEtichette e ON s.value = e.Id
			WHERE
				s.value <> ''
				AND e.IdSede = @idSede
				AND e.IdModulo = 'RIF'
				AND e.Lock = 0
				AND e.Id NOT IN (SELECT IdEtichetta FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = @Id);

			SET @returnValue = @@ROWCOUNT;
		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
GO
