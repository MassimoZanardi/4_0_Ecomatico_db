SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSessioni_upd_AziendaByContesto]
	@Id CHAR(16) = NULL,
	@Contesto INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Contesto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Contesto non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @Contesto = 2 -- Sede: l'azienda è quella della sede del contesto
		BEGIN
			UPDATE e
			SET IdAzienda = ISNULL(s.IdParent, s.Id)
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblSedi s ON e.IdSede = s.Id
			WHERE e.Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Sessione non trovata o sede non impostata';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @Contesto = 3 -- Registro
		BEGIN
			UPDATE e
			SET IdAzienda = s.IdAziendaInterna
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblRifiutiRegistri r ON e.IdRegistro = r.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			WHERE e.Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Sessione non trovata o registro non impostato';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Contesto non valido: ' + CAST(@Contesto AS VARCHAR(5));
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
