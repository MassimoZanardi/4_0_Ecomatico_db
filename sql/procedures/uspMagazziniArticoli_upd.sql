SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Codice VARCHAR(20) = NULL,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Codice = dbo.ufnStringhe_get_SenzaSpazi(@Codice, 0, 1);
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

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
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome';
			GOTO BRANCH_END;
		END
		IF @IdUnitaMisura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''unità di misura';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblUnitaMisura WHERE Id = @IdUnitaMisura)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''unità di misura indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblMagazziniArticoli c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro articolo attivo con lo stesso nome nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro articolo con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		-- Unità di misura NR (a numero): quantità intere, non frazionabili. Un articolo già
		-- movimentato con quantità decimali non può passare a NR
		IF @IdUnitaMisura = 'NR' AND EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniMovimentiRighe
			WHERE
				IdArticolo = @Id
				AND Quantita <> FLOOR(Quantita)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo ha movimenti con quantità decimali: non può essere gestito a numero';
			GOTO BRANCH_END;
		END

		-- Il codice è opzionale, ma se indicato deve essere univoco nella stessa azienda
		-- (stessa regola del nome)
		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Codice = @Codice
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro articolo con lo stesso codice è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblMagazziniArticoli
			SET
				Lock = 0,
				IdUnitaMisura = @IdUnitaMisura,
				Nome = @Nome,
				Codice = @Codice,
				Descrizione = @Descrizione
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Articolo non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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
