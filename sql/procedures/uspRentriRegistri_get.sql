SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get]
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
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistri WHERE Id = @Id AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registro non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.Nome,
			g.IdSede,
			SedeNome = s.NomeCompleto,
			s.IndirizzoCompleto,
			Identificativo = h.Identificativo,
			BloccoFormulari = h.BloccoFormulari,
			DataInizioInvio = h.DataInizioInvio,
			IsCollegato = CAST(IIF(r.IdRentri IS NULL, 0, 1) AS BIT),
			Conservazione = ISNULL(h.Conservazione, 0),
			ConservazioneNome = ISNULL(h.ConservazioneNome, ''),
			ConservazioneCodiceFiscale = ISNULL(h.ConservazioneCodiceFiscale, ''),
			ConservazioneEmail = ISNULL(h.ConservazioneEmail, ''),
			ConservazioniXfirMax = ISNULL(g.ConservazioniXfirMax, 0)
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRentriRegistri r ON g.Id = r.Id
			LEFT JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
		WHERE g.Id = @Id;

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
