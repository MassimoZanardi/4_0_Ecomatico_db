CREATE PROCEDURE [dbo].[uspTipi_del_Proprieta]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');

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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (TPO = Gestione Tipi)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Rimuove la proprietà dagli eventi scadenza del tipo
			DELETE e
			FROM dbo.tblScadenze s
			INNER JOIN dbo.tblEventiProprieta e ON s.IdEvento = e.Id
			WHERE
				s.IdTipo = @Id
				AND e.IdProprieta = @IdProprieta;
			-- Rimuove la proprietà dagli eventi servizio del tipo
			DELETE e
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventiProprieta e ON s.IdEvento = e.Id
			WHERE
				s.IdTipo = @Id
				AND e.IdProprieta = @IdProprieta;
			-- Rimuove la proprietà dal tipo
			DELETE dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta;
			-- Ricompatta le posizioni rimanenti
			UPDATE r
			SET Pos = t.Pos
			FROM dbo.tblTipiProprieta r
			INNER JOIN (
					   SELECT
						   IdProprieta,
						   Pos = ROW_NUMBER() OVER (ORDER BY Pos)
					   FROM dbo.tblTipiProprieta
					   WHERE Id = @Id) t ON r.IdProprieta = t.IdProprieta
			WHERE r.Id = @Id;
		COMMIT TRANSACTION;
		-- Log FUORI dalla transazione: uspId_upd gestisce la propria transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';
		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END
END;
