SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_get_List]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtenteSessione CHAR(16);
		SELECT @idUtenteSessione = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtenteSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		-- Titolarità: l'esecutore può gestire se stesso, oppure - da Amministratore - qualunque
		-- utente del proprio Dominio (o di qualunque Dominio se appartiene a un Dominio Master).
		-- Stesso schema di uspUtenti_upd.
		IF @idUtenteSessione <> @IdUtente
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti target
				INNER JOIN dbo.tblUtenti admin ON admin.IdDominio = target.IdDominio
				WHERE
					target.Id = @IdUtente
					AND admin.Id = @idUtenteSessione
					AND admin.IdRuolo = 'AD'
					AND admin.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti target
				INNER JOIN dbo.tblUtenti admin ON admin.Id = @idUtenteSessione
				INNER JOIN dbo.tblDomini d ON admin.IdDominio = d.Id
				WHERE
					target.Id = @IdUtente
					AND admin.IdRuolo = 'AD'
					AND admin.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblUtenti WHERE Id = @IdUtente AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato';
			GOTO BRANCH_END;
		END

		-- Elenco per SedeInterna (l'unità locale RENTRI, terminologia riconoscibile), non per
		-- Credenziale/operatore: più sedi del TARGET possono condividere la stessa credenziale
		-- primaria (Pos = 0), nel qual caso compaiono come righe distinte con lo stesso stato -
		-- coerente con quanto verificato in produzione (stesso PIN operativo su più sedi).
		-- IdCredenziale resta comunque il valore selezionato/usato dalle chiamate successive.
		SELECT
			s.Id AS IdSede,
			s.NomeCompleto AS SedeNome,
			s.IndirizzoCompleto AS Indirizzo,
			cs.IdCredenziale,
			Collegata = CASE WHEN f.IdUtente IS NOT NULL AND f.Lock = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
			DataBoarding = CASE WHEN f.Lock = 0 THEN f.DataBoarding ELSE NULL END
		FROM
			dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) su
			INNER JOIN dbo.tblSedi s ON s.Id = su.Id
			INNER JOIN dbo.tblRentriCredenzialiSedi cs ON cs.IdSede = s.Id AND cs.Pos = 0
			INNER JOIN dbo.tblRentriCredenziali c ON c.Id = cs.IdCredenziale AND c.Lock <= 2
			LEFT JOIN dbo.tblRentriFirmeCredenziali f ON f.IdCredenziale = cs.IdCredenziale AND f.IdUtente = @IdUtente
		ORDER BY s.NomeCompleto;

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
