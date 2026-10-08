SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registra la generazione dei file XML della fattura elettronica per le fatture indicate (@Ids: Id separati
-- da ;): assegna a ciascuna un progressivo dell'azienda (tblFattureDatiFiscali.ProgressivoInvio, 5 caratteri
-- in base 36: è quello del nome del file e del blocco DatiTrasmissione), segna la data della generazione e,
-- con @SolaLettura = 1, mette la fattura in sola lettura. Rigenerare il file assegna un nuovo progressivo.
-- Le fatture devono essere clienti, attive e numerate, dell'azienda interna corrente della sessione.
-- Restituisce Id e Progressivo di ogni fattura, in ordine di numero.
CREATE OR ALTER PROCEDURE dbo.uspFatture_upd_Xml
	@IdSessione CHAR(16) = NULL,
	@Ids VARCHAR(MAX) = NULL,
	@SolaLettura BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Ids = NULLIF(LTRIM(RTRIM(@Ids)), '');
		SET @SolaLettura = ISNULL(@SolaLettura, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Ids IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessuna fattura indicata';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		DECLARE @richieste TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		INSERT @richieste (Id)
		SELECT DISTINCT LTRIM(RTRIM(v.value))
		FROM STRING_SPLIT(@Ids, ';') v
		WHERE LTRIM(RTRIM(v.value)) <> '';

		DECLARE @fatture TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, Pos INT NOT NULL, Progressivo INT NULL);
		INSERT @fatture (Id, Pos)
		SELECT
			f.Id,
			ROW_NUMBER() OVER (ORDER BY f.DataEmissione, f.Numero, f.Sezionale, f.Id)
		FROM
			@richieste q
			INNER JOIN dbo.tblFatture f ON q.Id = f.Id
		WHERE
			f.IdSede = @idAzienda
			AND f.Tipo = 'C'
			AND f.Lock = 0
			AND f.Numero IS NOT NULL;

		IF (SELECT COUNT(*) FROM @fatture) = 0 OR (SELECT COUNT(*) FROM @fatture) <> (SELECT COUNT(*) FROM @richieste)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o una delle fatture non esiste o non è numerata';
			GOTO BRANCH_END;
		END
		IF (SELECT COUNT(*) FROM @fatture) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si possono generare al massimo 100 fatture alla volta';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureDatiFiscali WHERE Id = @idAzienda)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Completare i dati fiscali dell''azienda (Fatturazione > Dati fiscali)';
			GOTO BRANCH_END;
		END

		DECLARE @cifre CHAR(36) = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
		DECLARE @numero INT = (SELECT COUNT(*) FROM @fatture);
		DECLARE @ultimo INT;

		BEGIN TRANSACTION;
			-- Progressivi dell'azienda riservati con il blocco sulla riga dei dati fiscali
			UPDATE dbo.tblFattureDatiFiscali WITH (UPDLOCK, HOLDLOCK)
			SET
				@ultimo = ISNULL(ProgressivoInvio, 0),
				ProgressivoInvio = ISNULL(ProgressivoInvio, 0) + @numero
			WHERE Id = @idAzienda;

			-- 5 caratteri in base 36: 60.466.175 file per azienda
			IF @ultimo + @numero > 60466175
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Progressivi dei file esauriti per questa azienda';
				GOTO BRANCH_END;
			END

			UPDATE @fatture
			SET Progressivo = @ultimo + Pos;

			UPDATE f
			SET
				DataXml = GETDATE(),
				ProgressivoXml =
					SUBSTRING(@cifre, (t.Progressivo / 1679616) % 36 + 1, 1)
					+ SUBSTRING(@cifre, (t.Progressivo / 46656) % 36 + 1, 1)
					+ SUBSTRING(@cifre, (t.Progressivo / 1296) % 36 + 1, 1)
					+ SUBSTRING(@cifre, (t.Progressivo / 36) % 36 + 1, 1)
					+ SUBSTRING(@cifre, t.Progressivo % 36 + 1, 1),
				SolaLettura = IIF(@SolaLettura = 1, 1, f.SolaLettura)
			FROM
				dbo.tblFatture f
				INNER JOIN @fatture t ON f.Id = t.Id;
		COMMIT TRANSACTION;

		SELECT
			f.Id,
			Progressivo = f.ProgressivoXml
		FROM
			dbo.tblFatture f
			INNER JOIN @fatture t ON f.Id = t.Id
		ORDER BY t.Pos;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
