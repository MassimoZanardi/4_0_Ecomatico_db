SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_get
	@Id CHAR(16) = NULL,
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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAmministratori c
				INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblAmministratori WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Amministratore non trovato';
			GOTO BRANCH_END;
		END

		-- I dati anagrafici del soggetto sono in sola lettura: si modificano in Anagrafica > Soggetti
		SELECT
			c.Id,
			c.IdAziendaInterna,
			c.IdSede,
			c.Note,
			c.Lock,
			SedeNomeCompleto = s.NomeCompleto,
			SedeIndirizzoCompleto = s.IndirizzoCompleto,
			SedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM
			dbo.tblAmministratori c
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

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
