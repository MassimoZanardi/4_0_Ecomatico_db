SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modifica dei soli dati "da documento" di una riga: imballo, colli e alla rinfusa per una riga
-- articolo, il testo per una riga descrittiva. Non toccano giacenze né relazioni carico/scarico,
-- quindi sono modificabili anche a movimento confermato. Sede, articolo, lotto, criterio e
-- quantità non si modificano: la riga va tolta e reinserita.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Colli INT = NULL,
	@AllaRinfusa BIT = 0,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Imballo: '00' è il segnaposto "(Selezionare)" di uspImballi_get_SelectList; alla
		-- rinfusa non c'è imballo (come nei Formulari)
		SET @IdImballo = NULLIF(NULLIF(LTRIM(RTRIM(@IdImballo)), ''), '00');
		SET @AllaRinfusa = ISNULL(@AllaRinfusa, 0);
		IF @AllaRinfusa = 1 SET @IdImballo = NULL;
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');

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
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La riga deve appartenere a un movimento (in bozza o già confermato, non eliminato)
		-- dell'azienda interna corrente della sessione
		DECLARE @isDescrizione BIT = NULL;
		SELECT @isDescrizione = IIF(r.IdArticolo IS NULL, 1, 0)
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti c ON r.IdMovimento = c.Id
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @isDescrizione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		IF @isDescrizione = 1
		BEGIN
			-- Riga descrittiva: solo il testo
			IF @Descrizione IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare la descrizione';
				GOTO BRANCH_END;
			END
			SET @IdImballo = NULL;
			SET @Colli = NULL;
			SET @AllaRinfusa = NULL;
		END
		ELSE
		BEGIN
			SET @Descrizione = NULL;
			IF @Colli < 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il numero di colli non può essere negativo';
				GOTO BRANCH_END;
			END
			IF @IdImballo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblImballi WHERE Id = @IdImballo)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''imballo indicato non esiste';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblMagazziniMovimentiRighe
			SET
				IdImballo = @IdImballo,
				Colli = @Colli,
				AllaRinfusa = @AllaRinfusa,
				Descrizione = @Descrizione
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Riga non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

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
