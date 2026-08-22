CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Ricorre BIT = 0,
	@Avviso BIT = 0,
	@AvvisoAnticipo INT = 0,
	@Email VARCHAR(1000) = NULL,
	@IdEtichette VARCHAR(50) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@Frequenza INT = NULL,
	@DataFine SMALLDATETIME = NULL,
	@Ripetizioni INT = NULL,
	@Relativo INT = 0,
	@OccorrenzaESuccessive BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @permesso TINYINT;
	DECLARE @frequenzaMax INT = 0;
	DECLARE @minuti INT = 0;
	DECLARE @idEventoParent CHAR(16);
	DECLARE @dataFineParent SMALLDATETIME;

	BEGIN TRY

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

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
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
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
			WHERE
				s.Id = @Id
				AND e.Id = @IdEvento
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Normalizzazione parametri VARCHAR opzionali
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @Email = dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1);

		IF @Ricorre = 1 AND @Data < '20220101'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data minima per le scadenze ricorrenti è il 01/01/2022';
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND @DataFine IS NOT NULL AND @DataFine < @Data
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine della serie non può essere inferiore alla data di inizio';
			GOTO BRANCH_END;
		END

		IF @IdIntervallo = 'YY'
		BEGIN
			SET @frequenzaMax = DATEDIFF(YEAR, @Data, '20501231') - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' anni';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @IdIntervallo = 'MM'
		BEGIN
			SET @frequenzaMax = DATEDIFF(MONTH, @Data, '20501231') - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' mesi';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;

			IF (EXISTS (SELECT 1
			FROM dbo.tblRicorrenze
			WHERE Id = @IdEvento))
			   AND @OccorrenzaESuccessive = 0
			BEGIN
				IF @Ricorre = 0
				BEGIN
					DELETE dbo.tblRicorrenze
					WHERE Id = @IdEvento;
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE Id = @IdEvento;
				END
				ELSE
				BEGIN
					IF EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenze
						WHERE
							Id = @IdEvento
							AND
								(
								IdIntervallo <> @IdIntervallo
								OR Frequenza <> @Frequenza
								OR Relativo <> @Relativo
								)
					)
					BEGIN
						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @IdEvento
							AND IdEvento IS NULL;
					END

					SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
					FROM dbo.tblEventi
					WHERE Id = @IdEvento;

					IF ISNULL(@minuti, 0) <> 0
						UPDATE dbo.tblRicorrenzeEccezioni
						SET [Data] = DATEADD(MINUTE, @minuti, [Data])
						WHERE Id = @IdEvento;

					UPDATE dbo.tblRicorrenze
					SET
						IdIntervallo = @IdIntervallo,
						Frequenza = @Frequenza,
						DataFine = @DataFine,
						Ripetizioni = @Ripetizioni,
						Relativo = @Relativo
					WHERE Id = @IdEvento;
				END
			END
			ELSE IF @Ricorre = 1 AND @OccorrenzaESuccessive = 0
			BEGIN
				INSERT dbo.tblRicorrenze
					(Id, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
				VALUES
					(@IdEvento, @IdIntervallo, @Frequenza, @DataFine, @Ripetizioni, @Relativo);
			END
			ELSE IF @OccorrenzaESuccessive = 1
			BEGIN
				SELECT @idEventoParent = IdParent
				FROM dbo.tblRicorrenze
				WHERE Id = @IdEvento;

				SET @dataFineParent =
					DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
						DATEADD(DAY, DATEDIFF(DAY, 0, @Data), -1)));

				UPDATE dbo.tblRicorrenze
				SET
					DataFine = @dataFineParent,
					Ripetizioni = 0
				WHERE Id = @idEventoParent;

				UPDATE dbo.tblRicorrenze
				SET
					IdIntervallo = @IdIntervallo,
					Frequenza = @Frequenza,
					DataFine = @DataFine,
					Ripetizioni = @Ripetizioni,
					Relativo = @Relativo
				WHERE Id = @IdEvento;

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @idEventoParent
					AND [Data] > @dataFineParent;

				-- Sblocca le eccezioni della serie padre che referenziano questo evento sostitutivo
				UPDATE dbo.tblRicorrenzeEccezioni
				SET Lock = 0
				WHERE
					IdEvento = @IdEvento
					AND Lock <= 2;
			END

			UPDATE dbo.tblScadenze
			SET Descrizione = ISNULL(@Descrizione, Descrizione)
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Scadenza non trovata o già eliminata';
				GOTO BRANCH_END;
			END

			DELETE dbo.tblEventiEtichette
			WHERE Id = @IdEvento;

			INSERT dbo.tblEventiEtichette (Id, IdEtichetta)
			SELECT TOP 3
				@IdEvento,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value
			WHERE v.value <> '';

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				AvvisoAnticipo = IIF(@Avviso = 0, NULL, @AvvisoAnticipo),
				Email = IIF(@Avviso = 0, NULL, @Email),
				Avviso = dbo.ufnStringhe_get_Compatta( t.Nome + ' - ' + @Descrizione, 200, default),
				Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c.Hex, c.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblEventiEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c ON et.IdColore = c.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH ),
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblScadenze s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			WHERE
				e.Id = @IdEvento
				AND e.Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Evento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
