-- Deploy produzione 2026-09-29, EoW Allocazioni (2 stored procedure):
-- - uspEoWAllocazioni_ins_Lotto: nuovo parametro @IdAllocazioneTipo (tipo scelto nella pagina). Su un'allocazione
--   non ancora salvata il tipo era NULL e i controlli per tipo venivano saltati (es. due lotti con la stessa
--   priorita'): ora il tipo viene memorizzato con il primo lotto e non si puo' cambiare con lotti presenti.
-- - uspEoWAllocazioni_upd: cambio tipo bloccato con lotti presenti anche su allocazione nuova; al salvataggio i
--   lotti devono rispettare il tipo (priorita' diverse, percentuali entro 100, un solo lotto per Lotto unico).
-- Richiede l'app aggiornata (passa @IdAllocazioneTipo); l'app precedente continua a funzionare (parametro facoltativo).
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -i <questo file>
-- ============================================================ uspEoWAllocazioni_ins_Lotto
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_ins_Lotto
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Valore DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL,
	-- Tipo scelto nella pagina: un'allocazione nuova ha il tipo salvato solo con il primo "Salva",
	-- quindi senza questo parametro i controlli per tipo verrebbero saltati (tipo NULL)
	@IdAllocazioneTipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAllocazioneTipo = NULLIF(LTRIM(RTRIM(@IdAllocazioneTipo)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
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
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @tipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@tipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale dell'allocazione non è un campo proprio: si ricava dal primo lotto aggiunto
		-- e deve restare coerente con gli altri lotti già presenti (nessuna anagrafica/duplicazione
		-- separata, "un'Allocazione = un Materiale" è solo un vincolo, non uno stato memorizzato).
		DECLARE @idMaterialeAllocazione CHAR(2) = (
			SELECT TOP 1 l.IdMateriale
			FROM dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id
		);

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeAllocazione IS NOT NULL AND @idMaterialeLotto <> @idMaterialeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale degli altri lotti già presenti nell''allocazione';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id AND IdLotto = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo lotto è già presente nell''allocazione';
			GOTO BRANCH_END;
		END

		-- Tipo effettivo: con lotti già presenti vale quello salvato (non si può cambiare, come in
		-- uspEoWAllocazioni_upd); senza lotti vale quello scelto nella pagina, che viene memorizzato
		-- insieme al lotto cosi' i controlli sotto non vengono mai saltati.
		DECLARE @isLottiPresenti BIT = IIF(EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id), 1, 0);

		IF @isLottiPresenti = 1 AND @tipo IS NOT NULL AND @IdAllocazioneTipo IS NOT NULL AND @IdAllocazioneTipo <> @tipo
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo di un''allocazione con lotti associati';
			GOTO BRANCH_END;
		END

		DECLARE @isTipoDaSalvare BIT = 0;
		-- (anche con lotti presenti se il tipo non era mai stato salvato: allocazioni create prima di
		-- questo controllo)
		IF (@isLottiPresenti = 0 OR @tipo IS NULL) AND @IdAllocazioneTipo IS NOT NULL AND @IdAllocazioneTipo <> ISNULL(@tipo, '')
		BEGIN
			SET @tipo = @IdAllocazioneTipo;
			SET @isTipoDaSalvare = 1;
		END

		IF @tipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblEoWAllocazioniTipi WHERE Id = @tipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo di allocazione prima di aggiungere i lotti';
			GOTO BRANCH_END;
		END

		-- Validazione specifica per tipo (i valori dei tipi sono in tblEoWAllocazioniTipi: U=Lotto
		-- unico, P=Percentuale, C=Priorità/Capacità)
		IF @tipo = 'U' AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @tipo = 'P' AND (@Valore IS NULL OR @Valore <= 0 OR @Valore > 100)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere maggiore di zero e non superiore a 100';
			GOTO BRANCH_END;
		END

		IF @tipo = 'P' AND @Valore + ISNULL((
				SELECT SUM(la.Valore)
				FROM dbo.tblEoWLottiAllocazioni la
				WHERE la.IdAllocazione = @Id
			), 0) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La somma delle percentuali dei lotti non può superare 100';
			GOTO BRANCH_END;
		END

		IF @tipo = 'C' AND (@Valore IS NULL OR @Valore <= 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La priorità deve essere un valore maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @tipo = 'C' AND EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni la
				WHERE la.IdAllocazione = @Id AND la.Valore = @Valore
			)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questa priorità è già assegnata a un altro lotto dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @tipo = 'U'
			SET @Valore = NULL;

		BEGIN TRANSACTION;
			IF @isTipoDaSalvare = 1
				UPDATE dbo.tblEoWAllocazioni
				SET IdAllocazioneTipo = @tipo
				WHERE Id = @Id;

			INSERT dbo.tblEoWLottiAllocazioni (IdLotto, IdAllocazione, Valore)
			VALUES (@IdLotto, @Id, @Valore);
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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

-- ============================================================ uspEoWAllocazioni_upd
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdAllocazioneTipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAllocazioneTipo = NULLIF(LTRIM(RTRIM(@IdAllocazioneTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);

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
		IF @IdAllocazioneTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAllocazioneTipo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale dell'allocazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblEoWAllocazioniTipi WHERE Id = @IdAllocazioneTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di allocazione indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se l'allocazione ha già lotti collegati, anche se non
		-- ancora salvata (uspEoWAllocazioni_ins_Lotto memorizza il tipo con il primo lotto)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id = @Id
				AND IdAllocazioneTipo <> @IdAllocazioneTipo
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo di un''allocazione con lotti associati';
			GOTO BRANCH_END;
		END

		-- I lotti presenti devono rispettare il tipo (stessi vincoli di uspEoWAllocazioni_ins_Lotto):
		-- intercetta anche lotti aggiunti quando il tipo non era ancora salvato
		IF @IdAllocazioneTipo = 'U' AND (SELECT COUNT(*) FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id) > 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @IdAllocazioneTipo = 'P' AND (
			EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE
					IdAllocazione = @Id
					AND (Valore IS NULL OR Valore <= 0 OR Valore > 100)
			)
			OR (SELECT ISNULL(SUM(Valore), 0) FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id) > 100
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le percentuali dei lotti devono essere maggiori di zero e la loro somma non può superare 100';
			GOTO BRANCH_END;
		END

		IF @IdAllocazioneTipo = 'C' AND (
			EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE
					IdAllocazione = @Id
					AND (Valore IS NULL OR Valore <= 0)
			)
			OR EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE IdAllocazione = @Id
				GROUP BY Valore
				HAVING COUNT(*) > 1
			)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ogni lotto deve avere una priorità diversa: togliere e aggiungere di nuovo i lotti con la stessa priorità';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra allocazione attiva con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra allocazione con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWAllocazioni
			SET
				Lock = 0,
				IdAllocazioneTipo = @IdAllocazioneTipo,
				Nome = @Nome
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allocazione non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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

