SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Pre-controllo di coerenza prima dell'invio al RENTRI, adattata dalla SP di riferimento
-- 3_1_ecomatico.uspRentriRegistrazioni_get_InvioControllo (fornita dall'utente). Si ferma al
-- primo problema trovato (non un elenco cumulativo). Riusa dbo.viewRentriRegistrazioni: stessa
-- vista consumata dall'hub, quindi valida esattamente ciò che verrà davvero inviato.
-- Rinominata da uspRifiutiRegistrazioni_get_InvioControllo (2026-09-01) per coerenza col
-- prefisso Rentri delle altre SP dedicate al RENTRI (uspRentriSedi_*, uspRentriRegistri_*, ecc.).
-- exec dbo.uspRentriRegistrazioni_get_InvioControllo @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AllaData='20501231'
-- exec dbo.uspRentriRegistrazioni_get_InvioControllo @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AlNumero=10, @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_InvioControllo]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@AllaData DATE = NULL,
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IsData BIT = CAST(IIF(@AllaData IS NOT NULL, 1, 0) AS BIT);

		IF @IsData = 0 AND (@AlNumero IS NULL OR @Anno IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare una data oppure un numero e un anno';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @DataInizioRegistrazioni DATE;

		IF EXISTS (
			SELECT 1
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2
		)
			SELECT @DataInizioRegistrazioni = MAX(Data)
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2;
		ELSE
			SELECT @DataInizioRegistrazioni = z.DataInizioInvio
			FROM
				dbo.tblRentriRegistri                    g
				LEFT JOIN [1_0_rentri]..tblRegistri z ON g.IdRentri = z.Id COLLATE DATABASE_DEFAULT
			WHERE g.Id = @IdRegistro;

		DECLARE
			@Numero INT, @Data DATE, @NumeroBak INT = 0, @DataBak DATE,
			@Operazione VARCHAR(10), @Quantita DECIMAL(18, 3), @Anno_ CHAR(4),
			@IsTrasportatore BIT, @TrasportatoreAutorizzazione VARCHAR(20),
			@IsDestinatario BIT, @DestinatarioAutorizzazione VARCHAR(20),
			@IsIntermediario BIT, @IntermediarioAutorizzazione VARCHAR(20),
			@IsProduttore BIT, @ProduttoreIdComune CHAR(6), @ProduttoreNazione CHAR(2),
			@RecLock TINYINT, @Count INT = 0, @CountMax INT = 100;

		DECLARE c CURSOR LOCAL FAST_FORWARD FOR
		SELECT
			r.Numero, r.Data, r.Operazione, r.Quantita,
			r.IsTrasportatore, r.TrasportatoreAutorizzazione,
			r.IsDestinatario, r.DestinatarioAutorizzazione,
			r.IsIntermediario, r.IntermediarioAutorizzazione,
			r.IsProduttore, c.Id, r.ProduttoreNazione,
			r.Lock
		FROM
			dbo.viewRentriRegistrazioni r WITH (NOLOCK)
			LEFT JOIN [1_0_rentri]..tblComuni c WITH (NOLOCK) ON r.ProduttoreIdComune = c.Id COLLATE DATABASE_DEFAULT
		WHERE
			r.IDRegistro = @IdRegistro
			AND r.RentriIdentificativo IS NULL
			AND r.Lock < 2
			AND (@DataInizioRegistrazioni IS NULL OR r.Data >= @DataInizioRegistrazioni)
			AND (
				(@IsData = 1 AND r.Data <= @AllaData)
				OR (@IsData = 0 AND ((r.Anno < @Anno) OR (r.Anno = @Anno AND r.Numero BETWEEN 1 AND @AlNumero)))
			)
		ORDER BY r.Data, r.Numero;

		OPEN c;
		FETCH c INTO @Numero, @Data, @Operazione, @Quantita, @IsTrasportatore, @TrasportatoreAutorizzazione, @IsDestinatario, @DestinatarioAutorizzazione, @IsIntermediario, @IntermediarioAutorizzazione, @IsProduttore, @ProduttoreIdComune, @ProduttoreNazione, @RecLock;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @Count >= @CountMax
			BEGIN
				SET @returnMessage = 'Il numero massimo di registrazioni inviabile è ' + CAST(@CountMax AS VARCHAR(20));
				BREAK;
			END
			ELSE IF (@IsData = 1 AND YEAR(@Data) <> YEAR(@AllaData)) OR (@IsData = 0 AND YEAR(@Data) <> @Anno)
			BEGIN
				SET @returnMessage = 'Le registrazioni devono appartenere allo stesso anno, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF @Operazione IS NULL
			BEGIN
				SET @returnMessage = 'Causale non valida, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF @Quantita < 0
			BEGIN
				SET @returnMessage = 'Q.tà negativa non valida, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF ISNULL(@RecLock, 0) <> 0
			BEGIN
				SET @returnMessage = 'Registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy') + ' non confermata';
				BREAK;
			END
			ELSE IF (@NumeroBak > 0 AND @Numero - @NumeroBak <> 1)
			BEGIN
				SET @returnMessage = 'Salto di numerazione registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF (@NumeroBak > 0 AND @Data < @DataBak)
			BEGIN
				SET @returnMessage = 'Data inferiore alla precedente reg. N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsTrasportatore, 0) = 1 AND @TrasportatoreAutorizzazione IS NOT NULL AND @TrasportatoreAutorizzazione NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]')
			BEGIN
				SET @returnMessage = 'Il nr. di autoriz. del trasportatore deve essere indicato nel formato "AA/123456". Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsDestinatario, 0) = 1 AND (@DestinatarioAutorizzazione IS NULL OR LEN(@DestinatarioAutorizzazione) = 0 OR LEN(@DestinatarioAutorizzazione) > 20))
			BEGIN
				SET @returnMessage = 'Nr. errato autoriz. destinatario. Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsIntermediario, 0) = 1 AND @IntermediarioAutorizzazione IS NOT NULL AND @IntermediarioAutorizzazione NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]')
			BEGIN
				SET @returnMessage = 'Il nr. di autoriz. dell''intermediario deve essere indicato nel formato "AA/123456". Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsProduttore, 0) = 1 AND @ProduttoreNazione = 'IT' AND @ProduttoreIdComune IS NULL)
			BEGIN
				SET @returnMessage = 'Comune del Produttore non valido. Aggiornare l''anagrafica. Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END

			SET @Count = @Count + 1;
			SET @NumeroBak = @Numero;
			SET @DataBak = @Data;

			FETCH c INTO @Numero, @Data, @Operazione, @Quantita, @IsTrasportatore, @TrasportatoreAutorizzazione, @IsDestinatario, @DestinatarioAutorizzazione, @IsIntermediario, @IntermediarioAutorizzazione, @IsProduttore, @ProduttoreIdComune, @ProduttoreNazione, @RecLock;
		END
		CLOSE c;
		DEALLOCATE c;

		IF @returnMessage IS NULL AND @Count = 0
			SET @returnMessage = 'Nessuna registrazione trovata nell''intervallo indicato';

	END TRY
	BEGIN CATCH
		IF CURSOR_STATUS('local', 'c') >= -1
		BEGIN
			CLOSE c;
			DEALLOCATE c;
		END;
		THROW;
	END CATCH

	BRANCH_END:

	SET NOCOUNT, XACT_ABORT OFF;

	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Count = @Count, Messaggio = @returnMessage;

END
GO
