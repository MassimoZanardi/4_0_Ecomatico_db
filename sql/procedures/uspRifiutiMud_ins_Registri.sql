SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMud_ins_Registri]
	@Id CHAR(16) = NULL,
	@Registri VARCHAR(8000) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Registri = NULLIF(LTRIM(RTRIM(@Registri)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Registri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Registri non può essere vuoto';
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
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla dichiarazione padre (scope azienda interna corrente della
		-- sessione) + risoluzione dell'unità locale dichiarata
		DECLARE @idSedeUnitaLocale CHAR(16);
		SELECT @idSedeUnitaLocale = c.IdSedeUnitaLocale
		FROM
			dbo.tblRifiutiMud c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione
			AND c.Lock <= 2;

		IF @idSedeUnitaLocale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- @Registri: lista di Id registro separati da ';'. Sono associabili solo i registri
		-- della stessa unità locale dichiarata, attivi.
		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiMudRegistri (Id, IdRegistro)
			SELECT
				@Id,
				r.Id
			FROM
				STRING_SPLIT(@Registri, ';') s
				INNER JOIN dbo.tblRifiutiRegistri r ON s.value = r.Id
			WHERE
				s.value <> ''
				AND r.IdSede = @idSedeUnitaLocale
				AND r.Lock = 0
				AND r.Id NOT IN (SELECT IdRegistro FROM dbo.tblRifiutiMudRegistri WHERE Id = @Id);

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
