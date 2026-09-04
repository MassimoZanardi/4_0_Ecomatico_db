SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCredenziali_get_IdRentriRegistro]
	@IdCredenziale CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: la credenziale deve appartenere allo stesso Dominio della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti a ON a.IdDominio = rc.IdDominio
			INNER JOIN dbo.tblSessioni s ON s.IdUtente = a.Id
			WHERE rc.Id = @IdCredenziale AND s.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'endpoint hub di risoluzione del connettore (certificato) è per Registro
		-- (viewRegistri, 1_0_rentri), non per Credenziale: si risale a un Registro
		-- qualunque delle Sedi collegate a questa Credenziale - condividono lo stesso
		-- certificato, quindi va bene il primo trovato.
		DECLARE @IdRentri CHAR(16);
		SELECT TOP 1 @IdRentri = rr.IdRentri
		FROM
			dbo.tblRentriCredenzialiSedi cs
			INNER JOIN dbo.tblRifiutiRegistri g ON g.IdSede = cs.IdSede AND g.Lock = 0
			INNER JOIN dbo.tblRentriRegistri rr ON rr.Id = g.Id AND rr.IdRentri IS NOT NULL
		WHERE cs.IdCredenziale = @IdCredenziale;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessun registro collegato a RENTRI per questo operatore';
			GOTO BRANCH_END;
		END

		SELECT rtn = @IdRentri;

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
