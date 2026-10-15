SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get
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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @tipo CHAR(1);
		SELECT @tipo = c.Tipo
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @tipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato', 'Fornitore non trovato');
			GOTO BRANCH_END;
		END

		-- I dati anagrafici del soggetto sono in sola lettura: si modificano in Anagrafica > Soggetti
		SELECT
			c.Id,
			c.IdAziendaInterna,
			c.IdSede,
			c.Tipo,
			c.IdModalita,
			c.IdRata,
			c.IdRataInizio,
			c.IdBancaCassa,
			c.IdAliquotaIva,
			c.IdValuta,
			SplitPayment = ISNULL(c.SplitPayment, 0),
			c.Iban,
			RataGiorniInizio = ISNULL(c.RataGiorniInizio, 0),
			ImportoMinimoFatturabile = ISNULL(c.ImportoMinimoFatturabile, 0),
			RitenutaAcconto = ISNULL(c.RitenutaAcconto, 0),
			c.CodiceDestinatario,
			c.PecDestinatario,
			c.Note,
			-- Raggruppamento delle fatture: per i clienti, per cliente (C) se non indicato
			IdRaggruppamento = IIF(c.Tipo = 'C', ISNULL(c.IdRaggruppamento, 'C'), NULL),
			c.Lock,
			SedeNomeCompleto = s.NomeCompleto,
			SedeIndirizzoCompleto = s.IndirizzoCompleto,
			SedeCodiceFiscale = s.CodiceFiscale,
			SedePartitaIva = s.PartitaIva,
			SedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM
			dbo.tblClientiFornitori c
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

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
