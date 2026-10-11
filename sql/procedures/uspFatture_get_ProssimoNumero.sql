SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Numero che la fattura riceverebbe al salvataggio con il tipo di documento, il sezionale e le date
-- scelti nella scheda (anche se non ancora salvati). È solo un suggerimento: il numero definitivo lo
-- assegna uspFatture_upd, con la stessa regola. 0 = nessun numero (pre-fattura).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_ProssimoNumero
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(4) = NULL,
	@Sezionale CHAR(1) = NULL,
	@DataEmissione DATE = NULL,
	@DataRegistrazione DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4)));
		SET @Sezionale = NULLIF(UPPER(LTRIM(RTRIM(@Sezionale))), '');

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @tipo CHAR(1);
		SELECT
			@idAzienda = f.IdSede,
			@tipo = f.Tipo
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END

		-- Stessa regola di uspFatture_upd: progressivo per azienda, tipo (clienti / fornitori), anno e
		-- sezionale tra le fatture attive. L'anno è quello della data di emissione per le fatture cliente,
		-- della data di registrazione per le fatture fornitore; senza data vale oggi
		DECLARE @dataNumero DATE = ISNULL(IIF(@tipo = 'C', @DataEmissione, @DataRegistrazione), CAST(GETDATE() AS DATE));
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@dataNumero), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @numero INT = 0;

		-- La pre-fattura non ha numero
		IF ISNULL(@IdTipo, '') <> 'TD00'
		BEGIN
			-- Due letture, una per tipo, con il filtro sulla colonna della data (come in uspFatture_upd)
			IF @tipo = 'C'
				SELECT @numero = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblFatture
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataEmissione >= @annoInizio
					AND DataEmissione < @annoFine;
			ELSE
				SELECT @numero = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblFatture
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataRegistrazione >= @annoInizio
					AND DataRegistrazione < @annoFine;
		END

		SELECT Numero = @numero;

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
