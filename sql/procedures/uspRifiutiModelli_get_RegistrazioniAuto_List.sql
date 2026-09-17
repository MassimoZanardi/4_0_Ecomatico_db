SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_get_RegistrazioniAuto_List]
	@IdModello CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
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

		SELECT
			ra.Id,
			ra.Posizione,
			ra.Percentuale,
			ra.IdEer,
			EerNome = eer.Nome + ISNULL(' - ' + eer.Descrizione, ''),
			ra.IdMateriale,
			MaterialeNome = mat.Nome,
			ra.IdStatoFisico,
			StatoFisicoNome = sf.Nome,
			ra.IdUnitaMisura,
			Etichette = (
				SELECT
					e.Nome,
					Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
					e.Descrizione,
					e.Visualizzazione
				FROM
					dbo.tblRifiutiModelliRegistrazioniAutoEtichette re
					INNER JOIN dbo.tblEtichette e ON re.IdEtichetta = e.Id
					INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
				WHERE re.Id = ra.Id
				FOR JSON PATH)
		FROM
			dbo.tblRifiutiModelliRegistrazioniAuto ra
			LEFT JOIN dbo.tblRifiutiEer eer ON ra.IdEer = eer.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON ra.IdMateriale = mat.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici sf ON ra.IdStatoFisico = sf.Id
		WHERE
			ra.IdModello = @IdModello
			AND ra.Lock = 0
		ORDER BY ra.Posizione
		OPTION (RECOMPILE);

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
