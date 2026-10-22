SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Soggetti dell'Allegato VII con il loro operatore DIWASS (Ruolo O chi organizza, P produttore, D destinatario,
-- I impianto, T trasportatore)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Soggetti]
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

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			x.Ruolo,
			x.Pos,
			x.IdSede,
			SedeNome = s.NomeCompleto,
			o.OperatorInternalId,
			OperatoreNome = o.Nome,
			x.ContattoNome,
			x.ContattoTelefono,
			x.ContattoEmail,
			x.MezzoTrasporto,
			x.ImpiantoIntermedio,
			x.NomeRiservato,
			x.MotivoRiservatezza
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
		WHERE x.Id = @Id
		ORDER BY x.Ruolo, x.Pos;

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
