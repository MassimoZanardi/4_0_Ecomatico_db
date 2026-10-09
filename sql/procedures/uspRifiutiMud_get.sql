SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMud_get]
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
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		-- (tblSessioni.IdAzienda), non tutte le aziende accessibili all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiMud c
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiMud
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dichiarazione MUD non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			c.Id,
			c.IdSede,
			c.IdSedeLegale,
			SedeLegaleNome = sl.Nome + ' ' + sl.IndirizzoCompleto,
			LegaleNome = ld.LegaleNome,
			LegaleCognome = ld.LegaleCognome,
			c.IdSedeUnitaLocale,
			SedeUnitaLocaleNome = su.Nome + ' ' + su.IndirizzoCompleto,
			IdAteco = ud.IdAteco,
			AtecoDescrizione = a.Descrizione,
			NumeroRea = ud.NumeroRea,
			Dipendenti = ud.Dipendenti,
			c.Data,
			c.Anno,
			c.DataGenerazione,
			c.Lock
		FROM
			dbo.tblRifiutiMud c
			LEFT JOIN dbo.tblSedi sl ON c.IdSedeLegale = sl.Id
			LEFT JOIN dbo.tblSediDatiEstesi ld ON sl.Id = ld.Id
			LEFT JOIN dbo.tblSedi su ON c.IdSedeUnitaLocale = su.Id
			LEFT JOIN dbo.tblSediDatiEstesi ud ON su.Id = ud.Id
			LEFT JOIN dbo.tblAteco a ON ud.IdAteco = a.Id
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
