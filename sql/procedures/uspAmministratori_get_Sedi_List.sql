SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_get_Sedi_List
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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAmministratori c
				INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Soggetti amministrati della scheda, con le date dell'incarico
		SELECT
			Id = x.IdSede,
			s.NomeCompleto,
			s.IndirizzoCompleto,
			s.CodiceFiscale,
			s.PartitaIva,
			x.DataInizio,
			x.DataFine,
			StatoValore = CASE WHEN s.Disabilitata = 1 THEN 2 ELSE 0 END,
			StatoDescrizione = CASE WHEN s.Disabilitata = 1 THEN 'Anagrafica del soggetto disabilitata' ELSE 'OK' END
		FROM
			dbo.tblAmministratoriSedi x
			INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
		WHERE x.Id = @Id
		ORDER BY s.NomeCompleto;

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
