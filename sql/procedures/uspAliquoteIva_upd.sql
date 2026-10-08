SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(2) = NULL,
	@IdNatura VARCHAR(4) = NULL,
	@RiferimentoNormativo VARCHAR(150) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Codice VARCHAR(20) = NULL,
	@Valore DECIMAL(9, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 2)));
		SET @IdNatura = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdNatura)), ''), REPLICATE('0', 4)));
		SET @RiferimentoNormativo = dbo.ufnStringhe_get_SenzaSpazi(@RiferimentoNormativo, 0, 1);
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Codice = dbo.ufnStringhe_get_SenzaSpazi(@Codice, 0, 1);

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Le aliquote di sistema (IdSede NULL) non si modificano mai, da nessun utente
		IF EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id AND IdSede IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''aliquota di sistema non può essere modificata';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblAliquoteIva c
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

		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome';
			GOTO BRANCH_END;
		END
		IF @IdTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = @IdTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Regola della fattura elettronica: la natura si indica solo con aliquota zero, e allora è obbligatoria.
		--   Imponibile (IM): valore maggiore di zero, nessuna natura
		--   Altri tipi (esente, escluso, fuori campo, non imponibile): valore zero, natura obbligatoria
		IF @IdTipo = 'IM'
		BEGIN
			IF @Valore IS NULL OR @Valore <= 0 OR @Valore > 100
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Per un''aliquota imponibile indicare un valore maggiore di 0 e non superiore a 100';
				GOTO BRANCH_END;
			END
			SET @IdNatura = NULL;
			SET @RiferimentoNormativo = NULL;
		END
		ELSE
		BEGIN
			IF ISNULL(@Valore, 0) <> 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Solo un''aliquota imponibile può avere un valore diverso da 0';
				GOTO BRANCH_END;
			END
			SET @Valore = 0;

			IF @IdNatura IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare la natura';
				GOTO BRANCH_END;
			END
			IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = @IdNatura)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La natura indicata non esiste';
				GOTO BRANCH_END;
			END
		END

		-- Nome (e codice, se indicato) unici tra le aliquote di sistema e quelle attive dell'azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblAliquoteIva
			WHERE
				Id <> @Id
				AND (IdSede IS NULL OR IdSede = @idAzienda)
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra aliquota con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END
		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblAliquoteIva
			WHERE
				Id <> @Id
				AND (IdSede IS NULL OR IdSede = @idAzienda)
				AND Lock = 0
				AND Codice = @Codice
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra aliquota con lo stesso codice è già presente';
			GOTO BRANCH_END;
		END

		-- Il riferimento normativo accompagna la natura nel file della fattura elettronica: facoltativo
		IF LEN(@RiferimentoNormativo) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il riferimento normativo non può superare i 100 caratteri';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblAliquoteIva
			SET
				Lock = 0,
				IdTipo = @IdTipo,
				IdNatura = @IdNatura,
				RiferimentoNormativo = @RiferimentoNormativo,
				Nome = @Nome,
				Codice = @Codice,
				Valore = @Valore
			WHERE
				Id = @Id
				AND IdSede IS NOT NULL
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Aliquota non trovata o già eliminata';
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
