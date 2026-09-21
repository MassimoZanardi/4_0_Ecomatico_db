SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_get_RegistrazioniAuto]
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: stesso pattern di uspRifiutiModelli_get_Etichette_SelectList, incatenato da
		-- tblRifiutiModelliRegistrazioniAuto a tblRifiutiModelli.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelliRegistrazioniAuto ra
				INNER JOIN dbo.tblRifiutiModelli m ON ra.IdModello = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE ra.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- EerNome/MaterialeNome: mancavano del tutto - il payload JSON arrivava al modale di modifica
		-- (Pages/Rifiuti/Modelli/Edit.cshtml, registrazioneAutoEdit) senza la descrizione necessaria
		-- per aggiungere l'opzione mancante nella select EER quando il codice non è tra quelle già
		-- caricate a inizio pagina - stessa risoluzione già presente in
		-- uspRifiutiModelli_get_RegistrazioniAuto_List, qui replicata.
		SELECT
			ra.Id,
			ra.IdModello,
			ra.Posizione,
			ra.Percentuale,
			IsMateriale = CAST(IIF(ra.IdMateriale IS NOT NULL, 1, 0) AS BIT),
			ra.IdEer,
			EerNome = eer.Nome + ISNULL(' - ' + eer.Descrizione, ''),
			ra.IdMateriale,
			MaterialeNome = mat.Nome,
			ra.IdStatoFisico,
			ra.IdUnitaMisura,
			IdEtichette = (
				SELECT STRING_AGG(IdEtichetta, ';')
				FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				WHERE Id = ra.Id)
		FROM
			dbo.tblRifiutiModelliRegistrazioniAuto ra
			LEFT JOIN dbo.tblRifiutiEer eer ON ra.IdEer = eer.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON ra.IdMateriale = mat.Id
		WHERE ra.Id = @Id;

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
