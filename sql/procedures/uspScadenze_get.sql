CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get]
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
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblScadenze s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblScadenze s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			WHERE
				s.Id = @Id
				AND e.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Scadenza non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			IdEvento = ISNULL(s.IdEvento, ''),
			Descrizione = ISNULL(s.Descrizione, ''),
			IdStato = ISNULL(e.IdStato, 'D'),
			[Data] = ISNULL(e.[Data],
									 DATEADD(MINUTE, ((DATEDIFF(MINUTE, 0, GETDATE()) / 30) * 30), 0)),
			InGiornata = ISNULL(e.InGiornata, 0),
			Ricorre = CAST(IIF(r.Id IS NULL, 0, 1) AS BIT),
			Avviso = CAST(IIF(e.AvvisoAnticipo IS NULL, 0, 1) AS BIT),
			Email = ISNULL(e.Email, ''),
			AvvisoAnticipo = ISNULL(e.AvvisoAnticipo, 0),
			IdIntervallo = ISNULL(r.IdIntervallo, 'DD'),
			Frequenza = ISNULL(r.Frequenza, 1),
			Ripetizioni = ISNULL(r.Ripetizioni, 0),
			Relativo = ISNULL(r.Relativo, 0),
			Eccezione = CAST(IIF(z.IdEvento IS NULL, 0, 1) AS BIT),
			DataFine = ISNULL(r.DataFine, '2050-12-31 23:59:00'),
			RicorrenzaTermine = CASE
				WHEN r.Ripetizioni > 0 THEN 2
				WHEN r.DataFine < '2050-12-31 23:59:00' THEN 1
				ELSE 0
			END,
			Proprieta = dbo.ufnEventi_get_TipoProprieta(s.IdEvento, s.IdTipo),
			e.Lock
		FROM
			dbo.tblScadenze s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.IdEvento
													 AND z.Lock <= 2
		WHERE
			s.Id = @Id
			AND e.Lock <= 2;

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
