SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati dell'Allegato VII da mandare all'hub DIWASS (JSON) per @Operazione: I invio, A aggiornamento, N annullamento,
-- S lettura dello stato. Per I e A controlla che il documento sia completo e restituisce in un solo messaggio tutto
-- quello che manca. La firma di chi organizza è dell'utente della sessione (nome, email) con il ruolo della scheda.
-- Restituisce rtn = JSON (assegnato a variabile, così non viene spezzato in più righe)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Invio]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Operazione CHAR(1) = NULL,
	@Motivo VARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(2000) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @Motivo = dbo.ufnStringhe_get_SenzaSpazi(@Motivo, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL OR ISNULL(@Operazione, '') NOT IN ('I', 'A', 'N', 'S')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri non validi';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF IIF(@Operazione = 'S', 1, 2) > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		DECLARE @stato VARCHAR(20);
		DECLARE @numero VARCHAR(50);
		DECLARE @lock TINYINT;
		DECLARE @ricevuto BIT;
		DECLARE @dataSpedizione DATE;
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente,
			@stato = a.Stato,
			@numero = a.Numero,
			@lock = a.Lock,
			@ricevuto = ISNULL(a.Ricevuto, 0),
			@dataSpedizione = a.DataSpedizione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL OR @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto: salvarlo prima dell''invio';
			GOTO BRANCH_END;
		END

		-- Stato ammesso per l'operazione. Un documento ricevuto da DIWASS lo gestisce chi organizza: si legge solo lo stato
		IF @ricevuto = 1 AND @Operazione <> 'S'
			SET @returnMessage = 'L''Allegato VII è stato ricevuto da DIWASS: lo invia, aggiorna o annulla solo chi organizza la spedizione';
		ELSE IF @Operazione = 'I' AND @stato IS NOT NULL
			SET @returnMessage = 'L''Allegato VII è già stato inviato a DIWASS';
		ELSE IF @Operazione IN ('A', 'N') AND ISNULL(@stato, '') <> 'ANNOUNCED'
			SET @returnMessage = IIF(@stato IS NULL,
				'L''Allegato VII non è ancora stato inviato a DIWASS',
				'L''Allegato VII è ' + LOWER(dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(@stato)) + ' su DIWASS: non si può più ' + IIF(@Operazione = 'A', 'modificare', 'annullare'));
		ELSE IF @Operazione = 'S' AND @numero IS NULL
			SET @returnMessage = 'L''Allegato VII non è ancora stato inviato a DIWASS';
		ELSE IF @Operazione = 'N' AND @Motivo IS NULL
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
		IF @returnMessage IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			GOTO BRANCH_END;
		END

		-- Credenziale DIWASS associata all'azienda in Diwass > Aziende
		DECLARE @idCredenziale CHAR(16) = (
			SELECT c.IdDiwass
			FROM
				dbo.tblDiwassCredenzialiAziende a
				INNER JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			WHERE
				a.IdAziendaInterna = @idAzienda
				AND c.Lock = 0
		);
		IF @idCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda non ha una credenziale DIWASS: chiedere all''amministratore di associarla in Diwass > Aziende';
			GOTO BRANCH_END;
		END

		-- Firma: utente della sessione
		DECLARE @firmaNome VARCHAR(100);
		DECLARE @firmaEmail VARCHAR(100);
		SELECT
			@firmaNome = NULLIF(LTRIM(RTRIM(ISNULL(Nome, '') + ' ' + ISNULL(Cognome, ''))), ''),
			@firmaEmail = Email
		FROM dbo.tblUtenti
		WHERE Id = @idUtente;

		-- Completezza (invio e aggiornamento)
		IF @Operazione IN ('I', 'A')
		BEGIN
			DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Testo NVARCHAR(200));

			INSERT INTO @mancanti (Testo)
			SELECT x.Testo
			FROM
				dbo.tblDiwassAllegatiVii a
				CROSS APPLY (
					VALUES
						(IIF(a.DataSpedizione IS NULL, N'data della spedizione', NULL)),
						(IIF(ISNULL(a.Quantita, 0) <= 0, N'quantità', NULL)),
						(IIF(a.LuogoPartenza IS NULL, N'luogo di partenza', NULL)),
						(IIF(a.ResponsabileNome IS NULL OR a.ResponsabileTelefono IS NULL OR a.ResponsabileEmail IS NULL, N'nome, telefono ed email del responsabile del luogo di partenza', NULL)),
						(IIF(a.IdEer IS NULL, N'codice EER', NULL)),
						(IIF(a.Codice IS NULL, N'codice internazionale del rifiuto (Basel, OCSE)', NULL)),
						(IIF(a.Descrizione IS NULL, N'descrizione usuale del rifiuto', NULL)),
						(IIF(a.IdAttivita IS NULL, N'operazione di recupero', NULL)),
						(IIF(a.IdNazioneSpedizione IS NULL OR a.IdNazioneDestinazione IS NULL, N'paesi di spedizione e di destinazione', NULL)),
						(IIF(a.FirmaRuolo IS NULL, N'ruolo di chi firma', NULL)),
						(IIF(@firmaNome IS NULL OR @firmaEmail IS NULL, N'nome ed email dell''utente che firma (Impostazioni > Utenti)', NULL))
				) x (Testo)
			WHERE
				a.Id = @Id
				AND x.Testo IS NOT NULL;

			-- Operazione di recupero: deve essere una R (spedizioni della lista verde)
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblDiwassAllegatiVii a
					INNER JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON a.IdAttivita = r.Id
				WHERE
					a.Id = @Id
					AND r.Codice NOT LIKE 'R%'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'operazione di recupero (R1-R13), non di smaltimento');

			-- Soggetti obbligatori
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassOperatori
			WHERE
				Id = @idAzienda
				AND Stato IN ('NEW', 'VALID')
			)
				INSERT INTO @mancanti (Testo) VALUES (N'collegamento a DIWASS dell''azienda che organizza (Diwass > Operatori)');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'D'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'destinatario');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'I'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'impianto di recupero o laboratorio');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'T'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'almeno un trasportatore');

			INSERT INTO @mancanti (Testo)
			SELECT N'contatto (nome, telefono ed email) di ' + s.NomeCompleto
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
			WHERE
				x.Id = @Id
				AND
					(
					x.ContattoNome IS NULL
					OR x.ContattoTelefono IS NULL
					OR x.ContattoEmail IS NULL
					);

			INSERT INTO @mancanti (Testo)
			SELECT N'collegamento a DIWASS di ' + s.NomeCompleto
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
				LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id AND o.Stato IN ('NEW', 'VALID')
			WHERE
				x.Id = @Id
				AND x.Ruolo <> 'O'
				AND o.Id IS NULL;

			IF EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'P'
			)
				AND EXISTS (
					SELECT 1
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND
							(
							ProduttoreFirmaNome IS NULL
							OR ProduttoreFirmaRuolo IS NULL
							OR ProduttoreFirmaData IS NULL
							)
				)
				INSERT INTO @mancanti (Testo) VALUES (N'conferma del produttore (nome, ruolo e data)');

			IF EXISTS (SELECT 1
			FROM @mancanti)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = LEFT(N'Per inviare l''Allegato VII a DIWASS completare: '
					+ STUFF((SELECT N'; ' + Testo
					FROM @mancanti ORDER BY Pos FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), 2000);
				GOTO BRANCH_END;
			END
		END

		-- Invio almeno due giorni lavorativi prima della spedizione (Reg. UE 2024/1157 art. 18.5; DIWASS lo controlla
		-- nella sua interfaccia web): la data della spedizione non può essere precedente alla prima ammessa
		DECLARE @dataMinima DATE = dbo.ufnDiwassAllegatiVii_get_DataSpedizioneMinima(CAST(GETDATE() AS DATE));
		IF @Operazione = 'I' AND @dataSpedizione < @dataMinima
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data della spedizione deve essere il ' + CONVERT(VARCHAR(10), @dataMinima, 103) + ' o successiva: l''Allegato VII va inviato almeno due giorni lavorativi prima della spedizione';
			GOTO BRANCH_END;
		END

		DECLARE @json NVARCHAR(MAX) = (
			SELECT
				idCredenziale = @idCredenziale,
				numero = a.Numero,
				arrangerIsProducer = CAST(IIF(EXISTS (SELECT 1
				FROM dbo.tblDiwassAllegatiViiSoggetti p
				WHERE
					p.Id = a.Id
					AND p.Ruolo = 'P'
				), 0, 1) AS BIT),
				tipoDestinazione = a.TipoDestinazione,
				dataSpedizione = a.DataSpedizione,
				quantita = a.Quantita,
				unitaQuantita = a.UnitaQuantita,
				contenitore = a.Contenitore,
				luogoPartenza = a.LuogoPartenza,
				responsabileNome = a.ResponsabileNome,
				responsabileTelefono = a.ResponsabileTelefono,
				responsabileEmail = a.ResponsabileEmail,
				-- Elenco europeo dei rifiuti nel formato DIWASS ("15 01 01", con l'asterisco se pericoloso)
				eer = LEFT(a.IdEer, 2) + ' ' + SUBSTRING(a.IdEer, 3, 2) + ' ' + RIGHT(a.IdEer, 2) + IIF(e.Pericoloso = 1, '*', ''),
				listaCodice = a.ListaCodice,
				codice = a.Codice,
				descrizione = a.Descrizione,
				operazione = r.Codice,
				codiceDoganale = a.CodiceDoganale,
				paeseSpedizione = a.IdNazioneSpedizione,
				paeseDestinazione = a.IdNazioneDestinazione,
				paeseTransito1 = a.IdNazioneTransito1,
				paeseTransito2 = a.IdNazioneTransito2,
				firmaNome = @firmaNome,
				firmaRuolo = a.FirmaRuolo,
				firmaEmail = @firmaEmail,
				produttoreFirmaNome = a.ProduttoreFirmaNome,
				produttoreFirmaRuolo = a.ProduttoreFirmaRuolo,
				produttoreFirmaData = a.ProduttoreFirmaData,
				motivo = @Motivo,
				soggetti = (
					SELECT
						ruolo = x.Ruolo,
						pos = x.Pos,
						operatorInternalId = o.OperatorInternalId,
						partyUuid = x.PartyUuid,
						contattoNome = x.ContattoNome,
						contattoTelefono = x.ContattoTelefono,
						contattoEmail = x.ContattoEmail,
						mezzoTrasporto = x.MezzoTrasporto,
						impiantoIntermedio = ISNULL(x.ImpiantoIntermedio, 0),
						nomeRiservato = ISNULL(x.NomeRiservato, 0),
						motivoRiservatezza = x.MotivoRiservatezza
					FROM
						dbo.tblDiwassAllegatiViiSoggetti x
						LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
					WHERE x.Id = a.Id
					ORDER BY x.Ruolo, x.Pos
					FOR JSON PATH
				)
			FROM
				dbo.tblDiwassAllegatiVii a
				LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON a.IdAttivita = r.Id
			WHERE a.Id = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

		SELECT rtn = @json;

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
