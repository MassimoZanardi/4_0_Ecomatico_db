CREATE OR ALTER PROCEDURE [dbo].[uspId_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Operazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;

	BEGIN TRY

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL OR @Operazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'uspId_upd: parametri @Id, @IdSessione, @Operazione obbligatori';
			GOTO BRANCH_END;
		END

		DECLARE @data DATETIME2(0) = GETDATE();
		DECLARE @dataMin DATETIME2(0);

		-- Calcola la soglia per la pulizia del log (fuori dalla transazione)
		IF @Operazione = 'U'
			SELECT TOP 1
				@dataMin = [Data]
			FROM (
				SELECT
					[Data],
					Pos = ROW_NUMBER() OVER (ORDER BY [Data] DESC)
				FROM dbo.tblIdLog
				WHERE
					Id = @Id
					AND Operazione = 'U'
			) t
			WHERE t.Pos > 9 -- mantiene max 10 record per Id
			ORDER BY Pos;
		ELSE
			SET @dataMin = @data;

		BEGIN TRANSACTION;

			IF @Operazione = 'U'
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					AND Operazione = 'U'
					AND
						(
						-- Sovrascrive operazioni sullo stesso Id nel range di 30 secondi
					  [Data] BETWEEN DATEADD(SECOND, -30, @data) AND @data
						OR
					  -- Elimina i log oltre il decimo
					  -- NULL <= NULL = FALSE: nessun effetto se @dataMin è NULL
					  [Data] <= @dataMin
						);

			INSERT INTO dbo.tblIdLog (Id, Operazione, [Data], IdUtente)
			SELECT @Id, @Operazione, @data, IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;

		COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		THROW; -- propaga senza ROLLBACK: la gestione spetta al chiamante
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
