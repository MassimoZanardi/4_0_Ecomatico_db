CREATE OR ALTER PROCEDURE [dbo].[uspAree_ins_Osepe]
	@Id CHAR(16) = NULL,
	@IdOsepe CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdOsepe = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdOsepe IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdOsepe non può essere vuoto';
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
			@IdFunzione = 'ARE',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Dominio della sessione: l'Area deve appartenere al tenant del chiamante
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblAree
		WHERE
			Id = @Id
			AND IdDominio = @idDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Area non trovata';
			GOTO BRANCH_END;
		END

		-- Titolarità: lo scopo di Aree/Osepe è condividere entità esterne di
		-- un'azienda interna con altre aziende interne DELLO STESSO DOMINIO —
		-- prima non c'era alcuna verifica che @IdOsepe appartenesse allo stesso
		-- Dominio dell'Area, permettendo di collegare (e quindi condividere) entità
		-- di un Dominio/tenant completamente diverso. Risolve Sede/Persona/Oggetto
		-- alla propria Sede "governante" (per una Sede è se stessa) e ne verifica
		-- l'IdAziendaInterna -> IdDominio.
		DECLARE @idSedeOsepe CHAR(16);
		SELECT @idSedeOsepe = CASE o.Tipo
				WHEN 'S' THEN s.Id
				WHEN 'P' THEN p.IdSede
				WHEN 'O' THEN g.IdSede
			END
		FROM
			dbo.tblOsepe o
			LEFT JOIN dbo.tblSedi s ON o.Tipo = 'S' AND o.Id = s.Id
			LEFT JOIN dbo.tblPersone p ON o.Tipo = 'P' AND o.Id = p.Id
			LEFT JOIN dbo.tblOggetti g ON o.Tipo = 'O' AND o.Id = g.Id
		WHERE o.Id = @IdOsepe;

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSedi s
			INNER JOIN dbo.tblSediInterne si ON s.IdAziendaInterna = si.Id
			WHERE
				s.Id = @idSedeOsepe
				AND si.IdDominio = @idDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Upsert: DELETE + INSERT per evitare duplicati su PK (Id, IdOsepe)
			DELETE dbo.tblAreeOsepe
			WHERE
				Id = @Id
				AND IdOsepe = @IdOsepe;

			INSERT INTO dbo.tblAreeOsepe (Id, IdOsepe)
			VALUES (@Id, @IdOsepe);
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione: uspId_upd gestisce la propria transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

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
