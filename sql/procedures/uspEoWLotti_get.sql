SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLotti
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			l.Id,
			l.IdSede,
			SedeNome = s.Nome,
			l.IdMagazzino,
			MagazzinoNome = g.Nome,
			l.IdMateriale,
			MaterialeNome = m.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAttribuita, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			l.Lock
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			OUTER APPLY (
				SELECT QuantitaAttribuita = SUM(r.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni r
				WHERE r.IdLotto = l.Id
			) q
		WHERE
			l.Id = @Id
			AND l.Lock <= 2;

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
