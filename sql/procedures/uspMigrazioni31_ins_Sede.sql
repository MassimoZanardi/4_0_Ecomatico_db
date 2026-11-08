SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1: crea in 4.0 una sede a partire da una sede della 3.1. SP interna di uspMigrazioni31_ins,
-- eseguita dentro la sua transazione; scrive gli avvisi nella tabella temporanea #log del chiamante.
-- Replica i passi di uspSedi_ins + uspSedi_upd (domini-aziende-sedi.md, D2/D3) senza passare dal contesto della
-- sessione: Osepe (Tipo S), sede confermata (Lock = 0), azienda interna (tblSediInterne) o soggetto (tblSediEsterne)
-- se radice, indirizzo, recapiti (Telefono -> T0, Email -> M0), dati estesi, NomeCompleto, IndirizzoCompleto,
-- IdAziendaInterna; codice fiscale e partita IVA ereditati dal padre per le sedi di tipo A e G (D2.4); unita' locale
-- sulla radice del gruppo (D2.5).
-- - @IdParent: sede 4.0 padre (NULL per una radice);
-- - @InternaEsterna: 'I' sede interna, 'E' sede esterna;
-- - @IdAziendaInterna: per una radice esterna, l'azienda interna 4.0 proprietaria del soggetto (tblSediEsterne).
-- Indirizzo 3.1 ViaENumeroCivico: il numero civico e' la parte dopo l'ultima virgola se contiene una cifra ed e' lungo
-- al massimo 10 caratteri, altrimenti tutto resta in Indirizzo. Comune non piu' presente in 4.0: si prova
-- tblMappingComuniSardegna della 3.1, altrimenti comune vuoto e avviso nel log.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Sede
	@IdMigrazione INT = NULL,
	@IdDominioA CHAR(16) = NULL,
	@IdSede31 CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL,
	@InternaEsterna CHAR(1) = NULL,
	@IdAziendaInterna CHAR(16) = NULL,
	@Id CHAR(16) = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULL;

		IF @IdMigrazione IS NULL OR @IdDominioA IS NULL OR @IdSede31 IS NULL OR ISNULL(@InternaEsterna, '') NOT IN ('I', 'E')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri della sede da migrare incompleti';
			GOTO BRANCH_END;
		END

		IF @IdParent IS NULL AND @InternaEsterna = 'E' AND @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un soggetto richiede l''azienda interna proprietaria';
			GOTO BRANCH_END;
		END

		-- Dati della sede 3.1
		DECLARE @tipo31 CHAR(1);
		DECLARE @nome VARCHAR(50);
		DECLARE @cognome VARCHAR(50);
		DECLARE @codiceFiscale VARCHAR(20);
		DECLARE @partitaIva VARCHAR(20);
		DECLARE @codice VARCHAR(20);
		DECLARE @note VARCHAR(1000);
		DECLARE @telefono VARCHAR(100);
		DECLARE @email VARCHAR(100);
		DECLARE @dataInserimento DATETIME2(0);

		SELECT
			@tipo31 = s.Tipo,
			@nome = NULLIF(LTRIM(RTRIM(s.Nome)), ''),
			@cognome = NULLIF(LTRIM(RTRIM(s.Cognome)), ''),
			@codiceFiscale = NULLIF(LTRIM(RTRIM(s.CodiceFiscale)), ''),
			@partitaIva = NULLIF(LTRIM(RTRIM(s.PartitaIva)), ''),
			@codice = NULLIF(LTRIM(RTRIM(s.CodiceGestionale)), ''),
			@note = NULLIF(LTRIM(RTRIM(s.Note)), ''),
			@telefono = NULLIF(LTRIM(RTRIM(s.Telefono)), ''),
			@email = NULLIF(LTRIM(RTRIM(s.Email)), ''),
			@dataInserimento = x.DataInserimento
		FROM
			dbo.syn31Sedi s
			LEFT JOIN dbo.syn31ID x ON s.IDSede = x.ID
		WHERE s.IDSede = @IdSede31;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = CONCAT('Sede della 3.1 non trovata: ', @IdSede31);
			GOTO BRANCH_END;
		END

		DECLARE @idTipo CHAR(1) = (SELECT CodiceDestinazione
		FROM dbo.tblMigrazioniCodici
		WHERE
			Versione = '31'
			AND Tabella = 'tblSediTipi'
			AND CodiceOrigine = @tipo31 COLLATE DATABASE_DEFAULT
		);

		IF @idTipo IS NULL
		BEGIN
			-- Radice senza tipo: sede legale (come uspSedi_ins da Rifiuti, D3.1); sede figlia: sede generica
			SET @idTipo = IIF(@IdParent IS NULL, 'L', 'G');

			INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
			VALUES ('Sedi', 'W', 'tblSedi', @IdSede31, CONCAT('Tipo di sede ', ISNULL(@tipo31, '(vuoto)'), ' non mappato: impostato ', @idTipo));
		END

		-- Indirizzo 3.1 (al massimo uno per sede)
		DECLARE @idIndirizzo31 UNIQUEIDENTIFIER;
		DECLARE @via VARCHAR(50);
		DECLARE @civico VARCHAR(10);
		DECLARE @localita VARCHAR(50);
		DECLARE @cap VARCHAR(10);
		DECLARE @idComune31 CHAR(6);
		DECLARE @idComune CHAR(6);
		DECLARE @idNazione CHAR(3);

		SELECT TOP (1)
			@idIndirizzo31 = i.IDIndirizzo,
			@via = NULLIF(LTRIM(RTRIM(i.ViaENumeroCivico)), ''),
			@localita = NULLIF(LTRIM(RTRIM(i.[Località])), ''),
			@cap = NULLIF(LTRIM(RTRIM(i.CAP)), ''),
			@idComune31 = NULLIF(LTRIM(RTRIM(i.IDComune)), ''),
			@idNazione = NULLIF(LTRIM(RTRIM(i.IDNazione)), '')
		FROM
			dbo.syn31SediIndirizzi si
			INNER JOIN dbo.syn31Indirizzi i ON si.IDIndirizzo = i.IDIndirizzo
		WHERE si.IDSede = @IdSede31;

		DECLARE @virgola INT = IIF(@via IS NULL, 0, LEN(@via) - CHARINDEX(',', REVERSE(@via)) + 1);

		IF @via IS NOT NULL AND CHARINDEX(',', @via) > 0
		BEGIN
			DECLARE @parteCivico VARCHAR(50) = LTRIM(RTRIM(SUBSTRING(@via, @virgola + 1, 50)));

			IF @parteCivico LIKE '%[0-9]%' AND LEN(@parteCivico) <= 10
			BEGIN
				SET @civico = @parteCivico;
				SET @via = NULLIF(LTRIM(RTRIM(LEFT(@via, @virgola - 1))), '');
			END
		END

		IF @idComune31 IS NOT NULL
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblComuni
			WHERE Id = @idComune31 COLLATE DATABASE_DEFAULT)
				SET @idComune = @idComune31;
			ELSE
			BEGIN
				SELECT @idComune = c.Id
				FROM
					dbo.syn31MappingComuniSardegna ms
					INNER JOIN dbo.tblComuni c ON ms.IDComuneNuovo = c.Id COLLATE DATABASE_DEFAULT
				WHERE ms.IDComune = @idComune31;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
				VALUES ('Sedi', 'W', 'tblIndirizzi', @IdSede31, CONCAT('Comune ', @idComune31, ' non presente nella 4.0: ', ISNULL('sostituito con ' + @idComune + ' (mappatura Sardegna)', 'indirizzo senza comune')));
			END
		END

		IF @idNazione IS NOT NULL
			AND NOT EXISTS (SELECT 1
			FROM dbo.tblNazioni
			WHERE Id = @idNazione COLLATE DATABASE_DEFAULT)
		BEGIN
			INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
			VALUES ('Sedi', 'W', 'tblIndirizzi', @IdSede31, CONCAT('Nazione ', @idNazione, ' non presente nella 4.0: impostata Italia'));

			SET @idNazione = NULL;
		END

		SET @idNazione = ISNULL(@idNazione, '380');

		-- Sede
		EXEC dbo.uspMigrazioniId_ins
			@Versione = '31',
			@IdDominioA = @IdDominioA,
			@Tabella = 'tblSedi',
			@IdOrigine = @IdSede31,
			@IdMigrazione = @IdMigrazione,
			@DataInserimento = @dataInserimento,
			@Id = @Id OUTPUT;

		INSERT INTO dbo.tblOsepe (Id, Tipo)
		VALUES (@Id, 'S');

		INSERT INTO dbo.tblSedi (Id, IdParent, InternaEsterna, IdTipo, Nome, Cognome, CodiceFiscale, PartitaIva, Codice, Note, Disabilitata, UnitaLocale, Lock)
		VALUES (@Id, @IdParent, @InternaEsterna, @idTipo, @nome, @cognome, @codiceFiscale, @partitaIva, @codice, @note, 0, IIF(@IdParent IS NULL, 1, 0), 0);

		IF @IdParent IS NULL AND @InternaEsterna = 'I'
			INSERT INTO dbo.tblSediInterne (Id, IdDominio)
			VALUES (@Id, @IdDominioA);
		ELSE IF @IdParent IS NULL AND @InternaEsterna = 'E'
			INSERT INTO dbo.tblSediEsterne (Id, IdSedeInterna)
			VALUES (@Id, @IdAziendaInterna);

		-- Indirizzo (come uspSedi_upd: sempre presente, anche vuoto)
		DECLARE @idIndirizzo CHAR(16);

		EXEC dbo.uspMigrazioniId_ins
			@Versione = '31',
			@IdDominioA = @IdDominioA,
			@Tabella = 'tblIndirizzi',
			@IdOrigine = @IdSede31,
			@IdMigrazione = @IdMigrazione,
			@DataInserimento = @dataInserimento,
			@Id = @idIndirizzo OUTPUT;

		INSERT INTO dbo.tblIndirizzi (Id, Indirizzo, NumeroCivico, CAP, Localita, IdComune, IdNazione)
		VALUES (@idIndirizzo, @via, @civico, @cap, @localita, @idComune, @idNazione);

		INSERT INTO dbo.tblSediIndirizzi (Id, IdIndirizzo)
		VALUES (@Id, @idIndirizzo);

		-- Recapiti
		INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore)
		SELECT @Id, 'T0', @telefono
		WHERE @telefono IS NOT NULL;

		INSERT INTO dbo.tblSediRecapiti (Id, IdRecapito, Valore)
		SELECT @Id, 'M0', @email
		WHERE @email IS NOT NULL;

		-- Dati estesi
		INSERT INTO dbo.tblSediDatiEstesi (Id, IdAteco, NumeroRea, Dipendenti, LegaleNome, LegaleCognome)
		SELECT
			@Id,
			NULLIF(LTRIM(RTRIM(d.CodiceAteco)), ''),
			NULLIF(LTRIM(RTRIM(d.CodiceREA)), ''),
			d.Dipendenti,
			NULLIF(LTRIM(RTRIM(d.LegaleNome)), ''),
			NULLIF(LTRIM(RTRIM(d.LegaleCognome)), '')
		FROM dbo.syn31SediDatiEstesi d
		WHERE d.IDSede = @IdSede31;

		-- Campi calcolati, come uspSedi_upd
		UPDATE s
		SET
			CodiceFiscale = IIF(s.IdTipo IN ('A', 'G') AND sl.Id IS NOT NULL, sl.CodiceFiscale, s.CodiceFiscale),
			PartitaIva = IIF(s.IdTipo IN ('A', 'G') AND sl.Id IS NOT NULL, sl.PartitaIva, s.PartitaIva),
			NomeCompleto = COALESCE(s.Cognome + ' ' + s.Nome, s.Nome, sl.Nome),
			IndirizzoCompleto = CASE WHEN i.IdNazione = '380' THEN ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.Localita + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(c.Nome + ' (' + p.Sigla + ')', '') ELSE ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(i.Localita + ' ', '') + ISNULL(n.Nome, '') END,
			IdAziendaInterna = IIF(s.InternaEsterna = 'I', ISNULL(s.IdParent, s.Id), ISNULL(se.IdSedeInterna, sle.IdSedeInterna))
		FROM
			dbo.tblSedi s
			LEFT JOIN dbo.tblSedi sl ON s.IdParent = sl.Id
			LEFT JOIN dbo.tblSediEsterne se ON s.Id = se.Id
			LEFT JOIN dbo.tblSediEsterne sle ON s.IdParent = sle.Id
			LEFT JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
			LEFT JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			LEFT JOIN dbo.tblComuni c ON i.IdComune = c.Id
			LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
			LEFT JOIN dbo.tblNazioni n ON i.IdNazione = n.Id
		WHERE s.Id = @Id;

		INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
		VALUES ('Sedi', 'I', 'tblSedi', @IdSede31, 1, CONCAT('Creata ', IIF(@InternaEsterna = 'I', 'sede interna ', 'sede esterna '), @Id, ': ', COALESCE(@cognome + ' ' + @nome, @nome, '(senza nome)')));
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
