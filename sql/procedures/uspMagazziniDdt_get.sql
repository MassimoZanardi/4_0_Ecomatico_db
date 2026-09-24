SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			d.Id,
			d.IdMovimento,
			d.IdSede,
			SedeNome = si.NomeCompleto,
			d.IdCausale,
			CausaleNome = c.Nome,
			d.Numero,
			d.NumeroFornitore,
			d.Sezionale,
			d.Data,
			d.IdMittente,
			MittenteNome = sm.NomeCompleto,
			d.IdDestinatario,
			DestinatarioNome = sd.NomeCompleto,
			d.IdTrasportatore,
			TrasportatoreNome = st.NomeCompleto,
			d.DataInizioTrasporto,
			d.Peso,
			d.Lock
		FROM
			dbo.tblMagazziniDdt d
			LEFT JOIN dbo.tblSedi si ON d.IdSede = si.Id
			LEFT JOIN dbo.tblMagazziniCausali c ON d.IdCausale = c.Id
			LEFT JOIN dbo.tblSedi sm ON d.IdMittente = sm.Id
			LEFT JOIN dbo.tblSedi sd ON d.IdDestinatario = sd.Id
			LEFT JOIN dbo.tblSedi st ON d.IdTrasportatore = st.Id
		WHERE
			d.IdMovimento = @IdMovimento
			AND d.Lock <= 2;

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
