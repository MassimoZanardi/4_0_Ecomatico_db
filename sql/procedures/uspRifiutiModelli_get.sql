CREATE PROCEDURE [dbo].[uspRifiutiModelli_get]
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: prima scattava solo per Lock=0, lasciando le bozze Lock=2 di
		-- altre aziende leggibili da chiunque avesse permesso RMD — ora incondizionata,
		-- stesso pattern già corretto su uspRifiutiAutorizzazioni_get/uspRifiutiFormulari_get.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			m.Id,
			m.IdRegistro,
			Nome = ISNULL(m.Nome, ''),
			IdOperazione = ISNULL(m.IdOperazione, '0'),
			OperazioneNome = ISNULL(o.Nome, ''),
			IdEer = ISNULL(m.IdEer, '000000'),
			IdStatoFisico = ISNULL(m.IdStatoFisico, '0'),
			IdAttivitaRs = ISNULL(m.IdAttivita, '00'),
			IdUnitaMisura = ISNULL(m.IdUnitaMisura, 'KG'),
			IdAutorizzazioneProduttoreDetentore = ISNULL(m.IdAutorizzazioneProduttoreDetentore, REPLICATE('0', 16)),
			IdAutorizzazioneDestinatario = ISNULL(m.IdAutorizzazioneDestinatario, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore1 = ISNULL(m.IdAutorizzazioneTrasportatore1, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario1 = ISNULL(m.IdAutorizzazioneIntermediario1, REPLICATE('0', 16)),
			IdTipoTrasporto1 = ISNULL(m.IdTipoTrasporto1, 'G'),
			IdAdr = ISNULL(m.IdAdr, '00'),
			IdImballo = ISNULL(m.IdImballo, '00'),
			Note = ISNULL(m.Note, ''),
			UtenteNote = ISNULL(m.UtenteNote, ''),
			t.IsProduttore,
			t.IsTrasportatore,
			t.IsDestinatario,
			t.IsIntermediario,
			t.IsAttivitaRs,
			m.Lock
		FROM
			dbo.tblRifiutiModelli m
		LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		LEFT JOIN dbo.tblRifiutiOperazioniRegistro t ON o.Id = t.Id
		WHERE
			m.Id = @Id
			AND m.Lock <= 2;

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
