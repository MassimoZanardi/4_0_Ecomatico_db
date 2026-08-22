CREATE PROCEDURE [dbo].[uspUtenti_del_Undo]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		-- Validazione parametri
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @ripristinate INT;
		BEGIN TRANSACTION;
			-- Ripristina gli utenti cancellati dalla sessione corrente
			UPDATE i
			SET Lock = 0 -- Lock = 0 = attivo
			FROM dbo.tblUtenti i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;
			-- Rimuove la voce di log 'D' (delete) per le entità ripristinate
			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';
			-- Rimuove le entità dalla lista dei cancellati
			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			-- @@ROWCOUNT letto subito dopo DELETE tblIdCancellati
			SET @ripristinate = @@ROWCOUNT;
		COMMIT TRANSACTION;
		-- Costruisce il messaggio di esito basato sulle righe dell'UPDATE
		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;
		SELECT @returnMessage AS ReturnMessage;
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
