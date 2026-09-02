SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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

		-- Recupera l'operazione del padre e verifica che esista
		DECLARE @operazioneParent CHAR(1);
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT
			@operazioneParent = Operazione,
			@rentriIdentificativo = RentriIdentificativo,
			@rentriData = RentriData
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @IdParent;

		IF @operazioneParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione padre non trovata';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		IF (
			SELECT COUNT(DISTINCT r.Id)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id IN (@Id, @IdParent)) < 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1) + 1
		FROM dbo.tblRifiutiRegistrazioniRelazioni s
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;
		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			VALUES
				(@Id, @IdParent, @operazioneParent, 0, @pos);

			-- Imposta la registrazione padre nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
