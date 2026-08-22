CREATE OR ALTER PROCEDURE [dbo].[uspEventi_get_Ricorrenza]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL
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

		-- Titolarità: nessun controllo esisteva — chiunque avesse una sessione valida
		-- poteva leggere la classificazione di ricorrenza di un evento di un'altra
		-- azienda conoscendone l'Id. Stesso pattern già usato in uspEventi_upd_Proprieta.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE e.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Evento non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			Ricorrenza = CASE
				WHEN r.Id IS NOT NULL AND @Data IS NULL THEN 1
				WHEN r.Id IS NOT NULL AND e.[Data] <> @Data THEN 1
				WHEN r.Id IS NOT NULL AND e.[Data] = @Data THEN 3
				WHEN z.IdEvento IS NOT NULL THEN 2
				ELSE 0
			END
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblEventiStati t ON e.IdStato = t.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.IdEvento AND z.Lock = 0
		WHERE e.Id = @Id;

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
