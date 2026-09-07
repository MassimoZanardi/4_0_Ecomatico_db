SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Risolve, per ciascun ruolo (Produttore/Destinatario/Trasportatore/Intermediario1/Intermediario2), l'
-- IdAutorizzazione da passare a uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd durante l'importazione
-- di un formulario digitale RENTRI (Rifiuti/Registrazioni e Rifiuti/Formulari, "Acquisisci da formulario
-- digitale"). Nessun controllo bloccante sul match: se non si trova una corrispondenza univoca il relativo
-- Id resta NULL e l'utente completa a mano da Edit (stesso comportamento della SP legacy 3.1
-- uspRifiutiSchede_ins_ImportazioneFormularioDigitale).
--
-- Cascata per ruolo (P/D/T/I), ristretta alle sedi visibili all'azienda interna del registro (stesso
-- calcolo di uspRifiutiAutorizzazioni_get_SelectList):
--   1. Autorizzazione con Numero + CodiceFiscale sede coincidenti
--   2. Solo CodiceFiscale sede, accettato solo se il match è univoco (esattamente 1 riga)
--   3. Solo per il Produttore: nessuna autorizzazione trovata ma esiste una Sede con quel CF tra le
--      visibili, senza un'autorizzazione Nessuna=1 che la blocchi → usa l'Id della Sede stessa
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get_MatchImportazione]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@ProduttoreCodiceFiscale VARCHAR(20) = NULL,
	@ProduttoreAutorizzazione VARCHAR(20) = NULL,
	@DestinatarioCodiceFiscale VARCHAR(20) = NULL,
	@DestinatarioAutorizzazione VARCHAR(20) = NULL,
	@TrasportatoreCodiceFiscale VARCHAR(20) = NULL,
	@TrasportatoreAutorizzazione VARCHAR(20) = NULL,
	@IntermediarioCodiceFiscale VARCHAR(20) = NULL,
	@IntermediarioAutorizzazione VARCHAR(20) = NULL,
	@Intermediario2CodiceFiscale VARCHAR(20) = NULL,
	@Intermediario2Autorizzazione VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @ProduttoreCodiceFiscale = NULLIF(LTRIM(RTRIM(@ProduttoreCodiceFiscale)), '');
		SET @ProduttoreAutorizzazione = NULLIF(LTRIM(RTRIM(@ProduttoreAutorizzazione)), '');
		SET @DestinatarioCodiceFiscale = NULLIF(LTRIM(RTRIM(@DestinatarioCodiceFiscale)), '');
		SET @DestinatarioAutorizzazione = NULLIF(LTRIM(RTRIM(@DestinatarioAutorizzazione)), '');
		SET @TrasportatoreCodiceFiscale = NULLIF(LTRIM(RTRIM(@TrasportatoreCodiceFiscale)), '');
		SET @TrasportatoreAutorizzazione = NULLIF(LTRIM(RTRIM(@TrasportatoreAutorizzazione)), '');
		SET @IntermediarioCodiceFiscale = NULLIF(LTRIM(RTRIM(@IntermediarioCodiceFiscale)), '');
		SET @IntermediarioAutorizzazione = NULLIF(LTRIM(RTRIM(@IntermediarioAutorizzazione)), '');
		SET @Intermediario2CodiceFiscale = NULLIF(LTRIM(RTRIM(@Intermediario2CodiceFiscale)), '');
		SET @Intermediario2Autorizzazione = NULLIF(LTRIM(RTRIM(@Intermediario2Autorizzazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idAziendaInterna CHAR(16), @idUtente CHAR(16);
		SELECT
			@idAziendaInterna = s.IdAziendaInterna,
			@idUtente = e.IdUtente
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblRifiutiRegistri r ON e.Id = @IdSessione AND r.Id = @IdRegistro
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id;

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

		-- Sedi visibili all'utente (interne dell'azienda + condivise) - stesso calcolo di
		-- uspRifiutiAutorizzazioni_get_SelectList, evita di richiamare la function per ogni ruolo
		SELECT
			Id, IdAziendaInterna, Condivisa, Disabilitata
		INTO #sediUtente
		FROM dbo.ufnSedi_get_SediByUtente_List(@idUtente);

		CREATE UNIQUE CLUSTERED INDEX IX_sediUtente_Id ON #sediUtente (Id);

		DECLARE
			@idAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
			@idAutorizzazioneDestinatario CHAR(16) = NULL,
			@idAutorizzazioneTrasportatore1 CHAR(16) = NULL,
			@idAutorizzazioneIntermediario1 CHAR(16) = NULL,
			@idAutorizzazioneIntermediario2 CHAR(16) = NULL,
			@cnt INT;

		-- ── PRODUTTORE ───────────────────────────────────────────────────────────
		IF @ProduttoreCodiceFiscale IS NOT NULL
		BEGIN
			IF @ProduttoreAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneProduttoreDetentore = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'P' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @ProduttoreCodiceFiscale
					AND a.Numero = @ProduttoreAutorizzazione;

			IF @idAutorizzazioneProduttoreDetentore IS NULL
			BEGIN
				SELECT @idAutorizzazioneProduttoreDetentore = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'P' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @ProduttoreCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneProduttoreDetentore = NULL;
			END

			IF @idAutorizzazioneProduttoreDetentore IS NULL
			BEGIN
				SELECT @idAutorizzazioneProduttoreDetentore = MIN(s.Id), @cnt = COUNT(*)
				FROM
					dbo.tblSedi s
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @ProduttoreCodiceFiscale
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRifiutiAutorizzazioni na
						WHERE na.IdSede = s.Id AND na.IdRuolo = 'P' AND na.Nessuna = 1 AND na.Lock = 0
					);
				IF @cnt <> 1 SET @idAutorizzazioneProduttoreDetentore = NULL;
			END
		END

		-- ── DESTINATARIO ─────────────────────────────────────────────────────────
		IF @DestinatarioCodiceFiscale IS NOT NULL
		BEGIN
			IF @DestinatarioAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneDestinatario = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'D' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @DestinatarioCodiceFiscale
					AND a.Numero = @DestinatarioAutorizzazione;

			IF @idAutorizzazioneDestinatario IS NULL
			BEGIN
				SELECT @idAutorizzazioneDestinatario = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'D' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @DestinatarioCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneDestinatario = NULL;
			END
		END

		-- ── TRASPORTATORE (Pos 0) ────────────────────────────────────────────────
		IF @TrasportatoreCodiceFiscale IS NOT NULL
		BEGIN
			IF @TrasportatoreAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneTrasportatore1 = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'T' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @TrasportatoreCodiceFiscale
					AND a.Numero = @TrasportatoreAutorizzazione;

			IF @idAutorizzazioneTrasportatore1 IS NULL
			BEGIN
				SELECT @idAutorizzazioneTrasportatore1 = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'T' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @TrasportatoreCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneTrasportatore1 = NULL;
			END
		END

		-- ── INTERMEDIARIO 1 ──────────────────────────────────────────────────────
		IF @IntermediarioCodiceFiscale IS NOT NULL
		BEGIN
			IF @IntermediarioAutorizzazione IS NOT NULL
				SELECT @idAutorizzazioneIntermediario1 = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @IntermediarioCodiceFiscale
					AND a.Numero = @IntermediarioAutorizzazione;

			IF @idAutorizzazioneIntermediario1 IS NULL
			BEGIN
				SELECT @idAutorizzazioneIntermediario1 = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @IntermediarioCodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneIntermediario1 = NULL;
			END
		END

		-- ── INTERMEDIARIO 2 ──────────────────────────────────────────────────────
		IF @Intermediario2CodiceFiscale IS NOT NULL
		BEGIN
			IF @Intermediario2Autorizzazione IS NOT NULL
				SELECT @idAutorizzazioneIntermediario2 = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @Intermediario2CodiceFiscale
					AND a.Numero = @Intermediario2Autorizzazione;

			IF @idAutorizzazioneIntermediario2 IS NULL
			BEGIN
				SELECT @idAutorizzazioneIntermediario2 = MIN(a.Id), @cnt = COUNT(*)
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
					INNER JOIN #sediUtente u ON u.Id = s.Id
				WHERE
					a.IdRuolo = 'I' AND a.Disabilitata = 0 AND a.Lock < 2
					AND s.Disabilitata = 0 AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.CodiceFiscale = @Intermediario2CodiceFiscale;
				IF @cnt <> 1 SET @idAutorizzazioneIntermediario2 = NULL;
			END
		END

		SELECT
			IdAutorizzazioneProduttoreDetentore = @idAutorizzazioneProduttoreDetentore,
			IdAutorizzazioneDestinatario = @idAutorizzazioneDestinatario,
			IdAutorizzazioneTrasportatore1 = @idAutorizzazioneTrasportatore1,
			IdAutorizzazioneIntermediario1 = @idAutorizzazioneIntermediario1,
			IdAutorizzazioneIntermediario2 = @idAutorizzazioneIntermediario2;

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
