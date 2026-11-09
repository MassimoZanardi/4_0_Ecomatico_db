SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dopo una conferma registrata su DIWASS (docs/regole/diwass.md D7): ricorda il ruolo di chi ha firmato, proposto alla
-- conferma o all'invio successivo dello stesso utente per l'azienda (tblDiwassFirmeRuoli, come all'invio). La conferma
-- arriva in tblDiwassAllegatiViiConferme con l'importazione del documento riletto dall'hub
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd_Conferma]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@FirmaRuolo VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @FirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@FirmaRuolo, 0, 1);

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
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @FirmaRuolo IS NOT NULL
			MERGE dbo.tblDiwassFirmeRuoli AS t
			USING (
				SELECT
					IdUtente = @idUtente,
					IdAziendaInterna = @idAzienda,
					Ruolo = @FirmaRuolo
			) AS s
			ON t.IdUtente = s.IdUtente AND t.IdAziendaInterna = s.IdAziendaInterna
			WHEN MATCHED THEN UPDATE
			SET Ruolo = s.Ruolo WHEN NOT MATCHED THEN INSERT (IdUtente, IdAziendaInterna, Ruolo) VALUES (s.IdUtente, s.IdAziendaInterna, s.Ruolo);

		SELECT rtn = 1;

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
