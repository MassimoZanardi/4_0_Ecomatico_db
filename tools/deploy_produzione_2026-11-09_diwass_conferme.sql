/*
Deploy produzione 2026-11-09 - DIWASS: conferme dei passaggi della spedizione

Rieseguibile. Eseguire con sqlcmd -f 65001 -I -b (oppure da SSMS) sul DB 4_0_ecomatico, PRIMA di pubblicare l'app.
Va installato anche 1_0_diwass tools/deploy_produzione_2026-11-09_sincronizzazione_stato.sql prima di pubblicare l'hub.

Conferme dalla scheda dell'Allegato VII (pulsante Conferma nel riquadro Avanzamento): presa in carico del
trasportatore, ricezione del destinatario, ricezione dell'impianto, recupero completato, anche per conto del
destinatario o dell'impianto da parte di chi organizza. Regola D7 in docs/regole/diwass.md (repo app).
1. ufnDiwassAllegatiVii_get_Passaggi (nuova): passaggi della spedizione, confermabili e per conto.
2. uspDiwassAllegatiVii_get_Avanzamento (riscritta sopra la funzione, colonne Proposta*).
3. uspDiwassAllegatiVii_get_Conferma (nuova): dati proposti nella modale di conferma.
4. uspDiwassAllegatiVii_upd_Conferma (nuova): controlli prima dell'invio a DIWASS.
*/
-- ===== ufnDiwassAllegatiVii_get_Passaggi.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Passaggi della spedizione di un Allegato VII visti dall'azienda @IdAzienda (docs/regole/diwass.md D6.7, D7): presa in
-- carico di ogni trasportatore (T), ricezione del destinatario (D), ricezione all'impianto (I) e recupero completato (C)
-- di ogni impianto, con l'operatore DIWASS del soggetto (della sede in anagrafica o letto da DIWASS). DellAzienda = il
-- soggetto ha l'operatore di una sede interna dell'azienda (IdSedeAzienda); Prevista = 0 per la ricezione del
-- destinatario che è anche l'impianto (Reg. di esecuzione UE 2025/1290 art. 17.2); Fatta = DIWASS ha già la conferma.
-- Confermabile = l'azienda può confermare il passaggio ora (D7.1): documento annunciato, in viaggio o ricevuto; presa in
-- carico solo da chi organizza in Ecomatico dal giorno della spedizione (il trasportatore non conferma da un software,
-- 2025/1290 art. 5.2); ricezioni dopo la presa in carico (in viaggio o ricevuto) e recupero completato dopo la
-- ricezione all'impianto, dal soggetto stesso o da chi organizza per suo conto (PerConto, allegato III op. 39-44)
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_Passaggi] (
	@Id CHAR(16),
	@IdAzienda CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH soggetti AS (
		SELECT
			x.Ruolo,
			x.Pos,
			x.IdSede,
			OperatorInternalId = ISNULL(o.OperatorInternalId, x.OperatorInternalId),
			Nome = ISNULL(s.NomeCompleto, x.Nome),
			x.MezzoTrasporto,
			x.ContattoNome,
			x.ContattoTelefono,
			x.ContattoEmail
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			LEFT JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
		WHERE
			x.Id = @Id
			AND x.Ruolo IN ('T', 'D', 'I')
	)
	SELECT
		p.Ordine,
		p.Tipo,
		s.Pos,
		s.OperatorInternalId,
		SoggettoNome = s.Nome,
		DellAzienda = CAST(IIF(sa.Id IS NULL, 0, 1) AS BIT),
		IdSedeAzienda = sa.Id,
		Prevista = CAST(IIF(p.Tipo = 'D' AND v.DestinatarioImpianto = 1, 0, 1) AS BIT),
		Fatta = CAST(IIF(k.Fatta IS NULL, 0, 1) AS BIT),
		Confermabile = CAST(CASE
			WHEN a.Lock <> 0 OR ISNULL(a.Stato, '') NOT IN ('ANNOUNCED', 'MOVING', 'RECEIVED') OR k.Fatta IS NOT NULL THEN 0
			WHEN p.Tipo = 'T' THEN IIF(ISNULL(a.Ricevuto, 0) = 0 AND a.DataSpedizione <= CAST(GETDATE() AS DATE), 1, 0)
			WHEN sa.Id IS NULL AND v.Organizza = 0 THEN 0
			WHEN p.Tipo = 'D' THEN IIF(v.DestinatarioImpianto = 0 AND a.Stato IN ('MOVING', 'RECEIVED'), 1, 0)
			WHEN p.Tipo = 'I' THEN IIF(a.Stato IN ('MOVING', 'RECEIVED'), 1, 0)
			ELSE IIF(EXISTS (
				SELECT 1
				FROM dbo.tblDiwassAllegatiViiConferme r
				WHERE
					r.Id = @Id
					AND r.Tipo = 'I'
					AND r.OperatorInternalId = s.OperatorInternalId
					AND r.Data IS NOT NULL
			), 1, 0)
		END AS BIT),
		PerConto = CAST(IIF(p.Tipo <> 'T' AND sa.Id IS NULL, 1, 0) AS BIT),
		s.MezzoTrasporto,
		ContattoNome = ISNULL(s.ContattoNome, c.Nome),
		ContattoTelefono = ISNULL(s.ContattoTelefono, c.Telefono),
		ContattoEmail = ISNULL(s.ContattoEmail, c.Email)
	FROM
		dbo.tblDiwassAllegatiVii a
		CROSS APPLY (
			SELECT
				Organizza = IIF(ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')) LIKE '%O%', 1, 0),
				DestinatarioImpianto = IIF(EXISTS (
					SELECT 1
					FROM
						soggetti d
						INNER JOIN soggetti i ON d.OperatorInternalId = i.OperatorInternalId
					WHERE
						d.Ruolo = 'D'
						AND i.Ruolo = 'I'
				), 1, 0)
		) v
						INNER JOIN soggetti s ON 1 = 1
						CROSS APPLY (
			SELECT
				Ordine = CASE s.Ruolo WHEN 'T' THEN 0 WHEN 'D' THEN 1 ELSE 2 END,
				Tipo = s.Ruolo
			UNION ALL
			SELECT
				Ordine = 2,
				Tipo = 'C'
			WHERE s.Ruolo = 'I') p
						OUTER APPLY (
			SELECT TOP 1 Fatta = 1
			FROM dbo.tblDiwassAllegatiViiConferme k
			WHERE
				k.Id = @Id
				AND k.Tipo = p.Tipo
				AND k.OperatorInternalId = s.OperatorInternalId
				AND k.Data IS NOT NULL
						) k
			OUTER APPLY (
			SELECT TOP 1 x.Id
			FROM
				dbo.tblDiwassOperatori o
				INNER JOIN dbo.tblSedi x ON o.Id = x.Id
			WHERE
				o.OperatorInternalId = s.OperatorInternalId
				AND x.InternaEsterna = 'I'
				AND x.IdAziendaInterna = @IdAzienda
			ORDER BY IIF(x.Id = s.IdSede, 0, 1), x.Id
		) sa
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(ISNULL(s.IdSede, sa.Id)) c
	WHERE a.Id = @Id);
GO
-- ===== uspDiwassAllegatiVii_get_Avanzamento.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'Allegato VII, riquadro "Avanzamento della spedizione": una riga per passaggio previsto, nell'ordine del
-- documento (presa in carico di ogni trasportatore, ricezione del destinatario, ricezione e recupero completato di ogni
-- impianto), con la conferma letta da DIWASS se c'è (stesso operatore del soggetto). Passaggi, ricezione del
-- destinatario non prevista, soggetti dell'azienda e passaggi che l'azienda può confermare da
-- ufnDiwassAllegatiVii_get_Passaggi; per la finestra di conferma, contatto e mezzo proposti, nome di chi firma (utente
-- della sessione) e ruolo proposto (l'ultimo dell'utente per l'azienda, altrimenti quello del documento). Regole in
-- docs/regole/diwass.md D6, D7
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Avanzamento]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione (lettura; per confermare serve la scrittura)
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

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		DECLARE @firmaRuolo VARCHAR(100);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente,
			@firmaRuolo = a.FirmaRuolo
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @firmaNome VARCHAR(100) = (
			SELECT NULLIF(LTRIM(RTRIM(ISNULL(Nome, '') + ' ' + ISNULL(Cognome, ''))), '')
			FROM dbo.tblUtenti
			WHERE Id = @idUtente);
		SET @firmaRuolo = ISNULL((
			SELECT Ruolo
			FROM dbo.tblDiwassFirmeRuoli
			WHERE
				IdUtente = @idUtente
				AND IdAziendaInterna = @idAzienda
		), @firmaRuolo);

		SELECT
			p.Ordine,
			p.Tipo,
			p.Pos,
			Passaggio = CASE p.Tipo
				WHEN 'T' THEN N'Presa in carico'
				WHEN 'D' THEN N'Ricezione del destinatario'
				WHEN 'I' THEN N'Ricezione all''impianto'
				ELSE N'Recupero completato'
			END,
			p.SoggettoNome,
			p.OperatorInternalId,
			p.DellAzienda,
			p.Prevista,
			Confermabile = CAST(IIF(p.Confermabile = 1 AND @permesso >= 2, 1, 0) AS BIT),
			p.PerConto,
			PropostaMezzoTrasporto = p.MezzoTrasporto,
			PropostaContattoNome = p.ContattoNome,
			PropostaContattoTelefono = p.ContattoTelefono,
			PropostaContattoEmail = p.ContattoEmail,
			PropostaFirmaNome = @firmaNome,
			PropostaFirmaRuolo = @firmaRuolo,
			NumeroConferma = c.Numero,
			c.Data,
			c.MezzoTrasporto,
			c.Targhe,
			c.UnitaQuantita,
			c.QuantitaAccettata,
			c.QuantitaRespinta,
			c.MotivoRespingimento,
			c.QuantitaRiutilizzo,
			c.QuantitaRecupero,
			c.Descrizione,
			c.FirmaNome,
			c.FirmaRuolo,
			c.FirmaData
		FROM
			dbo.ufnDiwassAllegatiVii_get_Passaggi(@Id, @idAzienda) p
			OUTER APPLY (
				SELECT TOP 1 *
				FROM dbo.tblDiwassAllegatiViiConferme k
				WHERE
					k.Id = @Id
					AND k.Tipo = p.Tipo
					AND k.OperatorInternalId = p.OperatorInternalId
				ORDER BY k.Pos
			) c
		ORDER BY p.Ordine, p.Pos, IIF(p.Tipo = 'C', 1, 0);

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
-- ===== uspDiwassAllegatiVii_get_Conferma.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Conferma di un passaggio dell'Allegato VII da mandare all'hub DIWASS (docs/regole/diwass.md D7): @Tipo T presa in
-- carico, D ricezione del destinatario, I ricezione all'impianto, C recupero completato, del soggetto con l'operatore
-- @OperatorInternalId. Controlla che l'azienda del contesto possa confermare il passaggio
-- (ufnDiwassAllegatiVii_get_Passaggi) e restituisce in un solo messaggio tutto quello che manca o non va. Date: non nel
-- futuro; presa in carico dal giorno della spedizione; ricezioni dalla prima presa in carico; recupero completato dalla
-- ricezione all'impianto ed entro un anno (Reg. UE 2024/1157 art. 18.9). La ricezione all'impianto oltre i due giorni
-- lavorativi (art. 18.9, giorni lavorativi del Reg. di esecuzione UE 2025/1290 art. 2.16) non si blocca: avviso nel JSON.
-- La firma è dell'utente della sessione (nome, email) con il ruolo indicato. Restituisce rtn = JSON (assegnato a
-- variabile, così non viene spezzato in più righe)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Conferma]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@OperatorInternalId BIGINT = NULL,
	@Data DATE = NULL,
	@MezzoTrasporto CHAR(1) = NULL,
	@Targhe VARCHAR(200) = NULL,
	@QuantitaAccettata DECIMAL(18, 5) = NULL,
	@QuantitaRespinta DECIMAL(18, 5) = NULL,
	@MotivoRespingimento NVARCHAR(500) = NULL,
	@QuantitaRiutilizzo DECIMAL(18, 5) = NULL,
	@QuantitaRecupero DECIMAL(18, 5) = NULL,
	@Descrizione NVARCHAR(500) = NULL,
	@ContattoNome VARCHAR(100) = NULL,
	@ContattoTelefono VARCHAR(50) = NULL,
	@ContattoEmail VARCHAR(100) = NULL,
	@FirmaRuolo VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(2000) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');
		SET @MezzoTrasporto = NULLIF(LTRIM(RTRIM(@MezzoTrasporto)), '');
		SET @Targhe = dbo.ufnStringhe_get_SenzaSpazi(@Targhe, 0, 1);
		SET @MotivoRespingimento = dbo.ufnStringhe_get_SenzaSpazi(@MotivoRespingimento, 0, 1);
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @ContattoNome = dbo.ufnStringhe_get_SenzaSpazi(@ContattoNome, 0, 1);
		SET @ContattoTelefono = dbo.ufnStringhe_get_SenzaSpazi(@ContattoTelefono, 0, 1);
		SET @ContattoEmail = dbo.ufnStringhe_get_SenzaSpazi(@ContattoEmail, 0, 1);
		SET @FirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@FirmaRuolo, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL OR ISNULL(@Tipo, '') NOT IN ('T', 'D', 'I', 'C') OR @OperatorInternalId IS NULL
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
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		DECLARE @numero VARCHAR(50);
		DECLARE @dataSpedizione DATE;
		DECLARE @unitaQuantita CHAR(1);
		DECLARE @descrizioneDocumento NVARCHAR(500);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente,
			@numero = a.Numero,
			@dataSpedizione = a.DataSpedizione,
			@unitaQuantita = a.UnitaQuantita,
			@descrizioneDocumento = a.Descrizione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione
			AND a.Lock = 0;
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		-- Passaggio che l'azienda può confermare ora
		DECLARE @fatta BIT;
		DECLARE @confermabile BIT;
		DECLARE @perConto BIT;
		SELECT
			@fatta = Fatta,
			@confermabile = Confermabile,
			@perConto = PerConto
		FROM dbo.ufnDiwassAllegatiVii_get_Passaggi(@Id, @idAzienda)
		WHERE
			Tipo = @Tipo
			AND OperatorInternalId = @OperatorInternalId;
		IF @confermabile IS NULL
			SET @returnMessage = 'Il soggetto non è nell''Allegato VII per questo passaggio';
		ELSE IF @fatta = 1
			SET @returnMessage = 'Il passaggio è già confermato su DIWASS';
		ELSE IF @confermabile = 0
			SET @returnMessage = 'Il passaggio non si può confermare ora: leggere lo stato aggiornato con Azioni > DIWASS – Leggi stato';
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

		-- Date di riferimento dalle conferme già lette da DIWASS
		DECLARE @presaInCarico DATE = (
			SELECT MIN(Data)
			FROM dbo.tblDiwassAllegatiViiConferme
			WHERE
				Id = @Id
				AND Tipo = 'T'
		);
		DECLARE @ricezioneImpianto DATE = (
			SELECT MIN(Data)
			FROM dbo.tblDiwassAllegatiViiConferme
			WHERE
				Id = @Id
				AND Tipo = 'I'
				AND OperatorInternalId = @OperatorInternalId
		);

		-- Valori proposti dal documento
		SET @Descrizione = ISNULL(@Descrizione, @descrizioneDocumento);
		IF @Tipo = 'I'
			SET @QuantitaRespinta = ISNULL(@QuantitaRespinta, 0);
		IF @Tipo = 'C'
		BEGIN
			SET @QuantitaRiutilizzo = ISNULL(@QuantitaRiutilizzo, 0);
			SET @QuantitaRecupero = ISNULL(@QuantitaRecupero, 0);
		END

		DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Testo NVARCHAR(300));
		INSERT INTO @mancanti (Testo)
		SELECT x.Testo
		FROM (
			VALUES
				(IIF(@Data IS NULL, N'data', NULL)),
				(IIF(@Data > CAST(GETDATE() AS DATE), N'data non successiva a oggi', NULL)),
				(IIF(@Tipo = 'T' AND @Data < @dataSpedizione, N'data non precedente alla spedizione (' + CONVERT(VARCHAR(10), @dataSpedizione, 103) + ')', NULL)),
				(IIF(@Tipo IN ('D', 'I') AND @Data < ISNULL(@presaInCarico, @dataSpedizione), N'data non precedente alla presa in carico (' + CONVERT(VARCHAR(10), ISNULL(@presaInCarico, @dataSpedizione), 103) + ')', NULL)),
				(IIF(@Tipo = 'C' AND @Data < @ricezioneImpianto, N'data non precedente alla ricezione all''impianto (' + CONVERT(VARCHAR(10), @ricezioneImpianto, 103) + ')', NULL)),
				(IIF(@Tipo = 'C' AND @Data > DATEADD(YEAR, 1, @ricezioneImpianto), N'data entro un anno dalla ricezione all''impianto (' + CONVERT(VARCHAR(10), DATEADD(YEAR, 1, @ricezioneImpianto), 103) + ')', NULL)),
				(IIF(@Tipo = 'T' AND ISNULL(@MezzoTrasporto, '') NOT IN ('R', 'T', 'S', 'A', 'W'), N'mezzo di trasporto', NULL)),
				(IIF(@Tipo = 'I' AND @QuantitaAccettata IS NULL, N'quantità accettata', NULL)),
				(IIF(@Tipo = 'I' AND (@QuantitaAccettata < 0 OR @QuantitaRespinta < 0), N'quantità non negative', NULL)),
				(IIF(@Tipo = 'I' AND @QuantitaAccettata = 0 AND @QuantitaRespinta = 0, N'quantità accettata o respinta', NULL)),
				(IIF(@Tipo = 'I' AND @QuantitaRespinta > 0 AND @MotivoRespingimento IS NULL, N'motivo del respingimento', NULL)),
				(IIF(@Tipo = 'C' AND (@QuantitaRiutilizzo < 0 OR @QuantitaRecupero < 0), N'quantità non negative', NULL)),
				(IIF(@Tipo = 'C' AND @QuantitaRiutilizzo = 0 AND @QuantitaRecupero = 0, N'quantità preparata per il riutilizzo o riciclata, o recuperata in altro modo', NULL)),
				(IIF(@Tipo IN ('I', 'C') AND @Descrizione IS NULL, N'descrizione del rifiuto', NULL)),
				(IIF(@ContattoNome IS NULL OR @ContattoTelefono IS NULL OR @ContattoEmail IS NULL, N'nome, telefono ed email del contatto', NULL)),
				(IIF(@FirmaRuolo IS NULL, N'ruolo di chi firma', NULL)),
				(IIF(@firmaNome IS NULL OR @firmaEmail IS NULL, N'nome ed email dell''utente che firma (Impostazioni > Utenti)', NULL))
		) x (Testo)
		WHERE x.Testo IS NOT NULL;

		IF EXISTS (SELECT 1
		FROM @mancanti)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = LEFT(N'Per confermare su DIWASS correggere o completare: '
				+ STUFF((SELECT N'; ' + Testo
				FROM @mancanti ORDER BY Pos FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), 2000);
			GOTO BRANCH_END;
		END

		-- Ricezione all'impianto oltre i due giorni lavorativi: si conferma comunque, con l'avviso
		DECLARE @avviso NVARCHAR(300) = IIF(@Tipo = 'I' AND dbo.ufnDiwassAllegatiVii_get_DataSpedizioneMinima(@Data) < CAST(GETDATE() AS DATE),
			N'confermata oltre i due giorni lavorativi dalla ricezione previsti dal Reg. UE 2024/1157 (art. 18)', NULL);

		DECLARE @json NVARCHAR(MAX) = (
			SELECT
				idCredenziale = @idCredenziale,
				numero = @numero,
				tipo = @Tipo,
				operatorInternalId = @OperatorInternalId,
				perConto = @perConto,
				contattoNome = @ContattoNome,
				contattoTelefono = @ContattoTelefono,
				contattoEmail = @ContattoEmail,
				data = @Data,
				mezzoTrasporto = IIF(@Tipo = 'T', @MezzoTrasporto, NULL),
				targhe = IIF(@Tipo = 'T', @Targhe, NULL),
				unitaQuantita = @unitaQuantita,
				quantitaAccettata = ISNULL(@QuantitaAccettata, 0),
				quantitaRespinta = ISNULL(@QuantitaRespinta, 0),
				motivoRespingimento = IIF(@QuantitaRespinta > 0, @MotivoRespingimento, NULL),
				quantitaRiutilizzo = ISNULL(@QuantitaRiutilizzo, 0),
				quantitaRecupero = ISNULL(@QuantitaRecupero, 0),
				descrizione = @Descrizione,
				firmaNome = @firmaNome,
				firmaRuolo = @FirmaRuolo,
				firmaEmail = @firmaEmail,
				avviso = @avviso
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

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
-- ===== uspDiwassAllegatiVii_upd_Conferma.sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dopo una conferma registrata su DIWASS (docs/regole/diwass.md D7): ricorda il ruolo di chi ha firmato, proposto alla
-- conferma o all'invio successivo dello stesso utente per l'azienda (tblDiwassFirmeRuoli, come all'invio). La conferma
-- arriva in tblDiwassAllegatiViiConferme con l'importazione del documento riletto dall'hub
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd_Conferma]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@FirmaRuolo VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @FirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@FirmaRuolo, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
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
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @FirmaRuolo IS NOT NULL
			MERGE dbo.tblDiwassFirmeRuoli AS t
			USING (
				SELECT
					IdUtente = @idUtente,
					IdAziendaInterna = @idAzienda,
					Ruolo = @FirmaRuolo
			) AS s
			ON t.IdUtente = s.IdUtente AND t.IdAziendaInterna = s.IdAziendaInterna
			WHEN MATCHED THEN UPDATE
			SET Ruolo = s.Ruolo WHEN NOT MATCHED THEN INSERT (IdUtente, IdAziendaInterna, Ruolo) VALUES (s.IdUtente, s.IdAziendaInterna, s.Ruolo);

		SELECT rtn = 1;

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
PRINT 'Deploy 2026-11-09 DIWASS conferme completato';
GO
