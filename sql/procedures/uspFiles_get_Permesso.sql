SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- File allegati (tblFiles): permesso della sessione sul record a cui sono allegati, usato da tutte le uspFiles_*.
-- @Permesso: 0 nessun accesso, 1 lettura (elenco e download), 2 modifica (carica e cancella).
-- Record ammessi: registrazioni e autorizzazioni attive (Lock < 2): le bozze non hanno allegati e quelle cancellate
-- (Lock = 4) li tengono per un eventuale ripristino, senza mostrarli.
-- Registrazione: sede interna dell'utente sul registro, permesso della funzione RRG.
-- Autorizzazione: dell'azienda del contesto, permesso della funzione RAT; condivisa da un'altra azienda (sede interna
-- dell'utente o azienda esterna condivisa, come uspRifiutiAutorizzazioni_get): al massimo lettura, come la modifica.
-- Fail-safe come uspSessione_get_FunzionePermesso: su parametri vuoti o record non trovato restituisce 0
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Permesso]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Permesso INT = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		SET @Permesso = 0;

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
			GOTO BRANCH_END;

		DECLARE @permessoFunzione INT;

		-- Registrazione
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				r.Id = @IdRecord
				AND r.Lock < 2
		)
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'RRG',
				@Permesso = @permessoFunzione OUTPUT;

			SET @permessoFunzione = ISNULL(@permessoFunzione, 0);
			SET @Permesso = IIF(@permessoFunzione > 2, 2, @permessoFunzione);
			GOTO BRANCH_END;
		END

		-- Autorizzazione
		DECLARE @idUtente CHAR(16);
		DECLARE @idAzienda CHAR(16);
		SELECT
			@idUtente = IdUtente,
			@idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @isProprietaria BIT = 0;
		DECLARE @isVisibile BIT = 0;

		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			WHERE
				a.Id = @IdRecord
				AND a.Lock < 2
				AND s.IdAziendaInterna = @idAzienda
		)
			SET @isProprietaria = 1;
		ELSE IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.IdAziendaInterna = i.Id
			WHERE
				a.Id = @IdRecord
				AND a.Lock < 2
		)
		OR EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(@idUtente) x ON s.Id = x.Id
			WHERE
				a.Id = @IdRecord
				AND a.Lock < 2
				AND x.IdAziendaInterna <> @idAzienda
		)
			SET @isVisibile = 1;

		IF @isProprietaria = 1 OR @isVisibile = 1
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'RAT',
				@Permesso = @permessoFunzione OUTPUT;

			SET @permessoFunzione = ISNULL(@permessoFunzione, 0);
			SET @Permesso = IIF(@permessoFunzione > IIF(@isProprietaria = 1, 2, 1), IIF(@isProprietaria = 1, 2, 1), @permessoFunzione);
		END

	END TRY
	BEGIN CATCH
		-- Fail-safe: nega l'accesso senza far saltare la SP chiamante
		SET @Permesso = 0;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;

END;
GO
