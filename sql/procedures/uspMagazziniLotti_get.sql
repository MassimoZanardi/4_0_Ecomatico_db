SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get
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
				dbo.tblMagazziniLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato';
			GOTO BRANCH_END;
		END

		-- Disponibilità = carichi confermati - scarichi confermati (mai memorizzata)
		SELECT
			l.Id,
			l.IdSede,
			l.IdArticolo,
			ArticoloNome = art.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaCaricata = ISNULL(q.Caricato, 0),
			QuantitaScaricata = ISNULL(q.Scaricato, 0),
			Disponibilita = ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.Caricato, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			l.Lock
		FROM
			dbo.tblMagazziniLotti l
			LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
			OUTER APPLY (
				SELECT
					Caricato = SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl.Quantita ELSE 0 END),
					Scaricato = SUM(CASE WHEN mv.IdOperazione = 'S' THEN rl.Quantita ELSE 0 END)
				FROM
					dbo.tblMagazziniMovimentiRigheLotti rl
					INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
					INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
				WHERE
					rl.IdLotto = l.Id
					AND r.Lock = 0
					AND mv.Lock = 0
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
