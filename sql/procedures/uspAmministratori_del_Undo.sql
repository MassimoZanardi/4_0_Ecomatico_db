SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Dopo la cancellazione lo stesso soggetto può essere stato reinserito tra gli
		-- amministratori, oppure essere diventato un soggetto amministrato
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblAmministratori i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblAmministratori a ON i.IdAziendaInterna = a.IdAziendaInterna
												 AND i.IdSede = a.IdSede
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: il soggetto è già stato reinserito tra gli amministratori';
			GOTO BRANCH_END;
		END

		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblAmministratori i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblAmministratoriSedi y ON i.IdSede = y.IdSede
				INNER JOIN dbo.tblAmministratori a ON y.Id = a.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: il soggetto è ora amministrato da un altro amministratore';
			GOTO BRANCH_END;
		END

		-- I suoi soggetti amministrati possono essere stati assegnati a un altro amministratore,
		-- o essere diventati a loro volta amministratori
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblAmministratori i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblAmministratoriSedi x ON i.Id = x.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND
					(
					EXISTS (
						SELECT 1
						FROM
							dbo.tblAmministratoriSedi y
							INNER JOIN dbo.tblAmministratori a ON y.Id = a.Id
						WHERE
							y.IdSede = x.IdSede
							AND a.Lock = 0
					)
					OR EXISTS (
						SELECT 1
						FROM dbo.tblAmministratori a
						WHERE
							a.IdSede = x.IdSede
							AND a.Lock = 0
					)
					)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: uno dei soggetti amministrati ha ora un altro amministratore o è diventato amministratore';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblAmministratori i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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
