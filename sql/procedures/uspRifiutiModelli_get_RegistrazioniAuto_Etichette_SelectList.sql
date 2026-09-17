SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_get_RegistrazioniAuto_Etichette_SelectList]
	@IdModello CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdModello IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModello non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: stesso pattern di uspRifiutiModelli_get_Etichette_SelectList.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @IdModello)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- @Id: riga tblRifiutiModelliRegistrazioniAuto in modifica (NULL in inserimento, nessuna
		-- etichetta preselezionata).
		SELECT
			Id = t.Id,
			[Text] =
				(SELECT
					e.Nome,
					Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
					e.Descrizione,
					e.Visualizzazione
				FROM
					dbo.tblEtichette e
					INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
				WHERE t.Id = e.Id FOR JSON PATH),
			Selected = CAST(IIF(re.IdEtichetta IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblEtichette t
			LEFT OUTER JOIN (
				SELECT IdEtichetta
				FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				WHERE Id = @Id) re ON t.Id = re.IdEtichetta
		WHERE
			t.IdSede = (
				SELECT g.IdSede
				FROM
					dbo.tblRifiutiModelli m
					INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				WHERE m.Id = @IdModello
			)
			AND t.IdModulo = 'RIF'
			AND t.Lock = 0
		ORDER BY
			Selected DESC, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
