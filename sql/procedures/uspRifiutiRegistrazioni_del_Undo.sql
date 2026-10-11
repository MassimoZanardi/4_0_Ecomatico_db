SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Ripristina le registrazioni cancellate dalla sessione (tblIdCancellati). Il ripristino è rifiutato se nel
-- frattempo il numero di una di esse è stato assegnato a un'altra registrazione dello stesso registro e anno.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del_Undo]
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Numerazione: i registri delle registrazioni da ripristinare vengono bloccati per tutta la
			-- transazione (UPDLOCK/HOLDLOCK sulle loro sole righe), come in uspRifiutiRegistrazioni_upd
			DECLARE @registriBloccati INT = (
				SELECT COUNT(*)
				FROM dbo.tblRifiutiRegistri g WITH (UPDLOCK, HOLDLOCK)
				WHERE g.Id IN (
					SELECT m.IdRegistro
					FROM
						dbo.tblIdCancellati c
						INNER JOIN dbo.tblRifiutiRegistrazioni i ON c.Id = i.Id
						INNER JOIN dbo.tblRifiutiMovimenti m ON i.IdMovimento = m.Id
					WHERE c.IdSessione = @IdSessione));

			-- Dopo la cancellazione il numero può essere stato riassegnato a un'altra registrazione dello
			-- stesso registro e anno: il ripristino creerebbe due registrazioni con lo stesso numero
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblIdCancellati c
					INNER JOIN dbo.tblRifiutiRegistrazioni i ON c.Id = i.Id
					INNER JOIN dbo.tblRifiutiMovimenti mi ON i.IdMovimento = mi.Id
					INNER JOIN dbo.tblRifiutiMovimenti ma ON mi.IdRegistro = ma.IdRegistro
					INNER JOIN dbo.tblRifiutiRegistrazioni a ON ma.Id = a.IdMovimento
				WHERE
					c.IdSessione = @IdSessione
					AND i.Lock = 4
					AND a.Lock < 2
					AND a.Id <> i.Id
					AND a.Numero = i.Numero
					AND a.[Data] >= DATEFROMPARTS(YEAR(i.[Data]), 1, 1)
					AND a.[Data] < DATEFROMPARTS(YEAR(i.[Data]) + 1, 1, 1)
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Ripristino non possibile: il numero della registrazione è già stato assegnato a un''altra registrazione';
				GOTO BRANCH_END;
			END

			UPDATE i
			SET Lock = 0
			FROM dbo.tblRifiutiRegistrazioni i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE c.IdSessione = @IdSessione;

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
