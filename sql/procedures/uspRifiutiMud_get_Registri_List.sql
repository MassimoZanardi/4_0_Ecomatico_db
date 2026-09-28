SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMud_get_Registri_List]
	@Id CHAR(16) = NULL,
	@DaAssociare BIT = 0,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla dichiarazione padre: scope azienda interna corrente della
		-- sessione. tblRifiutiMud.IdSede è già l'Id dell'azienda radice (valorizzato
		-- da uspRifiutiMud_ins con tblSessioni.IdAzienda), quindi i registri proponibili
		-- sono tutti quelli riconducibili a questa azienda, non solo alla singola
		-- unità locale dichiarata
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblRifiutiMud c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Ramo 1: Registri già associati alla dichiarazione
		IF @DaAssociare = 0
		BEGIN
			SELECT
				r.Id,
				r.Nome
			FROM
				dbo.tblRifiutiMudRegistri a
				INNER JOIN dbo.tblRifiutiRegistri r ON a.IdRegistro = r.Id
			WHERE a.Id = @Id
			ORDER BY
				r.Nome;
		END

		-- Ramo 2: Registri della stessa azienda interna non ancora associati, filtrabili per @Search
		ELSE
		BEGIN
			SELECT TOP 50
				r.Id,
				r.Nome
			FROM
				dbo.tblRifiutiRegistri r
				INNER JOIN dbo.tblSedi rs ON r.IdSede = rs.Id
			WHERE
				rs.IdAziendaInterna = @idAzienda
				AND r.Lock = 0
				AND r.Id NOT IN (SELECT IdRegistro FROM dbo.tblRifiutiMudRegistri WHERE Id = @Id)
				AND
					(
					@Search IS NULL
					OR r.Nome LIKE '%' + @Search + '%'
					)
			ORDER BY
				r.Nome;
		END

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
