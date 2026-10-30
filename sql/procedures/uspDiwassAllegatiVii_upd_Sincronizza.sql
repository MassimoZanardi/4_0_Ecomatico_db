SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importa gli Allegati VII letti da DIWASS dalla sincronizzazione dell'hub ([1_0_diwass]..tblAllegatiVii, JSON
-- AllegatoViiLetto) per le aziende del dominio della sessione associate a una credenziale (Diwass > Aziende).
-- Un documento si importa per ogni azienda che vi compare con un suo operatore (sedi interne collegate in Diwass >
-- Operatori): quelli inviati da Ecomatico aggiornano stato, ruoli e conferme; gli altri diventano documenti ricevuti
-- (Ricevuto = 1, in sola lettura) con dati, soggetti e conferme di DIWASS. Solo i documenti letti dall'hub dopo
-- l'ultima importazione (DataLettura); @Numero = un solo documento. Regole in docs/regole/diwass.md (D6)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd_Sincronizza]
	@IdSessione CHAR(16) = NULL,
	@Numero VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');

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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16) = (
			SELECT IdDominio
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione);

		-- Documenti dell'hub per le aziende associate alle credenziali del dominio
		CREATE TABLE #doc (
			IdAziendaInterna CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			Numero VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
			Documento NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NOT NULL,
			DataLettura DATETIME2(0) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Ricevuto BIT NULL,
			Nuovo BIT NOT NULL DEFAULT (0),
			Ruoli VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO #doc (IdAziendaInterna, Numero, Documento, DataLettura)
		SELECT ca.IdAziendaInterna, h.Numero, h.Documento, h.DataLettura
		FROM
			dbo.tblDiwassCredenziali c
			INNER JOIN dbo.tblDiwassCredenzialiAziende ca ON c.Id = ca.IdCredenziale
			INNER JOIN [1_0_diwass]..tblAllegatiVii h ON c.IdDiwass COLLATE DATABASE_DEFAULT = h.IdCredenziale COLLATE DATABASE_DEFAULT
		WHERE
			c.IdDominio = @idDominio
			AND c.Lock = 0
			AND
				(
				@Numero IS NULL
				OR h.Numero COLLATE DATABASE_DEFAULT = @Numero
				);

		-- Documento già presente nell'azienda: inviato da Ecomatico o ricevuto in un'importazione precedente
		UPDATE d
		SET
			Id = a.Id,
			Ricevuto = ISNULL(a.Ricevuto, 0)
		FROM
			#doc d
			INNER JOIN dbo.tblDiwassAllegatiVii a ON d.Numero = a.Numero AND d.IdAziendaInterna = a.IdAziendaInterna
		WHERE a.Lock = 0;

		-- Già importato dopo l'ultima lettura dell'hub, oppure presente ma cancellato: niente da fare
		DELETE d
		FROM
			#doc d
			INNER JOIN dbo.tblDiwassAllegatiVii a ON d.Numero = a.Numero AND d.IdAziendaInterna = a.IdAziendaInterna
		WHERE
			a.Lock <> 0
			OR
				(
				d.Id = a.Id
				AND a.DataLettura >= d.DataLettura
				);

		-- Soggetti dei documenti
		CREATE TABLE #sog (
			IdAziendaInterna CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			Numero VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
			Ruolo CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL,
			Pos TINYINT NOT NULL,
			OperatorInternalId BIGINT NULL,
			PartyUuid UNIQUEIDENTIFIER NULL,
			Nome NVARCHAR(250) COLLATE DATABASE_DEFAULT NULL,
			Indirizzo NVARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			Paese CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			ContattoNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			ContattoTelefono VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			ContattoEmail VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			MezzoTrasporto CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			ImpiantoIntermedio BIT NULL,
			IdSede CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO #sog (IdAziendaInterna, Numero, Ruolo, Pos, OperatorInternalId, PartyUuid, Nome, Indirizzo, Paese, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio)
		SELECT d.IdAziendaInterna, d.Numero, j.Ruolo, j.Pos, j.OperatorInternalId, j.PartyUuid, LEFT(j.Nome, 250), LEFT(j.Indirizzo, 500), j.Paese, LEFT(j.ContattoNome, 100), LEFT(j.ContattoTelefono, 50), LEFT(j.ContattoEmail, 100), j.MezzoTrasporto, j.ImpiantoIntermedio
		FROM
			#doc d
			CROSS APPLY OPENJSON(d.Documento, '$.soggetti')
			WITH (
				Ruolo CHAR(1) '$.ruolo',
				Pos TINYINT '$.pos',
				OperatorInternalId BIGINT '$.operatorInternalId',
				PartyUuid UNIQUEIDENTIFIER '$.partyUuid',
				Nome NVARCHAR(500) '$.nome',
				Indirizzo NVARCHAR(1000) '$.indirizzo',
				Paese CHAR(2) '$.paese',
				ContattoNome NVARCHAR(200) '$.contattoNome',
				ContattoTelefono NVARCHAR(100) '$.contattoTelefono',
				ContattoEmail NVARCHAR(200) '$.contattoEmail',
				MezzoTrasporto CHAR(1) '$.mezzoTrasporto',
				ImpiantoIntermedio BIT '$.impiantoIntermedio'
			) j
		WHERE
			j.Ruolo IN ('O', 'P', 'D', 'I', 'T')
			AND j.Pos IS NOT NULL;

		-- Ruoli dell'azienda nel documento: soggetti con l'operatore di una sua sede interna
		UPDATE d
		SET Ruoli = ( SELECT STRING_AGG(r.Ruolo, '') WITHIN GROUP (ORDER BY CHARINDEX(r.Ruolo, 'OPDIT')) FROM ( SELECT DISTINCT s.Ruolo FROM #sog s INNER JOIN dbo.tblDiwassOperatori o ON s.OperatorInternalId = o.OperatorInternalId INNER JOIN dbo.tblSedi x ON o.Id = x.Id WHERE s.Numero = d.Numero AND s.IdAziendaInterna = d.IdAziendaInterna AND x.InternaEsterna = 'I' AND x.IdAziendaInterna = d.IdAziendaInterna ) r )
		FROM #doc d;

		-- Un documento nuovo senza l'azienda tra i soggetti è di un'altra azienda della stessa credenziale
		DELETE #doc
		WHERE
			Id IS NULL
			AND Ruoli IS NULL;
		DELETE s
		FROM #sog s
		WHERE NOT EXISTS ( SELECT 1 FROM #doc d WHERE d.Numero = s.Numero AND d.IdAziendaInterna = s.IdAziendaInterna );

		-- Sede in anagrafica dell'azienda collegata allo stesso operatore (prima le interne)
		UPDATE s
		SET IdSede = ( SELECT TOP 1 o.Id FROM dbo.tblDiwassOperatori o INNER JOIN dbo.tblSedi x ON o.Id = x.Id WHERE o.OperatorInternalId = s.OperatorInternalId AND x.IdAziendaInterna = s.IdAziendaInterna AND x.Lock = 0 ORDER BY IIF(x.InternaEsterna = 'I', 0, 1), x.Id )
		FROM #sog s
		WHERE s.OperatorInternalId IS NOT NULL;

		-- Conferme: posizione del soggetto che conferma (trasportatore o impianto con lo stesso operatore)
		CREATE TABLE #conf (
			IdAziendaInterna CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			Numero VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
			Tipo CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL,
			Pos TINYINT NOT NULL,
			NumeroConferma VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			OperatorInternalId BIGINT NULL,
			Data DATE NULL,
			MezzoTrasporto CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			Targhe VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			UnitaQuantita CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			QuantitaAccettata DECIMAL(18, 5) NULL,
			QuantitaRespinta DECIMAL(18, 5) NULL,
			MotivoRespingimento NVARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			QuantitaRiutilizzo DECIMAL(18, 5) NULL,
			QuantitaRecupero DECIMAL(18, 5) NULL,
			Descrizione NVARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			ContattoNome NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			ContattoTelefono VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			ContattoEmail VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			FirmaNome NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			FirmaRuolo NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			FirmaData DATETIME2(0) NULL,
			FirmaEmail VARCHAR(100) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO #conf (IdAziendaInterna, Numero, Tipo, Pos, NumeroConferma, OperatorInternalId, Data, MezzoTrasporto, Targhe, UnitaQuantita, QuantitaAccettata, QuantitaRespinta, MotivoRespingimento, QuantitaRiutilizzo, QuantitaRecupero, Descrizione, ContattoNome, ContattoTelefono, ContattoEmail, FirmaNome, FirmaRuolo, FirmaData, FirmaEmail)
		SELECT
			d.IdAziendaInterna,
			d.Numero,
			j.Tipo,
			ROW_NUMBER() OVER (PARTITION BY d.IdAziendaInterna, d.Numero, j.Tipo ORDER BY ISNULL(p.Pos, 99), j.Data, j.Numero),
		LEFT(j.Numero, 50),
			j.OperatorInternalId,
			j.Data,
			j.MezzoTrasporto,
		LEFT(j.Targhe, 200),
			j.UnitaQuantita,
			j.QuantitaAccettata,
			j.QuantitaRespinta,
		LEFT(j.MotivoRespingimento, 500),
			j.QuantitaRiutilizzo,
			j.QuantitaRecupero,
		LEFT(j.Descrizione, 500),
		LEFT(j.ContattoNome, 100),
		LEFT(j.ContattoTelefono, 50),
		LEFT(j.ContattoEmail, 100),
		LEFT(j.FirmaNome, 100),
		LEFT(j.FirmaRuolo, 100),
			-- Ora italiana dell'autenticazione (DIWASS la dà con il fuso)
			CAST(SWITCHOFFSET(j.FirmaData, DATEPART(TZOFFSET, SYSDATETIMEOFFSET())) AS DATETIME2(0)),
		LEFT(j.FirmaEmail, 100)
		FROM
			#doc d
			CROSS APPLY OPENJSON(d.Documento, '$.conferme')
			WITH (
				Tipo CHAR(1) '$.tipo',
				Numero NVARCHAR(100) '$.numero',
				OperatorInternalId BIGINT '$.operatorInternalId',
				Data DATE '$.data',
				MezzoTrasporto CHAR(1) '$.mezzoTrasporto',
				Targhe NVARCHAR(400) '$.targhe',
				UnitaQuantita CHAR(1) '$.unitaQuantita',
				QuantitaAccettata DECIMAL(18, 5) '$.quantitaAccettata',
				QuantitaRespinta DECIMAL(18, 5) '$.quantitaRespinta',
				MotivoRespingimento NVARCHAR(1000) '$.motivoRespingimento',
				QuantitaRiutilizzo DECIMAL(18, 5) '$.quantitaRiutilizzo',
				QuantitaRecupero DECIMAL(18, 5) '$.quantitaRecupero',
				Descrizione NVARCHAR(1000) '$.descrizione',
				ContattoNome NVARCHAR(200) '$.contattoNome',
				ContattoTelefono NVARCHAR(100) '$.contattoTelefono',
				ContattoEmail NVARCHAR(200) '$.contattoEmail',
				FirmaNome NVARCHAR(200) '$.firmaNome',
				FirmaRuolo NVARCHAR(200) '$.firmaRuolo',
				FirmaData DATETIMEOFFSET(0) '$.firmaData',
				FirmaEmail NVARCHAR(200) '$.firmaEmail'
			) j
			OUTER APPLY (
				SELECT Pos = MIN(s.Pos)
				FROM #sog s
				WHERE
					s.Numero = d.Numero
					AND s.IdAziendaInterna = d.IdAziendaInterna
					AND s.OperatorInternalId = j.OperatorInternalId
					AND s.Ruolo = CASE j.Tipo WHEN 'T' THEN 'T' WHEN 'D' THEN 'D' ELSE 'I' END
			) p
		WHERE j.Tipo IN ('T', 'D', 'I', 'C');

		-- Id dei documenti nuovi (uspId_get FUORI dalla transazione)
		DECLARE @idNuovo CHAR(16);
		DECLARE @numeroNuovo VARCHAR(50);
		DECLARE @aziendaNuovo CHAR(16);
		DECLARE nuovi CURSOR LOCAL FAST_FORWARD FOR
		SELECT Numero, IdAziendaInterna
		FROM #doc
		WHERE Id IS NULL;
		OPEN nuovi;
		FETCH NEXT
		FROM nuovi INTO @numeroNuovo, @aziendaNuovo;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @idNuovo = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idNuovo OUTPUT;
			UPDATE #doc
			SET
				Id = @idNuovo,
				Ricevuto = 1,
				Nuovo = 1
			WHERE
				Numero = @numeroNuovo
				AND IdAziendaInterna = @aziendaNuovo;
			FETCH NEXT
			FROM nuovi INTO @numeroNuovo, @aziendaNuovo;
		END
		CLOSE nuovi;
		DEALLOCATE nuovi;

		BEGIN TRANSACTION;
			-- Documenti inviati da Ecomatico: solo stato, ruoli e data della lettura
			UPDATE a
			SET
				Stato = ISNULL(JSON_VALUE(d.Documento, '$.stato'), a.Stato),
				DataStato = IIF(ISNULL(JSON_VALUE(d.Documento, '$.stato'), a.Stato) = a.Stato, a.DataStato, GETDATE()),
				Ruoli = ISNULL(d.Ruoli, 'O'),
				DataLettura = d.DataLettura
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN #doc d ON a.Id = d.Id
			WHERE d.Ricevuto = 0;

			-- Documenti ricevuti: dati da DIWASS
			DECLARE @ricevuti TABLE (
				Id CHAR(16) PRIMARY KEY,
				Nuovo BIT,
				IdAziendaInterna CHAR(16),
				Numero VARCHAR(50),
				Stato VARCHAR(20),
				DataInvio SMALLDATETIME,
				TipoDestinazione CHAR(1),
				DataSpedizione DATE,
				Quantita DECIMAL(18, 5),
				UnitaQuantita CHAR(1),
				Contenitore VARCHAR(100),
				LuogoPartenza VARCHAR(300),
				ResponsabileNome VARCHAR(100),
				ResponsabileTelefono VARCHAR(50),
				ResponsabileEmail VARCHAR(100),
				IdEer CHAR(6),
				Descrizione VARCHAR(500),
				CodiceDoganale VARCHAR(50),
				IdNazioneSpedizione CHAR(3),
				IdNazioneDestinazione CHAR(3),
				IdNazioneTransito1 CHAR(3),
				IdNazioneTransito2 CHAR(3),
				IdAttivita CHAR(2),
				ListaCodice VARCHAR(10),
				Codice NVARCHAR(20),
				Ruoli VARCHAR(10),
				DataLettura DATETIME2(0)
			);

			INSERT INTO @ricevuti
			SELECT
				d.Id,
				d.Nuovo,
				d.IdAziendaInterna,
				d.Numero,
				j.Stato,
				j.DataAnnuncio,
				IIF(j.TipoDestinazione IN ('R', 'L'), j.TipoDestinazione, NULL),
				j.DataSpedizione,
				j.Quantita,
				IIF(j.UnitaQuantita IN ('T', 'M'), j.UnitaQuantita, NULL),
				LEFT(j.Contenitore, 100),
				LEFT(j.LuogoPartenza, 300),
				LEFT(j.ResponsabileNome, 100),
				LEFT(j.ResponsabileTelefono, 50),
				LEFT(j.ResponsabileEmail, 100),
				e.Id,
				LEFT(j.Descrizione, 500),
				LEFT(j.CodiceDoganale, 50),
				n1.Id,
				n2.Id,
				n3.Id,
				n4.Id,
				r.Id,
				LEFT(j.ListaCodice, 10),
				LEFT(j.Codice, 20),
				d.Ruoli,
				d.DataLettura
			FROM
				#doc d
				CROSS APPLY OPENJSON(d.Documento)
				WITH (
					Stato VARCHAR(20) '$.stato',
					DataAnnuncio DATE '$.dataAnnuncio',
					TipoDestinazione CHAR(1) '$.tipoDestinazione',
					DataSpedizione DATE '$.dataSpedizione',
					Quantita DECIMAL(18, 5) '$.quantita',
					UnitaQuantita CHAR(1) '$.unitaQuantita',
					Contenitore NVARCHAR(200) '$.contenitore',
					LuogoPartenza NVARCHAR(600) '$.luogoPartenza',
					ResponsabileNome NVARCHAR(200) '$.responsabileNome',
					ResponsabileTelefono NVARCHAR(100) '$.responsabileTelefono',
					ResponsabileEmail NVARCHAR(200) '$.responsabileEmail',
					Eer NVARCHAR(20) '$.eer',
					Descrizione NVARCHAR(1000) '$.descrizione',
					CodiceDoganale NVARCHAR(100) '$.codiceDoganale',
					PaeseSpedizione VARCHAR(10) '$.paeseSpedizione',
					PaeseDestinazione VARCHAR(10) '$.paeseDestinazione',
					PaeseTransito1 VARCHAR(10) '$.paeseTransito1',
					PaeseTransito2 VARCHAR(10) '$.paeseTransito2',
					Operazione VARCHAR(10) '$.operazione',
					ListaCodice NVARCHAR(20) '$.listaCodice',
					Codice NVARCHAR(40) '$.codice'
				) j
				LEFT JOIN dbo.tblRifiutiEer e ON REPLACE(REPLACE(j.Eer, ' ', ''), '*', '') = e.Id
				LEFT JOIN dbo.tblNazioni n1 ON j.PaeseSpedizione = n1.Id
				LEFT JOIN dbo.tblNazioni n2 ON j.PaeseDestinazione = n2.Id
				LEFT JOIN dbo.tblNazioni n3 ON j.PaeseTransito1 = n3.Id
				LEFT JOIN dbo.tblNazioni n4 ON j.PaeseTransito2 = n4.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON j.Operazione = r.Codice
			WHERE d.Ricevuto = 1;

			UPDATE a
			SET
				Stato = r.Stato,
				DataStato = IIF(ISNULL(r.Stato, '') = ISNULL(a.Stato, ''), a.DataStato, GETDATE()),
				DataInvio = r.DataInvio,
				TipoDestinazione = r.TipoDestinazione,
				DataSpedizione = r.DataSpedizione,
				Quantita = r.Quantita,
				UnitaQuantita = r.UnitaQuantita,
				Contenitore = r.Contenitore,
				LuogoPartenza = r.LuogoPartenza,
				ResponsabileNome = r.ResponsabileNome,
				ResponsabileTelefono = r.ResponsabileTelefono,
				ResponsabileEmail = r.ResponsabileEmail,
				IdEer = r.IdEer,
				Descrizione = r.Descrizione,
				CodiceDoganale = r.CodiceDoganale,
				IdNazioneSpedizione = r.IdNazioneSpedizione,
				IdNazioneDestinazione = r.IdNazioneDestinazione,
				IdNazioneTransito1 = r.IdNazioneTransito1,
				IdNazioneTransito2 = r.IdNazioneTransito2,
				IdAttivita = r.IdAttivita,
				ListaCodice = r.ListaCodice,
				Codice = r.Codice,
				Ruoli = r.Ruoli,
				DataLettura = r.DataLettura
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN @ricevuti r ON a.Id = r.Id
			WHERE r.Nuovo = 0;

			INSERT INTO dbo.tblDiwassAllegatiVii (Id, IdAziendaInterna, Numero, Stato, DataInvio, DataStato, TipoDestinazione, DataSpedizione, Quantita, UnitaQuantita, Contenitore, LuogoPartenza, ResponsabileNome, ResponsabileTelefono, ResponsabileEmail, IdEer, Descrizione, CodiceDoganale, IdNazioneSpedizione, IdNazioneDestinazione, IdNazioneTransito1, IdNazioneTransito2, IdAttivita, ListaCodice, Codice, Lock, Ricevuto, Ruoli, DataLettura)
			SELECT r.Id, r.IdAziendaInterna, r.Numero, r.Stato, r.DataInvio, GETDATE(), r.TipoDestinazione, r.DataSpedizione, r.Quantita, r.UnitaQuantita, r.Contenitore, r.LuogoPartenza, r.ResponsabileNome, r.ResponsabileTelefono, r.ResponsabileEmail, r.IdEer, r.Descrizione, r.CodiceDoganale, r.IdNazioneSpedizione, r.IdNazioneDestinazione, r.IdNazioneTransito1, r.IdNazioneTransito2, r.IdAttivita, r.ListaCodice, r.Codice, 0, 1, r.Ruoli, r.DataLettura
			FROM @ricevuti r
			WHERE r.Nuovo = 1;

			-- Soggetti dei documenti ricevuti: quelli di DIWASS
			DELETE x
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN @ricevuti r ON x.Id = r.Id;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, PartyUuid, OperatorInternalId, Nome, Indirizzo, Paese, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio)
			SELECT d.Id, s.Ruolo, s.Pos, s.IdSede, ISNULL(s.PartyUuid, NEWID()), s.OperatorInternalId, s.Nome, s.Indirizzo, s.Paese, s.ContattoNome, s.ContattoTelefono, s.ContattoEmail, s.MezzoTrasporto, s.ImpiantoIntermedio
			FROM
				#sog s
				INNER JOIN #doc d ON s.Numero = d.Numero AND s.IdAziendaInterna = d.IdAziendaInterna
			WHERE d.Ricevuto = 1;

			-- Conferme: quelle di DIWASS, per tutti i documenti importati
			DELETE c
			FROM
				dbo.tblDiwassAllegatiViiConferme c
				INNER JOIN #doc d ON c.Id = d.Id;

			INSERT INTO dbo.tblDiwassAllegatiViiConferme (Id, Tipo, Pos, Numero, OperatorInternalId, Data, MezzoTrasporto, Targhe, UnitaQuantita, QuantitaAccettata, QuantitaRespinta, MotivoRespingimento, QuantitaRiutilizzo, QuantitaRecupero, Descrizione, ContattoNome, ContattoTelefono, ContattoEmail, FirmaNome, FirmaRuolo, FirmaData, FirmaEmail)
			SELECT d.Id, c.Tipo, c.Pos, c.NumeroConferma, c.OperatorInternalId, c.Data, c.MezzoTrasporto, c.Targhe, c.UnitaQuantita, c.QuantitaAccettata, c.QuantitaRespinta, c.MotivoRespingimento, c.QuantitaRiutilizzo, c.QuantitaRecupero, c.Descrizione, c.ContattoNome, c.ContattoTelefono, c.ContattoEmail, c.FirmaNome, c.FirmaRuolo, c.FirmaData, c.FirmaEmail
			FROM
				#conf c
				INNER JOIN #doc d ON c.Numero = d.Numero AND c.IdAziendaInterna = d.IdAziendaInterna;
		COMMIT TRANSACTION;

		SELECT ReturnValue = COUNT(*)
		FROM #doc;

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
