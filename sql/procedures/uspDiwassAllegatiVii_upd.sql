SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva l'Allegato VII (bozza o già annunciato su DIWASS: in quel caso, se i dati cambiano, le modifiche restano da
-- inviare, DaInviare = 1; un salvataggio senza modifiche lascia DaInviare com'era).
-- @Soggetti è l'elenco JSON dei soggetti ([{ruolo, pos, idSede, contattoNome, contattoTelefono, contattoEmail,
-- mezzoTrasporto, impiantoIntermedio, nomeRiservato, motivoRiservatezza}]): sostituisce quelli salvati. I controlli di
-- completezza sono all'invio (uspDiwassAllegatiVii_get_Invio): qui solo quelli che rendono il dato incoerente
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@TipoDestinazione CHAR(1) = NULL,
	@DataSpedizione DATE = NULL,
	@Quantita DECIMAL(18, 5) = NULL,
	@UnitaQuantita CHAR(1) = NULL,
	@Contenitore VARCHAR(100) = NULL,
	@LuogoPartenza VARCHAR(300) = NULL,
	@ResponsabileNome VARCHAR(100) = NULL,
	@ResponsabileTelefono VARCHAR(50) = NULL,
	@ResponsabileEmail VARCHAR(100) = NULL,
	@IdEer CHAR(6) = NULL,
	@Descrizione VARCHAR(500) = NULL,
	@CodiceDoganale VARCHAR(50) = NULL,
	@IdNazioneSpedizione CHAR(3) = NULL,
	@IdNazioneDestinazione CHAR(3) = NULL,
	@IdNazioneTransito1 CHAR(3) = NULL,
	@IdNazioneTransito2 CHAR(3) = NULL,
	@IdAttivita CHAR(2) = NULL,
	@Codice NVARCHAR(40) = NULL,
	@FirmaRuolo VARCHAR(100) = NULL,
	@ProduttoreFirmaNome VARCHAR(100) = NULL,
	@ProduttoreFirmaRuolo VARCHAR(100) = NULL,
	@ProduttoreFirmaData DATETIME2(0) = NULL,
	@Note VARCHAR(500) = NULL,
	@Soggetti NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(400) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @TipoDestinazione = ISNULL(NULLIF(LTRIM(RTRIM(@TipoDestinazione)), ''), 'R');
		SET @UnitaQuantita = ISNULL(NULLIF(LTRIM(RTRIM(@UnitaQuantita)), ''), 'T');
		SET @Contenitore = dbo.ufnStringhe_get_SenzaSpazi(@Contenitore, 0, 1);
		SET @LuogoPartenza = dbo.ufnStringhe_get_SenzaSpazi(@LuogoPartenza, 0, 1);
		SET @ResponsabileNome = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileNome, 0, 1);
		SET @ResponsabileTelefono = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileTelefono, 0, 1);
		SET @ResponsabileEmail = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileEmail, 0, 1);
		SET @IdEer = NULLIF(NULLIF(LTRIM(RTRIM(@IdEer)), ''), '000000');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @CodiceDoganale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceDoganale, 0, 1);
		SET @IdNazioneSpedizione = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneSpedizione)), ''), '000');
		SET @IdNazioneDestinazione = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneDestinazione)), ''), '000');
		SET @IdNazioneTransito1 = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneTransito1)), ''), '000');
		SET @IdNazioneTransito2 = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneTransito2)), ''), '000');
		SET @IdAttivita = NULLIF(NULLIF(LTRIM(RTRIM(@IdAttivita)), ''), '00');
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');
		SET @FirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@FirmaRuolo, 0, 1);
		SET @ProduttoreFirmaNome = dbo.ufnStringhe_get_SenzaSpazi(@ProduttoreFirmaNome, 0, 1);
		SET @ProduttoreFirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@ProduttoreFirmaRuolo, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF @TipoDestinazione NOT IN ('R', 'L') OR @UnitaQuantita NOT IN ('T', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Tipo di destinazione o unità della quantità non validi';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NOT NULL AND @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @stato VARCHAR(20);
		DECLARE @nazioneSpedizioneAttuale CHAR(3);
		DECLARE @nazioneDestinazioneAttuale CHAR(3);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@stato = a.Stato,
			@nazioneSpedizioneAttuale = a.IdNazioneSpedizione,
			@nazioneDestinazioneAttuale = a.IdNazioneDestinazione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock <= 2
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END
		IF @stato IS NOT NULL AND @stato <> 'ANNOUNCED'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII è ' + LOWER(dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(@stato)) + ' su DIWASS: non si può più modificare';
			GOTO BRANCH_END;
		END
		-- Su DIWASS i paesi coinvolti non si cambiano dopo l'annuncio
		IF @stato = 'ANNOUNCED'
			AND (ISNULL(@IdNazioneSpedizione, '') <> ISNULL(@nazioneSpedizioneAttuale, '')
				OR ISNULL(@IdNazioneDestinazione, '') <> ISNULL(@nazioneDestinazioneAttuale, ''))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dopo l''invio a DIWASS i paesi di spedizione e di destinazione non si possono cambiare';
			GOTO BRANCH_END;
		END

		-- Codice internazionale nel formato "lista|codice" della select
		DECLARE @listaCodice VARCHAR(10) = NULL;
		DECLARE @codiceRifiuto NVARCHAR(20) = NULL;
		IF @Codice IS NOT NULL
		BEGIN
			SET @listaCodice = LEFT(@Codice, CHARINDEX('|', @Codice + '|') - 1);
			SET @codiceRifiuto = NULLIF(SUBSTRING(@Codice, CHARINDEX('|', @Codice + '|') + 1, 20), '');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassCodiciRifiuti
			WHERE
				Lista = @listaCodice
				AND Codice = @codiceRifiuto
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Codice internazionale del rifiuto non valido';
				GOTO BRANCH_END;
			END
		END

		-- Soggetti
		DECLARE @elenco TABLE (
			Ruolo CHAR(1) NOT NULL,
			Pos TINYINT NOT NULL,
			IdSede CHAR(16) NULL,
			ContattoNome VARCHAR(100) NULL,
			ContattoTelefono VARCHAR(50) NULL,
			ContattoEmail VARCHAR(100) NULL,
			MezzoTrasporto CHAR(1) NULL,
			ImpiantoIntermedio BIT NULL,
			NomeRiservato BIT NULL,
			MotivoRiservatezza VARCHAR(500) NULL,
			PRIMARY KEY (Ruolo, Pos)
		);
		INSERT INTO @elenco (Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
		SELECT
			j.ruolo,
			j.pos,
			NULLIF(NULLIF(LTRIM(RTRIM(j.idSede)), ''), REPLICATE('0', 16)),
			NULLIF(LTRIM(RTRIM(j.contattoNome)), ''),
			NULLIF(LTRIM(RTRIM(j.contattoTelefono)), ''),
			NULLIF(LTRIM(RTRIM(j.contattoEmail)), ''),
			NULLIF(LTRIM(RTRIM(j.mezzoTrasporto)), ''),
			j.impiantoIntermedio,
			j.nomeRiservato,
			NULLIF(LTRIM(RTRIM(j.motivoRiservatezza)), '')
		FROM OPENJSON(ISNULL(@Soggetti, N'[]'))
		WITH (
			ruolo CHAR(1),
			pos TINYINT,
			idSede CHAR(16),
			contattoNome VARCHAR(100),
			contattoTelefono VARCHAR(50),
			contattoEmail VARCHAR(100),
			mezzoTrasporto CHAR(1),
			impiantoIntermedio BIT,
			nomeRiservato BIT,
			motivoRiservatezza VARCHAR(500)
		) j;

		-- Le righe senza sede (casella lasciata su "Selezionare") non si salvano
		DELETE @elenco
		WHERE IdSede IS NULL;

		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo NOT IN ('O', 'P', 'D', 'I', 'T')
			OR Pos NOT BETWEEN 1 AND 3
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ruolo o posizione dei soggetti non validi';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo = 'T'
			AND ISNULL(MezzoTrasporto, '') NOT IN ('R', 'T', 'S', 'A', 'W')
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il mezzo di trasporto di ogni trasportatore';
			GOTO BRANCH_END;
		END

		-- Chi organizza è sempre l'azienda dell'Allegato VII
		DELETE @elenco
		WHERE
			Ruolo = 'O'
			AND IdSede <> @idAzienda;
		IF NOT EXISTS (SELECT 1
		FROM @elenco
		WHERE Ruolo = 'O')
			INSERT INTO @elenco (Ruolo, Pos, IdSede)
			VALUES ('O', 1, @idAzienda);

		-- Ogni soggetto deve essere visibile nel contesto e collegato a DIWASS con il ruolo WSR nuovo o valido
		DECLARE @nonCollegato VARCHAR(200) = (
			SELECT TOP 1 s.NomeCompleto
			FROM
				@elenco x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
				LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id AND o.Stato IN ('NEW', 'VALID')
				LEFT JOIN dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v ON x.IdSede = v.Id
			WHERE
				x.Ruolo <> 'O'
				AND
					(
					o.Id IS NULL
					OR v.Id IS NULL
					)
		);
		IF @nonCollegato IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto ' + @nonCollegato + ' non è collegato a DIWASS (Diwass > Operatori)';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo = 'I'
			AND NomeRiservato = 1
			AND MotivoRiservatezza IS NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare perché il nome dell''impianto è riservato';
			GOTO BRANCH_END;
		END

		-- Dati prima del salvataggio: su un documento annunciato le modifiche restano da inviare solo se qualcosa cambia
		DECLARE @prima NVARCHAR(MAX) = (
			SELECT
				a.TipoDestinazione, a.DataSpedizione, a.Quantita, a.UnitaQuantita, a.Contenitore, a.LuogoPartenza,
				a.ResponsabileNome, a.ResponsabileTelefono, a.ResponsabileEmail, a.IdEer, a.Descrizione, a.CodiceDoganale,
				a.IdNazioneSpedizione, a.IdNazioneDestinazione, a.IdNazioneTransito1, a.IdNazioneTransito2, a.IdAttivita,
				a.ListaCodice, a.Codice, a.FirmaRuolo, a.ProduttoreFirmaNome, a.ProduttoreFirmaRuolo, a.ProduttoreFirmaData, a.Note,
				Soggetti = (
					SELECT x.Ruolo, x.Pos, x.IdSede, x.ContattoNome, x.ContattoTelefono, x.ContattoEmail, x.MezzoTrasporto, x.ImpiantoIntermedio, x.NomeRiservato, x.MotivoRiservatezza
					FROM dbo.tblDiwassAllegatiViiSoggetti x
					WHERE x.Id = a.Id
					ORDER BY x.Ruolo, x.Pos
					FOR JSON PATH)
			FROM dbo.tblDiwassAllegatiVii a
			WHERE a.Id = @Id FOR JSON PATH, INCLUDE_NULL_VALUES);

		BEGIN TRANSACTION;
			UPDATE dbo.tblDiwassAllegatiVii
			SET
				TipoDestinazione = @TipoDestinazione,
				DataSpedizione = @DataSpedizione,
				Quantita = @Quantita,
				UnitaQuantita = @UnitaQuantita,
				Contenitore = @Contenitore,
				LuogoPartenza = @LuogoPartenza,
				ResponsabileNome = @ResponsabileNome,
				ResponsabileTelefono = @ResponsabileTelefono,
				ResponsabileEmail = @ResponsabileEmail,
				IdEer = @IdEer,
				Descrizione = @Descrizione,
				CodiceDoganale = @CodiceDoganale,
				IdNazioneSpedizione = @IdNazioneSpedizione,
				IdNazioneDestinazione = @IdNazioneDestinazione,
				IdNazioneTransito1 = @IdNazioneTransito1,
				IdNazioneTransito2 = @IdNazioneTransito2,
				IdAttivita = @IdAttivita,
				ListaCodice = @listaCodice,
				Codice = @codiceRifiuto,
				FirmaRuolo = @FirmaRuolo,
				ProduttoreFirmaNome = @ProduttoreFirmaNome,
				ProduttoreFirmaRuolo = @ProduttoreFirmaRuolo,
				ProduttoreFirmaData = @ProduttoreFirmaData,
				Note = @Note,
				DaInviare = IIF(@stato = 'ANNOUNCED', DaInviare, NULL),
				Lock = 0
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allegato VII non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Soggetti: l'identificativo del soggetto nel documento (PartyUuid) resta finché non cambia la sede
			DELETE x
			FROM dbo.tblDiwassAllegatiViiSoggetti x
			WHERE
				x.Id = @Id
				AND NOT EXISTS ( SELECT 1 FROM @elenco n WHERE n.Ruolo = x.Ruolo AND n.Pos = x.Pos AND n.IdSede = x.IdSede );

			UPDATE x
			SET
				ContattoNome = n.ContattoNome,
				ContattoTelefono = n.ContattoTelefono,
				ContattoEmail = n.ContattoEmail,
				MezzoTrasporto = n.MezzoTrasporto,
				ImpiantoIntermedio = n.ImpiantoIntermedio,
				NomeRiservato = n.NomeRiservato,
				MotivoRiservatezza = n.MotivoRiservatezza
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN @elenco n ON x.Ruolo = n.Ruolo AND x.Pos = n.Pos AND x.IdSede = n.IdSede
			WHERE x.Id = @Id;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
			SELECT @Id, n.Ruolo, n.Pos, n.IdSede, n.ContattoNome, n.ContattoTelefono, n.ContattoEmail, n.MezzoTrasporto, n.ImpiantoIntermedio, n.NomeRiservato, n.MotivoRiservatezza
			FROM @elenco n
			WHERE NOT EXISTS ( SELECT 1 FROM dbo.tblDiwassAllegatiViiSoggetti x WHERE x.Id = @Id AND x.Ruolo = n.Ruolo AND x.Pos = n.Pos );

			IF @stato = 'ANNOUNCED'
			BEGIN
				DECLARE @dopo NVARCHAR(MAX) = (
					SELECT
						a.TipoDestinazione, a.DataSpedizione, a.Quantita, a.UnitaQuantita, a.Contenitore, a.LuogoPartenza,
						a.ResponsabileNome, a.ResponsabileTelefono, a.ResponsabileEmail, a.IdEer, a.Descrizione, a.CodiceDoganale,
						a.IdNazioneSpedizione, a.IdNazioneDestinazione, a.IdNazioneTransito1, a.IdNazioneTransito2, a.IdAttivita,
						a.ListaCodice, a.Codice, a.FirmaRuolo, a.ProduttoreFirmaNome, a.ProduttoreFirmaRuolo, a.ProduttoreFirmaData, a.Note,
						Soggetti = (
							SELECT x.Ruolo, x.Pos, x.IdSede, x.ContattoNome, x.ContattoTelefono, x.ContattoEmail, x.MezzoTrasporto, x.ImpiantoIntermedio, x.NomeRiservato, x.MotivoRiservatezza
							FROM dbo.tblDiwassAllegatiViiSoggetti x
							WHERE x.Id = a.Id
							ORDER BY x.Ruolo, x.Pos
							FOR JSON PATH)
					FROM dbo.tblDiwassAllegatiVii a
					WHERE a.Id = @Id FOR JSON PATH, INCLUDE_NULL_VALUES);

				-- Confronto esatto (anche maiuscole e minuscole)
				IF @dopo COLLATE Latin1_General_BIN2 <> @prima COLLATE Latin1_General_BIN2
					UPDATE dbo.tblDiwassAllegatiVii
					SET DaInviare = 1
					WHERE Id = @Id;
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
