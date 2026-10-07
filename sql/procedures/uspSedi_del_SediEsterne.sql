SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediEsterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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
			@IdFunzione = 'ANS',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI, senza protezione anti-doppio-submit sul pulsante) — la
			-- si tratta come cancellazione già avvenuta con successo, non come errore: lo stato
			-- desiderato ("questa sede non esiste") è già raggiunto.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede condivisa da altre aziende non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeOsepe ao
				INNER JOIN dbo.tblAree a ON ao.Id = a.Id
				WHERE
					ao.IdOsepe = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''autorizzazione rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
			-- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
			-- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne)
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Anagrafica estesa: un soggetto con una scheda cliente o fornitore attiva
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede presente tra i clienti o i fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				-- Unità locale: se la sede cancellata è una sede figlia con il flag, lo eredita
				-- il soggetto, così il gruppo non resta mai senza un'unità locale attiva
				UPDATE p
				SET p.UnitaLocale = 1
				FROM dbo.tblSedi p
				INNER JOIN dbo.tblSedi s ON s.IdParent = p.Id
				WHERE
					s.Id = @Id
					AND s.UnitaLocale = 1
					AND p.Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				-- Modulo Magazzino: DDT dove questa sede esterna compare come mittente,
				-- destinatario, destinazione o trasportatore. Ramo di fatto irraggiungibile in
				-- pratica (blocco sopra su Lock=0), mantenuto per difesa dalla FK.
				DELETE dbo.tblMagazziniDdt
				WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id;

				-- Anagrafica estesa: schede cliente/fornitore del soggetto (una bozza di norma non
				-- ne ha), per difesa dalla FK NO_ACTION
				DELETE dbo.tblClientiFornitori
				WHERE IdSede = @Id;

				-- Tabelle 1:1 sulla sede (FK NO_ACTION): una bozza di norma non ne ha
				DELETE dbo.tblSediDatiEstesi
				WHERE Id = @Id;
				DELETE dbo.tblSediRecapiti
				WHERE Id = @Id;
				DELETE dbo.tblSediIndirizzi
				WHERE Id = @Id;

				DELETE dbo.tblAreeOsepe
				WHERE IdOsepe = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL. In
				-- pratica non popolata per una sede esterna (blocco sopra su Lock=0 comunque già la
				-- impedisce), mantenuta per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				DELETE dbo.tblSediEsterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

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


