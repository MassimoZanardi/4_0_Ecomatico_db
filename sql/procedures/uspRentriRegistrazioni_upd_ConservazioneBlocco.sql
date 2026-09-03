SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Blocca (ConservazioneSostitutiva=1) tutte le registrazioni attive (Lock=0) nell'intervallo
-- Numero/Anno indicato, per il flusso di conservazione sostitutiva in Rifiuti/Registrazioni.
-- Da questo momento uspRifiutiRegistrazioni_upd/_del rifiutano ogni modifica/cancellazione su
-- queste righe (stesso principio di RentriIdentificativo/RentriData). Aggiornamento massivo,
-- nessun log per singola riga (coerente con altri fix/bulk-update di questo repo, es. esclusione
-- rettifiche da giacenze/relazioni).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_ConservazioneBlocco]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare numero iniziale, numero finale e anno';
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

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @count INT;

		BEGIN TRANSACTION;

			UPDATE r
			SET ConservazioneSostitutiva = 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				m.IdRegistro = @IdRegistro
				AND r.Numero BETWEEN @DalNumero AND @AlNumero
				AND YEAR(r.[Data]) = @Anno
				AND r.Lock = 0;

			SET @count = @@ROWCOUNT;

		COMMIT TRANSACTION;

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

	SELECT Count = @count;

END
GO
