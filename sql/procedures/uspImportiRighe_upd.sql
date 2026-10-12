SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Aggiunge una riga a un importo (@Id NULL, in coda) o la modifica. Vale per gli importi di rifiuti, magazzino
-- e servizi: il tipo di riga deve essere del modulo dell'importo.
-- Riga con importo: il tipo dice per che cosa si moltiplica (una volta per documento, oppure per la quantità).
-- Riga di sola descrizione (@Importo NULL): in fattura dà una riga di testo, una per documento; aliquota IVA e
-- conto non contano.
-- Minimo fatturabile: l'importo della riga è il minimo da fatturare per documento; al massimo una per importo.
-- Aliquota IVA facoltativa: se manca, la fatturazione usa quella della scheda del cliente.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_upd
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(2) = NULL,
	@Importo DECIMAL(18, 4) = NULL,
	@MinimoFatturabile BIT = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdConto CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(UPPER(LTRIM(RTRIM(@IdTipo))), '');
		SET @MinimoFatturabile = ISNULL(@MinimoFatturabile, 0);
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');

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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Riga esistente: l'importo è quello della riga
		DECLARE @idAliquotaIvaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			SET @IdImporto = NULL;
			SELECT
				@IdImporto = g.IdImporto,
				@idAliquotaIvaAttuale = d.IdAliquotaIva,
				@idContoAttuale = d.IdConto
			FROM
				dbo.tblImportiRighe g
				LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
			WHERE g.Id = @Id;
		END

		-- L'importo deve esistere (in bozza o attivo), appartenere all'azienda interna corrente della sessione
		-- e il suo modulo deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @IdImporto
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		IF @Descrizione IS NULL OR LEN(@Descrizione) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il testo della riga in fattura (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END

		DECLARE @conImporto BIT = IIF(@Importo IS NULL, 0, 1);
		IF @conImporto = 1
		BEGIN
			IF @IdTipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblImportiRigheTipi WHERE Id = @IdTipo AND IdModulo = @idModulo)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare a che cosa si applica l''importo della riga';
				GOTO BRANCH_END;
			END
			IF @Importo < 0.0001 OR @Importo > 999999.9999
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo deve essere compreso tra 0,0001 e 999.999,9999';
				GOTO BRANCH_END;
			END
			-- Aliquota IVA: facoltativa, di sistema (IdSede NULL) o dell'azienda; quella già sulla riga resta valida
			IF @IdAliquotaIva IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblAliquoteIva
				WHERE
					Id = @IdAliquotaIva
					AND (IdSede IS NULL OR IdSede = @idAzienda)
					AND (Lock = 0 OR Id = @idAliquotaIvaAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''aliquota IVA indicata non esiste';
				GOTO BRANCH_END;
			END
			-- Conto: facoltativo, dell'azienda; quello già sulla riga resta valido
			IF @IdConto IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblFattureConti
				WHERE
					Id = @IdConto
					AND IdSede = @idAzienda
					AND (Lock = 0 OR Id = @idContoAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il conto indicato non esiste';
				GOTO BRANCH_END;
			END
			-- Al massimo una riga con il minimo fatturabile per importo
			IF @MinimoFatturabile = 1 AND EXISTS (
				SELECT 1
				FROM dbo.tblImportiRighe
				WHERE
					IdImporto = @IdImporto
					AND MinimoFatturabile = 1
					AND (@Id IS NULL OR Id <> @Id)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo ha già una riga con il minimo fatturabile';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Sola descrizione: una riga di testo per documento (il tipo "per documento" è il primo del modulo)
			SELECT TOP (1) @IdTipo = Id
			FROM dbo.tblImportiRigheTipi
			WHERE IdModulo = @idModulo
			ORDER BY Pos;

			SET @MinimoFatturabile = 0;
			SET @IdAliquotaIva = NULL;
			SET @IdConto = NULL;
		END

		-- Nuova riga: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
			BEGIN
				-- In coda alle righe dell'importo
				DECLARE @pos INT;
				SELECT @pos = ISNULL(MAX(Pos), 0) + 1
				FROM dbo.tblImportiRighe WITH (UPDLOCK, HOLDLOCK)
				WHERE IdImporto = @IdImporto;

				INSERT dbo.tblImportiRighe (Id, IdImporto, IdTipo, Importo, MinimoFatturabile, Lock, Pos)
				VALUES (@Id, @IdImporto, @IdTipo, @Importo, @MinimoFatturabile, 0, @pos);
			END
			ELSE
			BEGIN
				UPDATE dbo.tblImportiRighe
				SET
					IdTipo = @IdTipo,
					Importo = @Importo,
					MinimoFatturabile = @MinimoFatturabile
				WHERE Id = @Id;
			END

			DELETE dbo.tblImportiRigheDettagli
			WHERE Id = @Id;

			INSERT dbo.tblImportiRigheDettagli (Id, IdAliquotaIva, IdConto, Descrizione)
			VALUES (@Id, @IdAliquotaIva, @IdConto, @Descrizione);
		COMMIT TRANSACTION;

		SELECT Id = @Id;

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
