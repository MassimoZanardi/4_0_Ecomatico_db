CREATE OR ALTER PROCEDURE [dbo].[uspPersone_get]
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
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		DECLARE @idAzienda CHAR(16);

		SELECT @idUtente = IdUtente,
			   @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Titolarità: la persona è visibile se appartiene a un'azienda interna dell'utente
		-- OPPURE se è condivisa da un'altra azienda tramite Area comune (vedi Ramo 2 di
		-- uspPersone_get_List, che già lista queste persone condivise). La sola lettura è
		-- permessa qui; la modifica resta bloccata da uspPersone_upd (che confronta IdSede
		-- con l'azienda specifica della sessione).
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblPersone p
			INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@idUtente) i
					   ON p.IdSede = i.Id
			WHERE p.Id = @Id)
		AND NOT EXISTS (
			SELECT 1
			FROM dbo.ufnPersone_get_CondiviseByUtente_List(@idUtente) c
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblPersone
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Persona non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			p.Id,
			p.IdSede,
			Nome = ISNULL(p.Nome, ''),
			Cognome = ISNULL(p.Cognome, ''),
			Disabilitata = CAST(ISNULL(p.Disabilitata, 0) AS BIT),
			IdUnitaMisura = ISNULL(p.IdUnitaMisura, 'HR'),
			ImpiegabileServizi = ISNULL(p.ImpiegabileServizi, 0),
			Condivisa = CAST(IIF(c.Id IS NULL, 0, 1) AS BIT),
			CondivisaDaArea = ISNULL(c.Area, ''),
			CondivisaDaAltri = CAST(IIF(@idAzienda = p.IdSede, 0, 1) AS BIT),
			p.Lock
		FROM
			dbo.tblPersone p
			OUTER APPLY (
				SELECT TOP 1
					ae.Id,
					Area = a.Nome
				FROM dbo.tblAreeOsepe ae
				INNER JOIN dbo.tblAree a ON ae.Id = a.Id
				WHERE
					a.Lock = 0
					AND ae.IdOsepe = p.Id
			) c
		WHERE
			p.Id = @Id
			AND p.Lock <= 2;

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
