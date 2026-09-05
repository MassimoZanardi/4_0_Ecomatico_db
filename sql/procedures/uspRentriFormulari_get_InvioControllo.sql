SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Pre-controllo di coerenza prima dell'invio a RENTRI (Crea/Modifica formulario digitale), adattata
-- dalla SP di riferimento 3_1_ecomatico.uspRentriFormulari_get_InvioControllo (fornita dall'utente).
-- Si ferma al primo problema trovato. Riusa dbo.viewRentriFormulariDigitali: stessa vista consumata
-- dall'hub, quindi valida esattamente ciò che verrà davvero inviato.
-- Due adattamenti rispetto alla SP legacy (confermati dall'utente 2026-09-05):
-- 1) Il controllo comune Destinatario in 3.1 confronta erroneamente DestinatarioIdComune = 'IT' invece
--    di DestinatarioNazione = 'IT' (bug di trascrizione copy-paste dai due rami gemelli sopra) - qui
--    corretto.
-- 2) Il controllo "tipo autorizzazione Destinatario" in 3.1 lo richiede sempre. Nel nostro schema il
--    Destinatario può validamente essere iscritto all'Albo (nessun Tipo previsto in quel caso, vedi
--    viewRentriFormulariDigitali) - qui il controllo scatta solo se NON Albo e il Tipo manca comunque.
-- exec dbo.uspRentriFormulari_get_InvioControllo @Id='04ab59fa5c3e4dbe', @IdSessione='...'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFormulari_get_InvioControllo]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				f.Id = @Id
				AND f.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE
			@ProduttoreNazione CHAR(2), @ProduttoreIdComune CHAR(6),
			@PosizioneNazione CHAR(2), @PosizioneIdComune CHAR(6),
			@DestinatarioNazione CHAR(2), @DestinatarioIdComune CHAR(6),
			@DestinatarioAutorizzazioneAlbo VARCHAR(20), @DestinatarioAutorizzazioneTipo VARCHAR(30),
			@TrasportatoreAutorizzazioneAlbo VARCHAR(20), @Trasportatore2AutorizzazioneAlbo VARCHAR(20),
			@IntermediarioAutorizzazioneAlbo VARCHAR(20), @Intermediario2AutorizzazioneAlbo VARCHAR(20);

		SELECT
			@ProduttoreNazione = f.ProduttoreNazione,
			@ProduttoreIdComune = f.ProduttoreIdComune,
			@PosizioneNazione = f.PosizioneNazione,
			@PosizioneIdComune = f.PosizioneIdComune,
			@DestinatarioNazione = f.DestinatarioNazione,
			@DestinatarioIdComune = f.DestinatarioIdComune,
			@DestinatarioAutorizzazioneAlbo = f.DestinatarioAutorizzazioneAlbo,
			@DestinatarioAutorizzazioneTipo = f.DestinatarioAutorizzazioneTipo,
			@TrasportatoreAutorizzazioneAlbo = f.TrasportatoreAutorizzazioneAlbo,
			@Trasportatore2AutorizzazioneAlbo = f.Trasportatore2AutorizzazioneAlbo,
			@IntermediarioAutorizzazioneAlbo = f.IntermediarioAutorizzazioneAlbo,
			@Intermediario2AutorizzazioneAlbo = f.Intermediario2AutorizzazioneAlbo
		FROM dbo.viewRentriFormulariDigitali f WITH (NOLOCK)
		WHERE f.IdFormulario = @Id;

		IF @ProduttoreNazione = 'IT' AND @ProduttoreIdComune IS NULL
			SET @returnMessage = 'Il comune del Produttore non è valido. Aggiornare l''anagrafica';
		ELSE IF @PosizioneNazione = 'IT' AND @PosizioneIdComune IS NULL
			SET @returnMessage = 'Il comune del Luogo di produzione non è valido. Aggiornare l''anagrafica';
		ELSE IF @DestinatarioNazione = 'IT' AND @DestinatarioIdComune IS NULL
			SET @returnMessage = 'Il comune del Destinatario non è valido. Aggiornare l''anagrafica';
		ELSE IF @DestinatarioAutorizzazioneAlbo IS NULL AND @DestinatarioAutorizzazioneTipo IS NULL
			SET @returnMessage = 'Non è stato indicato il tipo di autorizzazione del Destinatario. Aggiornare l''autorizzazione';
		ELSE IF @TrasportatoreAutorizzazioneAlbo IS NOT NULL AND @TrasportatoreAutorizzazioneAlbo NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]'
			SET @returnMessage = 'Il numero di autorizzazione del 1° Trasportatore non è valido. Formato corretto: "AA/123456"';
		ELSE IF @Trasportatore2AutorizzazioneAlbo IS NOT NULL AND @Trasportatore2AutorizzazioneAlbo NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]'
			SET @returnMessage = 'Il numero di autorizzazione del 2° Trasportatore non è valido. Formato corretto: "AA/123456"';
		ELSE IF @IntermediarioAutorizzazioneAlbo IS NOT NULL AND @IntermediarioAutorizzazioneAlbo NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]'
			SET @returnMessage = 'Il numero di autorizzazione del 1° Intermediario non è valido. Formato corretto: "AA/123456"';
		ELSE IF @Intermediario2AutorizzazioneAlbo IS NOT NULL AND @Intermediario2AutorizzazioneAlbo NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]'
			SET @returnMessage = 'Il numero di autorizzazione del 2° Intermediario non è valido. Formato corretto: "AA/123456"';

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

	SELECT Messaggio = @returnMessage;

END
GO
