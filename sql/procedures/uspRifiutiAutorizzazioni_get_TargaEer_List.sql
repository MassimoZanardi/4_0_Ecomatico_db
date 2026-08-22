CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get_TargaEer_List]
	@Id CHAR(16) = NULL,
	@Numero VARCHAR(20) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Numero = dbo.ufnStringhe_get_SenzaSpazi(@Numero, 0, 1);
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
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		DECLARE @idAzienda CHAR(16);
		SELECT @idUtente = IdUtente,
			   @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Titolarità: stesso controllo di uspRifiutiAutorizzazioni_get.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.IdAziendaInterna = i.Id
			WHERE a.Id = @Id)
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(@idUtente) x ON s.Id = x.Id
			WHERE
				a.Id = @Id
				AND x.IdAziendaInterna <> @idAzienda
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Restituisce gli EER dell'autorizzazione con flag Checked:
		-- Checked = 1 → EER abilitato per questa targa (non escluso)
		-- Checked = 0 → EER escluso per questa targa
		SELECT
			Id = e.Id,
			[Text] = e.Nome + IIF(e.Pericoloso = 1, '*', ''),
			Checked = CAST(IIF(t.IdEer IS NULL, 1, 0) AS BIT),
			Description = e.Descrizione
		FROM
			dbo.tblRifiutiAutorizzazioniEer a
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniTargheEerEsclusi t
				ON a.Id = t.Id AND e.Id = t.IdEer AND t.Targa = @Numero
		WHERE a.Id = @Id
		ORDER BY
			e.Id;

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
