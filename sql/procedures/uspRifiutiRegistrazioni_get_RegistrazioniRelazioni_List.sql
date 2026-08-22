CREATE PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_RegistrazioniRelazioni_List]
	@IdParent CHAR(16) = NULL,
	@Verso INT,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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
			@IdFunzione = 'RRG',
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
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @tbl TABLE (
			Pos INT IDENTITY(1, 1),
			Id CHAR(16),
			IdOperazione CHAR(1),
			Numero INT,
			[Data] DATE,
			Quantita DECIMAL(18, 2),
			Relazione INT,
			QuantitaAssociata DECIMAL(18, 2)
		);

		-- Inserisce la registrazione padre come punto di partenza
		-- FIX: Quantita spostata da tblRifiutiRegistrazioni (r) a tblRifiutiMovimenti (m)
		INSERT INTO @tbl (Id, IdOperazione, Numero, [Data], Quantita, Relazione, QuantitaAssociata)
		SELECT
			r.Id,
			m.IdOperazione,
			r.Numero,
			r.[Data],
			m.Quantita,
			NULL,
			NULL
		FROM dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		-- Verso = 0: scende verso le figlie (registrazioni associate come IdParent)
		IF @Verso = 0
		WHILE 1 = 1
		BEGIN
			INSERT INTO @tbl (Id, IdOperazione, Numero, [Data], Quantita, Relazione, QuantitaAssociata)
			SELECT Id, IdOperazione, Numero, [Data], Quantita, Relazione, QuantitaAssociata
			FROM (
				SELECT
					r.Id,
					m.IdOperazione,
					r.Numero,
					r.[Data],
					m.Quantita,
					Relazione = t.Numero,
					QuantitaAssociata = l.Quantita
				FROM
					@tbl t
					INNER JOIN dbo.tblRifiutiRegistrazioniRelazioni l ON t.Id = l.IdParent
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE r.Lock = 0) x
			WHERE
				x.Id NOT IN (SELECT Id FROM @tbl)
				AND YEAR(x.[Data]) + x.Numero < (SELECT MIN(YEAR([Data]) + Numero) FROM @tbl);

			IF @@ROWCOUNT = 0 BREAK;
		END

		-- Verso = 1: sale verso i padri (registrazioni che hanno questa come figlia)
		ELSE
		WHILE 1 = 1
		BEGIN
			INSERT INTO @tbl (Id, IdOperazione, Numero, [Data], Quantita, Relazione, QuantitaAssociata)
			SELECT Id, IdOperazione, Numero, [Data], Quantita, Relazione, QuantitaAssociata
			FROM (
				SELECT
					r.Id,
					m.IdOperazione,
					r.Numero,
					r.[Data],
					m.Quantita,
					Relazione = t.Numero,
					QuantitaAssociata = l.Quantita
				FROM
					@tbl t
					INNER JOIN dbo.tblRifiutiRegistrazioniRelazioni l ON t.Id = l.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.IdParent = r.Id
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE r.Lock = 0) x
			WHERE
				x.Id NOT IN (SELECT Id FROM @tbl)
				AND YEAR(x.[Data]) + x.Numero > (SELECT MAX(YEAR([Data]) + Numero) FROM @tbl);

			IF @@ROWCOUNT = 0 BREAK;
		END

		SELECT TOP 100
			Operazione = o.Nome,
			t.Numero,
			t.[Data],
			Quantita = t.QuantitaAssociata,
			RelazioneNumero = t.Relazione
		FROM
			@tbl t
			LEFT JOIN dbo.tblRifiutiOperazioni o ON t.IdOperazione = o.Id
		WHERE t.Relazione IS NOT NULL
		ORDER BY t.Pos;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
