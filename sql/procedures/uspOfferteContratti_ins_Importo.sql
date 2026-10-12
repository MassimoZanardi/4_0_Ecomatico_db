SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Associa un importo a un contratto o a un'offerta (attivo o in bozza) dell'azienda interna corrente della
-- sessione. Un importo sta in un solo contratto o offerta (UX_OfferteContrattiImporti_IdImporto): quello già
-- associato altrove non si sposta da qui, va prima tolto dall'altro. L'importo deve essere attivo, della stessa
-- azienda e di un modulo attivo sul dominio. Già associato a questo contratto: nessuna azione.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_ins_Importo
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = oc.IdSede
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione
			AND oc.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		-- L'importo: attivo, della stessa azienda, di un modulo attivo sul dominio
		DECLARE @idModulo CHAR(3);
		SELECT
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN v.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi v ON i.Id = v.Id
		WHERE
			i.Id = @IdImporto
			AND i.IdSede = @idAzienda
			AND i.Lock = 0;

		IF @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DECLARE @idAltro CHAR(16);
			SELECT @idAltro = IdOffertaContratto
			FROM dbo.tblOfferteContrattiImporti WITH (UPDLOCK, HOLDLOCK)
			WHERE IdImporto = @IdImporto;

			IF @idAltro IS NOT NULL AND @idAltro <> @Id
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo è già associato a un altro contratto o a un''altra offerta';
				GOTO BRANCH_END;
			END

			IF @idAltro IS NULL
				INSERT dbo.tblOfferteContrattiImporti (IdOffertaContratto, IdImporto)
				VALUES (@Id, @IdImporto);
		COMMIT TRANSACTION;

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
		THROW 50001, @returnMessage, 1;
	END
END;
GO
