SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: crea l'area temporanea con i movimenti letti da RENTRI per un registro collegato e ne
-- esegue l'analisi (uspRentriImportazioni_upd_Analisi). Non scrive nulla nel registro: le registrazioni nascono
-- solo dall'esecuzione definitiva.
--
-- @Movimenti: array JSON preparato dall'app con i movimenti restituiti dall'hub, ognuno con
--   anno, progressivo, identificativo, isIntervallo (1 = nell'intervallo richiesto, 0 = recuperato perché
--   richiamato da un movimento dell'intervallo), json (movimento corrente come restituito da RENTRI),
--   jsonDettaglio (dettaglio con le variazioni, solo per le registrazioni rettificate o annullate),
--   jsonFormulario e formularioStato (D formulario digitale letto, N non trovato: solo per le registrazioni con numero
--   di formulario ma senza trasportatore o destinatario su RENTRI, da cui l'analisi li recupera).
-- I JSON di RENTRI si salvano così come arrivano e non si modificano più (copia originale).
--
-- @Modalita: F tutte le registrazioni fino ad @AlNumero/@AlAnno (letti tutti gli anni dal 2020: @DalAnno 2020,
-- @DalNumero 1), I solo l'intervallo indicato.
-- Un'importazione in preparazione per registro: quella precedente non eseguita viene sostituita. Le anteprime di
-- qualunque registro senza attività da 30 giorni si cancellano.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_ins]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Modalita CHAR(1) = NULL,
	@DalAnno SMALLINT = NULL,
	@DalNumero INT = NULL,
	@AlAnno SMALLINT = NULL,
	@AlNumero INT = NULL,
	@Movimenti NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Modalita = NULLIF(LTRIM(RTRIM(@Modalita)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro';
			GOTO BRANCH_END;
		END
		IF @Modalita IS NULL OR @Modalita NOT IN ('F', 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Modalita non è valido';
			GOTO BRANCH_END;
		END
		IF @DalAnno IS NULL OR @DalNumero IS NULL OR @AlAnno IS NULL OR @AlNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare numero e anno di inizio e di fine delle registrazioni da importare';
			GOTO BRANCH_END;
		END
		IF @DalAnno < 2020 OR @AlAnno > 2050 OR @DalNumero < 1 OR @AlNumero < 1
			OR @DalAnno > @AlAnno OR (@DalAnno = @AlAnno AND @DalNumero > @AlNumero)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''intervallo delle registrazioni da importare non è valido';
			GOTO BRANCH_END;
		END
		IF @Movimenti IS NULL OR ISJSON(@Movimenti) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Movimenti non è valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				g.Id = @IdRegistro
				AND g.Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro AND IdRentri IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è collegato a RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);

		-- Movimenti letti dall'hub (un movimento per anno e numero: eventuali doppioni dell'app si scartano)
		SELECT
			j.Anno, j.Progressivo, j.Identificativo, ISNULL(j.IsIntervallo, 0) AS IsIntervallo, j.Json, j.JsonDettaglio, j.JsonFormulario, j.FormularioStato,
			rn = ROW_NUMBER() OVER (PARTITION BY j.Anno, j.Progressivo ORDER BY ISNULL(j.IsIntervallo, 0) DESC)
		INTO #movimenti
		FROM
			OPENJSON(@Movimenti)
			WITH (
				Anno SMALLINT '$.anno',
				Progressivo INT '$.progressivo',
				Identificativo VARCHAR(50) '$.identificativo',
				IsIntervallo BIT '$.isIntervallo',
				Json NVARCHAR(MAX) '$.json',
				JsonDettaglio NVARCHAR(MAX) '$.jsonDettaglio',
				JsonFormulario NVARCHAR(MAX) '$.jsonFormulario',
				FormularioStato CHAR(1) '$.formularioStato'
			) j;

		IF EXISTS (
			SELECT 1
			FROM #movimenti
			WHERE
				Anno IS NULL OR Progressivo IS NULL OR Json IS NULL OR ISJSON(Json) = 0
				OR (JsonDettaglio IS NOT NULL AND ISJSON(JsonDettaglio) = 0))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I movimenti ricevuti da RENTRI non sono validi';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM #movimenti WHERE IsIntervallo = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessuna registrazione trovata su RENTRI nell''intervallo indicato';
			GOTO BRANCH_END;
		END

		DECLARE @id CHAR(16);
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @id OUTPUT;

		BEGIN TRANSACTION;

			-- Anteprime abbandonate: non eseguite e senza attività da 30 giorni, di qualunque registro (l'analisi
			-- aggiorna DataAnalisi a ogni rianalisi, anche abbinando o completando un soggetto)
			DELETE dbo.tblRentriImportazioni
			WHERE
				Stato = 'P'
				AND ISNULL(DataAnalisi, DataCreazione) < DATEADD(DAY, -30, SYSDATETIME());

			-- Una sola importazione in preparazione per registro
			DELETE dbo.tblRentriImportazioni
			WHERE
				IdRegistro = @IdRegistro
				AND Stato = 'P';

			INSERT dbo.tblRentriImportazioni (Id, IdRegistro, IdUtente, Modalita, DalAnno, DalNumero, AlAnno, AlNumero, Stato, DataCreazione)
			VALUES (@id, @IdRegistro, @idUtente, @Modalita, @DalAnno, @DalNumero, @AlAnno, @AlNumero, 'P', SYSDATETIME());

			INSERT dbo.tblRentriImportazioniMovimenti (IdImportazione, Anno, Progressivo, Identificativo, IsIntervallo, Json, JsonDettaglio, JsonFormulario, FormularioStato)
			SELECT @id, Anno, Progressivo, Identificativo, IsIntervallo, Json, JsonDettaglio, JsonFormulario, FormularioStato
			FROM #movimenti
			WHERE rn = 1;

		COMMIT TRANSACTION;

		EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @id;

		SELECT rtn = @id;

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
