CREATE OR ALTER PROCEDURE [dbo].[uspEventi_upd_Sessione]
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

		-- Titolarità: prima nessun controllo verificava che @Id (Scadenza/Servizio)
		-- appartenesse a un calendario/sede accessibile dalla sessione — la SP
		-- impostava tblSessioni.IdCalendario fidandosi ciecamente del valore letto.
		-- tblSessioni.IdCalendario è poi usato come confine di titolarità da altre SP
		-- (es. uspScadenze_get_CalendarioMese_List), quindi il gap permetteva di
		-- "spostare" la propria sessione sul calendario di un'altra azienda
		-- conoscendo/indovinando l'Id di una sua Scadenza o Servizio.
		IF EXISTS (SELECT 1
		FROM dbo.tblScadenze
		WHERE Id = @Id)
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblScadenze s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
				WHERE s.Id = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblSessioni
			SET IdCalendario = ( SELECT e.IdCalendario FROM dbo.tblScadenze s INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id WHERE s.Id = @Id )
			WHERE Id = @IdSessione;
		END

		ELSE IF EXISTS (SELECT 1
		FROM dbo.tblServizi
		WHERE Id = @Id)
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
				WHERE s.Id = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblSessioni
			SET IdCalendario = ( SELECT e.IdCalendario FROM dbo.tblServizi s INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id WHERE s.Id = @Id )
			WHERE Id = @IdSessione;
		END

		SELECT @returnValue AS ReturnValue;

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
