SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1: perimetro, abbinamenti e anomalie, in sola lettura. SP interna, chiamata da
-- uspMigrazioni31_get_Verifica e uspMigrazioni31_ins: il chiamante crea le tabelle temporanee che questa SP riempie
-- (#aziende, #registri, #registrazioni, #autorizzazioni, #sedi, #abbinamenti, #soggetti, #anomalie; struttura in
-- uspMigrazioni31_get_Verifica).
-- Perimetro: registri delle aziende interne del dominio 3.1 (@IdSedeInternaDa NULL) oppure della sola sede interna
-- indicata (la sede del registro o la sua azienda interna); tutte le registrazioni dei registri con Lock = 0, di ogni
-- anno, esclusi i formulari (tblRifiutiSchede: se ne legge solo numero e data di inizio trasporto).
-- Anomalie: Livello E = blocca la migrazione, W = record scartato o dato perso, I = informazione.
-- Le relazioni con quantita' -1 sono, nella 3.1, le derivazioni (carico CMC/CRC nato da un trattamento SFC): in 4.0
-- diventano padre = carico K/M, figlio = scarico R, Operazione 'C', quantita' = quella del carico K/M. Le altre sono
-- consumi: padre = scarico, figlio = carico, Operazione 'S'. Un CRC (M) puo' essere anche consumato (da R o S).
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_get_Perimetro
	@IdDominioDa VARCHAR(50) = NULL,
	@IdSedeInternaDa VARCHAR(50) = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdDominioDa = NULLIF(LTRIM(RTRIM(@IdDominioDa)), '');
		SET @IdSedeInternaDa = NULLIF(LTRIM(RTRIM(@IdSedeInternaDa)), '');
		SET @IdDominioA = NULLIF(LTRIM(RTRIM(@IdDominioA)), '');

		IF @IdDominioDa IS NULL OR @IdDominioA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdDominioDa e @IdDominioA sono obbligatori';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.syn31Domini
		WHERE IDDominio = @IdDominioDa)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dominio di origine non trovato nella 3.1';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE Id = @IdDominioA)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dominio di destinazione non trovato nella 4.0';
			GOTO BRANCH_END;
		END

		-- Aziende interne del dominio di origine
		INSERT INTO #aziende (Id)
		SELECT si.IDSede
		FROM dbo.syn31SediInterne si
		WHERE si.IDDominio = @IdDominioDa;

		IF @IdSedeInternaDa IS NOT NULL
			AND NOT EXISTS (SELECT 1
			FROM
				dbo.syn31Sedi s
				INNER JOIN #aziende a ON s.IDAziendaInterna = a.Id COLLATE DATABASE_DEFAULT
			WHERE s.IDSede = @IdSedeInternaDa)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede interna di origine non appartiene al dominio di origine';
			GOTO BRANCH_END;
		END

		-- Registri del perimetro
		INSERT INTO #registri (Id, IdSede, IdAzienda, IdTipo)
		SELECT g.IDRegistro, g.IDSede, s.IDAziendaInterna, g.IDTipo
		FROM
			dbo.syn31RifiutiRegistri g
			INNER JOIN dbo.syn31Sedi s ON g.IDSede = s.IDSede
			INNER JOIN #aziende a ON s.IDAziendaInterna = a.Id COLLATE DATABASE_DEFAULT
		WHERE
			ISNULL(g.Lock, 0) = 0
			AND
				(
				@IdSedeInternaDa IS NULL
				OR g.IDSede = @IdSedeInternaDa
				OR s.IDAziendaInterna = @IdSedeInternaDa
				);

		-- Registrazioni dei registri (tutte, anche quelle escluse, per il riepilogo). Si importano (Importabile = 1, sempre
		-- con Lock = 0) quelle dei gruppi:
		-- A) dal 01/01/2025;
		-- B) carichi precedenti associati a uno scarico del gruppo A oppure con quantita' residua oggi, calcolata come la
		--    3.1 (viewRifiutiMovimentiPerGiacenze): carico (operazione C) con EER, non di rettifica, quantita' effettiva
		--    ISNULL(QuantitaRettifica, Quantita) meno i prelievi (relazioni con quantita' > 0) degli scarichi con Lock < 2;
		-- C) scarichi precedenti che hanno prelevato da un carico del gruppo B: senza di loro il residuo del carico in 4.0
		--    sarebbe piu' alto di quello della 3.1 (le loro relazioni verso carichi non importati si scartano);
		-- D) scarichi precedenti da cui deriva (relazione -1) un carico K/M importato: il materiale conserva le
		--    registrazioni associate inviate al RENTRI.
		-- Le rettifiche riguardano solo registrazioni trasmesse al RENTRI (dal 13/02/2025): originale e rettifica sono nel
		-- gruppo A; un'eccezione blocca la verifica.
		DECLARE @dataInizio DATE = '20250101';

		INSERT INTO #registrazioni (Id, IdMovimento, IdRegistro, IdCausale, Operazione31, [Data], Numero, Lock, Inviata, Importabile, Gruppo)
		SELECT
			r.IDRegistrazione,
			r.IDMovimento,
			g.Id,
			UPPER(m.IDCausale),
			c.Operazione,
			r.[Data],
			r.Numero,
			r.Lock,
			IIF(r.RentriIdentificativo IS NULL, 0, 1),
			IIF(ISNULL(r.Lock, 0) = 0 AND r.[Data] >= @dataInizio, 1, 0),
			IIF(ISNULL(r.Lock, 0) = 0 AND r.[Data] >= @dataInizio, 'A', NULL)
		FROM
			dbo.syn31RifiutiRegistrazioni r
			INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IDMovimento = m.IDMovimento
			INNER JOIN #registri g ON m.IDRegistro = g.Id COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.syn31RifiutiMovimentiCausali c ON m.IDCausale = c.IDCausale;

		-- B) Carichi precedenti associati agli scarichi del gruppo A o con residuo
		UPDATE x
		SET
			Importabile = 1,
			Gruppo = 'B'
		FROM
			#registrazioni x
			INNER JOIN dbo.syn31RifiutiRegistrazioni r ON x.Id = r.IDRegistrazione COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IDMovimento = m.IDMovimento
		WHERE
			x.Importabile = 0
			AND ISNULL(x.Lock, 0) = 0
			AND x.Operazione31 = 'C'
			AND
				(
				EXISTS (SELECT 1 FROM dbo.syn31RifiutiRegistrazioniRelazioni l INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT WHERE l.IDCarico = r.IDRegistrazione AND l.[Quantità] > 0 AND s.Gruppo = 'A')
				OR
					(
					m.IDCER IS NOT NULL
					AND NOT EXISTS (SELECT 1 FROM dbo.syn31RentriRegistrazioniRettifiche t WHERE t.IDRegistrazione = r.IDRegistrazione)
					AND ISNULL(r.[QuantitàRettifica], r.[Quantità]) - ISNULL((SELECT SUM(l.[Quantità]) FROM dbo.syn31RifiutiRegistrazioniRelazioni l INNER JOIN dbo.syn31RifiutiRegistrazioni rs ON l.IDScarico = rs.IDRegistrazione WHERE l.IDCarico = r.IDRegistrazione AND l.[Quantità] > 0 AND rs.Lock < 2), 0) > 0
					)
				);

		-- C) Scarichi precedenti che hanno prelevato dai carichi del gruppo B
		UPDATE x
		SET
			Importabile = 1,
			Gruppo = 'C'
		FROM #registrazioni x
		WHERE
			x.Importabile = 0
			AND ISNULL(x.Lock, 0) = 0
			AND EXISTS (SELECT 1 FROM dbo.syn31RifiutiRegistrazioniRelazioni l INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT WHERE l.IDScarico = x.Id COLLATE DATABASE_DEFAULT AND l.[Quantità] > 0 AND c.Gruppo = 'B');

		-- D) Scarichi precedenti da cui derivano carichi K/M importati
		UPDATE x
		SET
			Importabile = 1,
			Gruppo = 'D'
		FROM #registrazioni x
		WHERE
			x.Importabile = 0
			AND ISNULL(x.Lock, 0) = 0
			AND EXISTS (SELECT 1 FROM dbo.syn31RifiutiRegistrazioniRelazioni l INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT WHERE l.IDScarico = x.Id COLLATE DATABASE_DEFAULT AND l.[Quantità] = -1 AND c.Importabile = 1);

		-- Autorizzazioni usate dalle registrazioni importabili
		INSERT INTO #autorizzazioni (Id)
		SELECT DISTINCT a.IdAutorizzazione
		FROM
			#registrazioni r
			INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			CROSS APPLY (VALUES
				(m.IDAutorizzazioneProduttore),
				(m.IDAutorizzazioneDestinatario),
				(m.IDAutorizzazioneTrasportatore),
				(m.IDAutorizzazioneTrasportatore2),
				(m.IDAutorizzazioneIntermediario1),
				(m.IDAutorizzazioneIntermediario2)
			) a (IdAutorizzazione)
		WHERE
			r.Importabile = 1
			AND a.IdAutorizzazione IS NOT NULL;

		-- Sedi coinvolte: delle autorizzazioni, luoghi di produzione, registri, e le loro aziende padre
		;WITH base AS (
			SELECT IdSede = a.IDSede COLLATE DATABASE_DEFAULT
			FROM
				#autorizzazioni x
				INNER JOIN dbo.syn31RifiutiAutorizzazioni a ON x.Id = a.IDAutorizzazione COLLATE DATABASE_DEFAULT
			UNION
			SELECT m.IDPosizione COLLATE DATABASE_DEFAULT
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION
			SELECT ms.IDSede COLLATE DATABASE_DEFAULT
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimentiSedi ms ON r.IdMovimento = ms.IDMovimento
			WHERE r.Importabile = 1
			UNION
			SELECT g.IdSede
			FROM #registri g
		),
		albero AS (
			SELECT s.IDSede, s.IDParent
			FROM
				dbo.syn31Sedi s
				INNER JOIN base b ON s.IDSede = b.IdSede COLLATE DATABASE_DEFAULT
			UNION ALL
			SELECT p.IDSede, p.IDParent
			FROM
				dbo.syn31Sedi p
				INNER JOIN albero a ON p.IDSede = a.IDParent
		)
		INSERT INTO #sedi (Id)
		SELECT DISTINCT IDSede
		FROM albero
		OPTION (MAXRECURSION 20);

		-- Radice di ogni sede (azienda interna o soggetto) e se e' interna o esterna: in 4.0 le sedi hanno due livelli,
		-- quindi il padre 4.0 di una sede figlia e' sempre la sua radice
		;WITH risali AS (
			SELECT x.Id, s.IDParent, Radice = s.IDSede
			FROM
				#sedi x
				INNER JOIN dbo.syn31Sedi s ON x.Id = s.IDSede COLLATE DATABASE_DEFAULT
			UNION ALL
			SELECT r.Id, p.IDParent, p.IDSede
			FROM
				risali r
				INNER JOIN dbo.syn31Sedi p ON r.IDParent = p.IDSede
		)
		UPDATE x
		SET
			Radice31 = r.Radice,
			InternaEsterna = s.InternaEsterna
		FROM
			#sedi x
			INNER JOIN risali r ON x.Id = r.Id AND r.IDParent IS NULL
			INNER JOIN dbo.syn31Sedi s ON x.Id = s.IDSede COLLATE DATABASE_DEFAULT
		OPTION (MAXRECURSION 20);

		-- Abbinamento a quelle del dominio 4.0 delle aziende interne del perimetro e delle altre aziende interne usate
		-- nelle registrazioni (es. il produttore di un carico e' un'altra azienda del cliente: si migra senza i suoi
		-- registri). Un'azienda gia' migrata conserva la propria corrispondenza (tblMigrazioniId), le altre si abbinano
		-- solo per codice fiscale o partita IVA
		INSERT INTO #abbinamenti (IdAzienda31, Mappata, Abbinamenti, IdAzienda40)
		SELECT
			s.IDSede,
			IIF(MIN(mi.IdDestinazione) IS NULL, 0, 1),
			IIF(MIN(mi.IdDestinazione) IS NULL, COUNT(x.Id), 1),
			ISNULL(MIN(mi.IdDestinazione), MIN(x.Id))
		FROM
			dbo.syn31Sedi s
			INNER JOIN (
				SELECT IdAzienda
				FROM #registri
				UNION
				SELECT Radice31
				FROM #sedi
				WHERE InternaEsterna = 'I') g ON s.IDSede = g.IdAzienda COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.tblMigrazioniId mi ON mi.Versione = '31'
				AND mi.IdDominioA = @IdDominioA
				AND mi.Tabella = 'tblSedi'
				AND mi.IdOrigine = s.IDSede COLLATE DATABASE_DEFAULT
				LEFT JOIN (
				SELECT ss.Id, ss.CodiceFiscale, ss.PartitaIva
				FROM
					dbo.tblSediInterne si
					INNER JOIN dbo.tblSedi ss ON si.Id = ss.Id
				WHERE
					si.IdDominio = @IdDominioA
					AND ss.Lock < 2
				) x ON (NULLIF(s.CodiceFiscale, '') IS NOT NULL AND x.CodiceFiscale = s.CodiceFiscale COLLATE DATABASE_DEFAULT)
				OR (NULLIF(s.PartitaIva, '') IS NOT NULL AND x.PartitaIva = s.PartitaIva COLLATE DATABASE_DEFAULT)
		GROUP BY s.IDSede;

		-- Soggetti (radici delle sedi esterne usate). Proprietario: l'azienda interna proprietaria nella 3.1, se e' tra
		-- quelle migrate (#abbinamenti); altrimenti (soggetto condiviso di un'azienda non migrata) l'azienda migrata che
		-- lo usa nelle registrazioni. Un soggetto gia' migrato conserva la propria corrispondenza; gli altri si abbinano
		-- per codice fiscale o partita IVA tra i soggetti dell'azienda 4.0 proprietaria (se l'azienda e' da creare non
		-- ha soggetti: il soggetto si crea)
		;WITH usi AS (
			SELECT g.IdAzienda, IdSede = COALESCE(a.IDSede, v.IdSede) COLLATE DATABASE_DEFAULT
			FROM
				#registrazioni r
				INNER JOIN #registri g ON r.IdRegistro = g.Id
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
				CROSS APPLY (VALUES
					(m.IDAutorizzazioneProduttore, NULL),
					(m.IDAutorizzazioneDestinatario, NULL),
					(m.IDAutorizzazioneTrasportatore, NULL),
					(m.IDAutorizzazioneTrasportatore2, NULL),
					(m.IDAutorizzazioneIntermediario1, NULL),
					(m.IDAutorizzazioneIntermediario2, NULL),
					(NULL, m.IDPosizione)
				) v (IdAutorizzazione, IdSede)
				LEFT JOIN dbo.syn31RifiutiAutorizzazioni a ON v.IdAutorizzazione = a.IDAutorizzazione
			WHERE r.Importabile = 1
			UNION ALL
			SELECT g.IdAzienda, ms.IDSede COLLATE DATABASE_DEFAULT
			FROM
				#registrazioni r
				INNER JOIN #registri g ON r.IdRegistro = g.Id
				INNER JOIN dbo.syn31RifiutiMovimentiSedi ms ON r.IdMovimento = ms.IDMovimento
			WHERE r.Importabile = 1),
		uso AS (
			SELECT x.Radice31, IdAzienda = MIN(u.IdAzienda)
			FROM
				usi u
				INNER JOIN #sedi x ON u.IdSede = x.Id
			WHERE x.InternaEsterna = 'E'
			GROUP BY x.Radice31
		)
		INSERT INTO #soggetti (IdSoggetto31, IdProprietario31, ProprietarioCambiato, Mappato, Abbinamenti, IdSoggetto40)
		SELECT
			rd.Radice31,
			p.IdProprietario31,
			p.Cambiato,
			IIF(mi.IdDestinazione IS NULL, 0, 1),
			IIF(mi.IdDestinazione IS NULL, k.Abbinamenti, 1),
			ISNULL(mi.IdDestinazione, k.Id)
		FROM
			(SELECT DISTINCT Radice31
			FROM #sedi
			WHERE InternaEsterna = 'E') rd
			INNER JOIN dbo.syn31Sedi s ON rd.Radice31 = s.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN #abbinamenti pa ON s.IDAziendaInterna = pa.IdAzienda31 COLLATE DATABASE_DEFAULT
			LEFT JOIN uso u ON rd.Radice31 = u.Radice31
			CROSS APPLY (SELECT
				IdProprietario31 = IIF(pa.IdAzienda31 IS NULL, u.IdAzienda, pa.IdAzienda31),
				Cambiato = CONVERT(BIT, IIF(pa.IdAzienda31 IS NULL, 1, 0))) p
			LEFT JOIN #abbinamenti po ON p.IdProprietario31 = po.IdAzienda31
			LEFT JOIN dbo.tblMigrazioniId mi ON mi.Versione = '31'
				AND mi.IdDominioA = @IdDominioA
				AND mi.Tabella = 'tblSedi'
				AND mi.IdOrigine = rd.Radice31
			OUTER APPLY (
				SELECT Abbinamenti = COUNT(e.Id), Id = MIN(e.Id)
				FROM
					dbo.tblSediEsterne se
					INNER JOIN dbo.tblSedi e ON se.Id = e.Id
				WHERE
					se.IdSedeInterna = po.IdAzienda40
					AND e.IdParent IS NULL
					AND e.InternaEsterna = 'E'
					AND e.Lock < 2
					AND
						(
							(
							NULLIF(s.CodiceFiscale, '') IS NOT NULL
							AND e.CodiceFiscale = s.CodiceFiscale COLLATE DATABASE_DEFAULT
							)
						OR
							(
							NULLIF(s.PartitaIva, '') IS NOT NULL
							AND e.PartitaIva = s.PartitaIva COLLATE DATABASE_DEFAULT
							)
						)
			) k;

		-- Anomalie
		-- Aziende interne abbinate a piu' aziende 4.0
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Azienda interna con piu'' abbinamenti nella 4.0 (stesso codice fiscale o partita IVA)', 'tblSedi', b.IdAzienda31, CONCAT(s.Nome, ': ', b.Abbinamenti, ' aziende')
		FROM
			#abbinamenti b
			INNER JOIN dbo.syn31Sedi s ON b.IdAzienda31 = s.IDSede COLLATE DATABASE_DEFAULT
		WHERE b.Abbinamenti > 1;

		-- I limiti del dominio di destinazione (AziendeMax, SediMax, RegistriMax) non si applicano alla migrazione

		-- Soggetti abbinati a piu' soggetti 4.0 dell'azienda proprietaria
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Soggetto con piu'' abbinamenti nella 4.0 (stesso codice fiscale o partita IVA)', 'tblSedi', g.IdSoggetto31, CONCAT(s.Nome, ': ', g.Abbinamenti, ' soggetti')
		FROM
			#soggetti g
			INNER JOIN dbo.syn31Sedi s ON g.IdSoggetto31 = s.IDSede COLLATE DATABASE_DEFAULT
		WHERE g.Abbinamenti > 1;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Soggetto senza azienda proprietaria', 'tblSedi', g.IdSoggetto31, s.Nome
		FROM
			#soggetti g
			INNER JOIN dbo.syn31Sedi s ON g.IdSoggetto31 = s.IDSede COLLATE DATABASE_DEFAULT
		WHERE g.IdProprietario31 IS NULL;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Soggetto di un''azienda non migrata: assegnato all''azienda che lo usa', 'tblSedi', g.IdSoggetto31, CONCAT(s.Nome, ': da ', pv.Nome, ' a ', pn.Nome)
		FROM
			#soggetti g
			INNER JOIN dbo.syn31Sedi s ON g.IdSoggetto31 = s.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.syn31Sedi pv ON s.IDAziendaInterna = pv.IDSede
			LEFT JOIN dbo.syn31Sedi pn ON g.IdProprietario31 = pn.IDSede COLLATE DATABASE_DEFAULT
		WHERE
			g.ProprietarioCambiato = 1
			AND g.IdProprietario31 IS NOT NULL;

		-- Abbinamenti su uno solo dei due codici: codice fiscale o partita IVA della 4.0 diverso da quello della 3.1. Le
		-- registrazioni migrate mostrerebbero l'anagrafica 4.0, diversa da quella trasmessa al RENTRI
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'W',
			'Abbinamento con codice fiscale o partita IVA diversi dalla 3.1',
			'tblSedi',
			k.IdOrigine,
			CONCAT(s.Nome COLLATE DATABASE_DEFAULT, ': 3.1 CF ', ISNULL(s.CodiceFiscale COLLATE DATABASE_DEFAULT, '-'), ' P.IVA ', ISNULL(s.PartitaIva COLLATE DATABASE_DEFAULT, '-'), ', 4.0 ', x.NomeCompleto, ' CF ', ISNULL(x.CodiceFiscale, '-'), ' P.IVA ', ISNULL(x.PartitaIva, '-'))
		FROM
			(
				SELECT IdOrigine = IdAzienda31, IdDestinazione = IdAzienda40
				FROM #abbinamenti
				WHERE
					Mappata = 0
					AND Abbinamenti = 1
				UNION ALL
				SELECT IdSoggetto31, IdSoggetto40
				FROM #soggetti
				WHERE
					Mappato = 0
					AND Abbinamenti = 1
			) k
				INNER JOIN dbo.syn31Sedi s ON k.IdOrigine = s.IDSede COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.tblSedi x ON k.IdDestinazione = x.Id
		WHERE
			(
			NULLIF(s.CodiceFiscale, '') IS NOT NULL
			AND ISNULL(x.CodiceFiscale, '') <> s.CodiceFiscale COLLATE DATABASE_DEFAULT
			)
			OR
				(
				NULLIF(s.PartitaIva, '') IS NOT NULL
				AND ISNULL(x.PartitaIva, '') <> s.PartitaIva COLLATE DATABASE_DEFAULT
				);

		-- La condivisione dei soggetti della 3.1 non si migra: in 4.0 si condivide con le Aree
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'I', 'Soggetto condiviso nella 3.1: in 4.0 condividerlo con le Aree', 'tblSedi', g.IdSoggetto31, s.Nome
		FROM
			#soggetti g
			INNER JOIN dbo.syn31Sedi s ON g.IdSoggetto31 = s.IDSede COLLATE DATABASE_DEFAULT
		WHERE
			ISNULL(s.IsCondivisa, 0) = 1
			OR EXISTS (SELECT 1 FROM dbo.syn31SediEsterne se WHERE se.IDSedeEsterna = s.IDSede AND ISNULL(se.Condivisa, 0) = 1);

		-- Sedi figlie create nuove sotto un'azienda interna o un soggetto abbinati a record 4.0 esistenti: le sedi
		-- non si possono abbinare (hanno lo stesso codice fiscale della radice) e potrebbero esserci gia'
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT DISTINCT 'W', 'Sede creata nuova sotto un''azienda o un soggetto abbinati (verificare duplicati)', 'tblSedi', x.Id, CONCAT(s.Nome, ' (', r.Nome, ')')
		FROM
			#sedi x
			INNER JOIN dbo.syn31Sedi s ON x.Id = s.IDSede COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31Sedi r ON x.Radice31 = r.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN #abbinamenti b ON x.Radice31 = b.IdAzienda31
			LEFT JOIN #soggetti g ON x.Radice31 = g.IdSoggetto31
		WHERE
			x.Id <> x.Radice31
			AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mi WHERE mi.Versione = '31' AND mi.IdDominioA = @IdDominioA AND mi.Tabella = 'tblSedi' AND mi.IdOrigine = x.Id)
			AND
				(
					(
					b.Mappata = 0
					AND b.Abbinamenti = 1
					)
				OR
					(
					g.Mappato = 0
					AND g.Abbinamenti = 1
					)
				OR EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mr WHERE mr.Versione = '31' AND mr.IdDominioA = @IdDominioA AND mr.Tabella = 'tblSedi' AND mr.IdOrigine = x.Radice31 AND mr.Creato = 0)
				);

		-- Ruoli delle registrazioni rispetto all'operazione 4.0 (stesse regole di uspMigrazioni31_ins_Registrazioni): il
		-- produttore mancante si ricava dal luogo di produzione o, se l'operazione lo prevede, dalla sede del registro
		;WITH ruoli AS (
			SELECT
				x.IdCausale,
				v.Ruolo,
				v.Previsto,
				Presente = IIF(v.Valore IS NULL, 0, 1)
			FROM
				#registrazioni x
				INNER JOIN dbo.syn31RifiutiRegistrazioni r ON x.Id = r.IDRegistrazione COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IDMovimento = m.IDMovimento
				INNER JOIN dbo.tblRifiutiCausaliOperazioni31 co ON x.IdCausale = co.IdCausale
				INNER JOIN dbo.tblRifiutiOperazioni o ON co.IdOperazione = o.Id
				CROSS APPLY (VALUES
					('produttore', ISNULL(o.IsProduttore, 0), COALESCE(m.IDPosizione, m.IDAutorizzazioneProduttore, IIF(ISNULL(o.ProduttoreSede, 0) = 1, 'sede del registro', NULL))),
					('trasportatore', ISNULL(o.IsTrasportatore, 0), m.IDAutorizzazioneTrasportatore),
					('secondo trasportatore', ISNULL(o.IsTrasportatore, 0), IIF(m.IDAutorizzazioneTrasportatore2 IS NULL, NULL, 'x')),
					('destinatario', ISNULL(o.IsDestinatario, 0), m.IDAutorizzazioneDestinatario),
					('intermediario', ISNULL(o.IsIntermediario, 0), m.IDAutorizzazioneIntermediario1),
					('secondo intermediario', ISNULL(o.IsIntermediario, 0), IIF(m.IDAutorizzazioneIntermediario2 IS NULL, NULL, 'x'))
				) v (Ruolo, Previsto, Valore)
			WHERE x.Importabile = 1)
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			IIF(Previsto = 1, 'W', 'I'),
			IIF(Previsto = 1, 'Ruolo previsto dall''operazione 4.0 ma assente nella 3.1', 'Ruolo della 3.1 non previsto dall''operazione 4.0 (non migrato)'),
			'tblRifiutiMovimenti',
			IdCausale,
			CONCAT(Ruolo, ': ', COUNT(*), ' registrazioni')
		FROM ruoli
		WHERE
			(
			Previsto = 1
			AND Presente = 0
			AND Ruolo IN ('produttore', 'destinatario')
			)
			OR
				(
				Previsto = 0
				AND Presente = 1
				)
		GROUP BY IdCausale, Ruolo, Previsto;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Trasporto transfrontaliero senza tipo di documento', 'tblRifiutiRegistrazioni', x.Id, CONCAT(x.IdCausale, ' ', x.Numero, '/', YEAR(x.[Data]))
		FROM
			#registrazioni x
			INNER JOIN dbo.syn31RifiutiRegistrazioni r ON x.Id = r.IDRegistrazione COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IDMovimento = m.IDMovimento
		WHERE
			x.Importabile = 1
			AND ISNULL(r.Transfrontaliero, 0) = 1
			AND NULLIF(LTRIM(RTRIM(m.TransfrontalieroTipo)), '') IS NULL;

		-- Derivazioni (quantita' -1): carichi K/M importati coperti solo in parte o per niente dallo scarico di trattamento
		-- (ufnMigrazioni31_get_Derivazioni, la stessa regola di uspMigrazioni31_ins_Relazioni) e unita' di misura diverse
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'W',
			IIF(dv.Prelievo = 0, 'Carico derivato senza quantita'' disponibile nello scarico: prelievo 0', 'Carico derivato coperto solo in parte dallo scarico'),
			'tblRifiutiRegistrazioniRelazioni',
			c.Id,
			CONCAT(c.IdCausale, ' ', c.Numero, '/', YEAR(c.[Data]), ': ', dv.QuantitaCarico, ', prelevati ', dv.Prelievo, ' dallo scarico ', s.IdCausale, ' ', s.Numero, '/', YEAR(s.[Data]), ' (', dv.QuantitaScarico, ')')
		FROM
			dbo.ufnMigrazioni31_get_Derivazioni() dv
			INNER JOIN #registrazioni c ON dv.IdCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON dv.IdScarico = s.Id COLLATE DATABASE_DEFAULT
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND dv.Prelievo < dv.QuantitaCarico;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'W',
			'Derivazione con unita'' di misura diverse (prelievo calcolato senza conversione)',
			'tblRifiutiRegistrazioniRelazioni',
			c.Id,
			CONCAT(c.IdCausale, ' ', c.Numero, '/', YEAR(c.[Data]), ' in ', dv.UnitaMisuraCarico COLLATE DATABASE_DEFAULT, ', scarico ', s.IdCausale, ' ', s.Numero, '/', YEAR(s.[Data]), ' in ', dv.UnitaMisuraScarico COLLATE DATABASE_DEFAULT)
		FROM
			dbo.ufnMigrazioni31_get_Derivazioni() dv
			INNER JOIN #registrazioni c ON dv.IdCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON dv.IdScarico = s.Id COLLATE DATABASE_DEFAULT
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND ISNULL(dv.UnitaMisuraCarico, '') <> ISNULL(dv.UnitaMisuraScarico, '');

		-- Relazioni di registrazioni di rettifica: in 4.0 una rettifica non ha relazioni proprie (R2.7), passano all'originale
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Relazione legata a una rettifica: spostata sull''originale', 'tblRifiutiRegistrazioniRelazioni', l.IDScarico, CONCAT('Carico ', l.IDCarico, ', quantita'' ', l.[Quantità])
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND EXISTS (SELECT 1 FROM dbo.syn31RentriRegistrazioniRettifiche t WHERE t.IDRegistrazione IN (l.IDCarico, l.IDScarico));

		-- Consumi oltre la quantita': un carico prelevato oltre la sua quantita' o uno scarico che preleva oltre la sua
		-- (le derivazioni, quantita' -1, si migrano a parte: vedi uspMigrazioni31_ins_Relazioni)
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Carico prelevato oltre la sua quantita''', 'tblRifiutiRegistrazioniRelazioni', c.Id, CONCAT(c.IdCausale, ' ', c.Numero, '/', YEAR(c.[Data]), ': ', MAX(ISNULL(rc.[QuantitàRettifica], rc.[Quantità])), ' prelevati ', SUM(l.[Quantità]))
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiRegistrazioni rc ON l.IDCarico = rc.IDRegistrazione
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND l.[Quantità] > 0
		GROUP BY c.Id, c.IdCausale, c.Numero, c.[Data]
		HAVING SUM(l.[Quantità]) > MAX(ISNULL(rc.[QuantitàRettifica], rc.[Quantità]));

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Scarico che preleva oltre la sua quantita''', 'tblRifiutiRegistrazioniRelazioni', s.Id, CONCAT(s.IdCausale, ' ', s.Numero, '/', YEAR(s.[Data]), ': ', MAX(rs.[Quantità]), ' prelevati ', SUM(l.[Quantità]))
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31RifiutiRegistrazioni rs ON l.IDScarico = rs.IDRegistrazione
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND l.[Quantità] > 0
		GROUP BY s.Id, s.IdCausale, s.Numero, s.[Data]
		HAVING SUM(l.[Quantità]) > MAX(rs.[Quantità]);

		-- Tipo di registro non migrabile
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Tipo di registro non migrabile', 'tblRifiutiRegistri', g.Id, ISNULL(g.IdTipo, '(vuoto)')
		FROM
			#registri g
			LEFT JOIN dbo.tblMigrazioniCodici k ON k.Versione = '31' AND k.Tabella = 'tblRifiutiRegistriTipi' AND k.CodiceOrigine = g.IdTipo
		WHERE k.CodiceDestinazione IS NULL;

		-- Registrazioni importabili senza data o numero
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Registrazione senza data o numero', 'tblRifiutiRegistrazioni', r.Id, CONCAT('Numero ', r.Numero, ', data ', r.[Data])
		FROM #registrazioni r
		WHERE
			r.Importabile = 1
			AND
				(
				r.[Data] IS NULL
				OR r.Numero IS NULL
				);

		-- Numero duplicato nello stesso registro e anno
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Numero duplicato nel registro e anno', 'tblRifiutiRegistri', r.IdRegistro, CONCAT('Numero ', r.Numero, '/', YEAR(r.[Data]), ': ', COUNT(*), ' registrazioni')
		FROM #registrazioni r
		WHERE r.Importabile = 1
		GROUP BY r.IdRegistro, r.Numero, YEAR(r.[Data])
		HAVING COUNT(*) > 1;

		-- Causale assente o senza operazione 4.0
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Causale senza operazione 4.0', 'tblRifiutiRegistrazioni', r.Id, CONCAT('Causale ', ISNULL(r.IdCausale, '(vuota)'), ', numero ', r.Numero, '/', YEAR(r.[Data]))
		FROM
			#registrazioni r
			LEFT JOIN dbo.tblRifiutiCausaliOperazioni31 o ON r.IdCausale = o.IdCausale
		WHERE
			r.Importabile = 1
			AND o.IdOperazione IS NULL;

		-- Movimento con piu' registrazioni
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'I', 'Movimento con piu'' registrazioni: in 4.0 un movimento per registrazione', 'tblRifiutiMovimenti', CONVERT(VARCHAR(50), r.IdMovimento), CONCAT(COUNT(*), ' registrazioni')
		FROM #registrazioni r
		WHERE r.Importabile = 1
		GROUP BY r.IdMovimento
		HAVING COUNT(*) > 1;

		-- Codici non mappati (movimento e registrazione)
		;WITH usati AS (
			SELECT r.Id, Tabella = 'tblRifiutiStatiFisici', Codice = CONVERT(VARCHAR(20), m.IDStatoFisico)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblUnitaMisura', CONVERT(VARCHAR(20), rr.[IDUnitàMisura])
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiRegistrazioni rr ON r.Id = rr.IDRegistrazione COLLATE DATABASE_DEFAULT
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiAttivitaRecuperoSmaltimento', CONVERT(VARCHAR(20), m.IDDestinazione)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiMateriali', CONVERT(VARCHAR(20), m.IDMaterialeSecondario)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiRaee', CONVERT(VARCHAR(20), m.IDRaee)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiProvenienze', CONVERT(VARCHAR(20), m.Provenienza)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiAttivitaProvenienze', CONVERT(VARCHAR(20), m.IDOrigine)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiTrasportiTransfrontalieriTipi', CONVERT(VARCHAR(20), m.TransfrontalieroTipo)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiMovimentiTrasportiTipi', CONVERT(VARCHAR(20), m.TrasportoTipo)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiMovimentiTrasportiTipi', CONVERT(VARCHAR(20), m.TrasportoTipo2)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			WHERE
				r.Importabile = 1
				AND m.IDAutorizzazioneTrasportatore2 IS NOT NULL
			UNION ALL
			SELECT r.Id, 'tblRifiutiRegistrazioniEsiti', CONVERT(VARCHAR(20), rr.IDEsito)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiRegistrazioni rr ON r.Id = rr.IDRegistrazione COLLATE DATABASE_DEFAULT
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiRegistrazioniEsitiCausaliRespingimento', CONVERT(VARCHAR(20), rr.IDEsitoCausaleRespingimento)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiRegistrazioni rr ON r.Id = rr.IDRegistrazione COLLATE DATABASE_DEFAULT
			WHERE r.Importabile = 1
			UNION ALL
			SELECT r.Id, 'tblRifiutiClassiPericolo', CONVERT(VARCHAR(20), c.IDClasse)
			FROM
				#registrazioni r
				INNER JOIN dbo.syn31RifiutiMovimentiClassiPericolo c ON r.IdMovimento = c.IDMovimento
			WHERE r.Importabile = 1)
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Codice non mappato', u.Tabella, MIN(u.Id), CONCAT('Codice ', u.Codice, ': ', COUNT(*), ' registrazioni')
		FROM
			usati u
			LEFT JOIN dbo.tblMigrazioniCodici k ON k.Versione = '31' AND k.Tabella = u.Tabella AND k.CodiceOrigine = u.Codice COLLATE DATABASE_DEFAULT
		WHERE
			NULLIF(LTRIM(RTRIM(u.Codice)), '') IS NOT NULL
			AND k.CodiceDestinazione IS NULL
		GROUP BY u.Tabella, u.Codice;

		-- EER non presente nella 4.0
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'EER non presente nella 4.0', 'tblRifiutiEer', m.IDCER, CONCAT(COUNT(*), ' registrazioni')
		FROM
			#registrazioni r
			INNER JOIN dbo.syn31RifiutiMovimenti m ON r.IdMovimento = m.IDMovimento
			LEFT JOIN dbo.tblRifiutiEer e ON m.IDCER = e.Id COLLATE DATABASE_DEFAULT
		WHERE
			r.Importabile = 1
			AND m.IDCER IS NOT NULL
			AND e.Id IS NULL
		GROUP BY m.IDCER;

		-- Quantita' con il terzo decimale (in 4.0 sono a due decimali)
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Quantita'' con tre decimali', 'tblRifiutiRegistrazioni', r.Id, CONCAT('Numero ', r.Numero, '/', YEAR(r.[Data]), ': ', rr.[Quantità])
		FROM
			#registrazioni r
			INNER JOIN dbo.syn31RifiutiRegistrazioni rr ON r.Id = rr.IDRegistrazione COLLATE DATABASE_DEFAULT
		WHERE
			r.Importabile = 1
			AND
				(
				rr.[Quantità] <> ROUND(rr.[Quantità], 2)
				OR rr.[QuantitàRettifica] <> ROUND(rr.[QuantitàRettifica], 2)
				OR rr.[RespingimentoQuantità] <> ROUND(rr.[RespingimentoQuantità], 2)
				);

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Quantita'' con tre decimali', 'tblRifiutiRegistrazioniRelazioni', l.IDScarico, CONCAT('Carico ', l.IDCarico, ': ', l.[Quantità])
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni r ON l.IDScarico = r.Id COLLATE DATABASE_DEFAULT
		WHERE
			r.Importabile = 1
			AND l.[Quantità] <> ROUND(l.[Quantità], 2);

		-- Relazioni: verso registrazioni non importate, derivazioni (-1) su causali inattese
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			-- I: registrazione precedente al 2025 non necessaria (scelta del perimetro); W: bozza, cancellata o di un altro registro
			IIF(ISNULL(IIF(ISNULL(c.Importabile, 0) = 0, c.Lock, s.Lock), 0) = 0 AND IIF(ISNULL(c.Importabile, 0) = 0, c.[Data], s.[Data]) < @dataInizio, 'I', 'W'),
			'Relazione con una registrazione non importata (scartata)',
			'tblRifiutiRegistrazioniRelazioni',
			l.IDScarico,
			CONCAT('Carico ', l.IDCarico, IIF(ISNULL(c.Importabile, 0) = 0, ' non importato', ''), IIF(ISNULL(s.Importabile, 0) = 0, ', scarico non importato', ''))
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			LEFT JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			LEFT JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
		WHERE
			(
			c.Id IS NOT NULL
			OR s.Id IS NOT NULL
			)
			AND
				(
				ISNULL(c.Importabile, 0) = 0
				OR ISNULL(s.Importabile, 0) = 0
				)
			AND
				(
				ISNULL(c.Importabile, 0) = 1
				OR ISNULL(s.Importabile, 0) = 1
				);

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'E',
			'Relazione di derivazione (-1) inattesa',
			'tblRifiutiRegistrazioniRelazioni',
			l.IDScarico,
			CONCAT('Carico ', c.IdCausale, ' ', c.Numero, '/', YEAR(c.[Data]), ', scarico ', s.IdCausale, ' ', s.Numero, '/', YEAR(s.[Data]), ', quantita'' ', l.[Quantità])
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND l.[Quantità] < 0
			AND
				(
				c.IdCausale NOT IN ('CMC', 'CRC')
				OR s.IdCausale <> 'SFC'
				OR l.[Quantità] <> -1
				);

		-- Coppia di operazioni ammessa in 4.0 (tblRifiutiOperazioniRelazioni: Id = operazione del padre, IdParent =
		-- operazione associabile come figlio). Padre e figlio della 4.0:
		-- - consumo (quantita' positiva): padre = scarico (S, R), figlio = carico consumato;
		-- - derivazione (quantita' -1): padre = carico K/M prodotto dal trattamento, figlio = scarico R.
		-- Esempio: K non e' mai figlio, quindi il consumo di un CMC da parte di uno scarico viene scartato
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'W',
			'Coppia di operazioni non ammessa in 4.0 (relazione scartata)',
			'tblRifiutiRegistrazioniRelazioni',
			l.IDScarico,
			CONCAT(
				IIF(l.[Quantità] = -1, 'Derivazione', 'Consumo'),
				': carico ', c.IdCausale, ' ', c.Numero, '/', YEAR(c.[Data]), ' (', oc.IdOperazione, ')',
				', scarico ', s.IdCausale, ' ', s.Numero, '/', YEAR(s.[Data]), ' (', os.IdOperazione, ')')
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.tblRifiutiCausaliOperazioni31 oc ON c.IdCausale = oc.IdCausale
			INNER JOIN dbo.tblRifiutiCausaliOperazioni31 os ON s.IdCausale = os.IdCausale
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni x WHERE x.Id = IIF(l.[Quantità] = -1, oc.IdOperazione, os.IdOperazione) AND x.IdParent = IIF(l.[Quantità] = -1, os.IdOperazione, oc.IdOperazione));

		-- Rettifiche: nella 3.1 IDRegistrazione = rettifica (registrazione nuova), IDRettifica = originale; in 4.0 il
		-- verso e' opposto (Id = originale, IdRettifica = rettifica). Una rettifica in bozza o cancellata si perde senza
		-- danno; una rettifica importabile senza il suo originale perderebbe il riferimento al RENTRI
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'I',
			'Rettifica in bozza o cancellata (non importata)',
			'tblRentriRegistrazioniRettifiche',
			t.IDRegistrazione,
			CONCAT('Originale ', o.Numero, '/', YEAR(o.[Data]), ', rettifica con Lock ', ISNULL(x.Lock, 0))
		FROM
			dbo.syn31RentriRegistrazioniRettifiche t
			INNER JOIN #registrazioni o ON t.IDRettifica = o.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni x ON t.IDRegistrazione = x.Id COLLATE DATABASE_DEFAULT
		WHERE
			o.Importabile = 1
			AND x.Importabile = 0
			AND ISNULL(x.Lock, 0) <> 0;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'E',
			'Rettifica importabile con l''originale non importato',
			'tblRentriRegistrazioniRettifiche',
			t.IDRegistrazione,
			CONCAT('Rettifica ', x.Numero, '/', YEAR(x.[Data]), ', originale ', t.IDRettifica)
		FROM
			dbo.syn31RentriRegistrazioniRettifiche t
			INNER JOIN #registrazioni x ON t.IDRegistrazione = x.Id COLLATE DATABASE_DEFAULT
			LEFT JOIN #registrazioni o ON t.IDRettifica = o.Id COLLATE DATABASE_DEFAULT
		WHERE
			x.Importabile = 1
			AND ISNULL(o.Importabile, 0) = 0;

		-- Caso inverso: originale importato con una rettifica confermata che non lo e' (registrazione precedente al 2025
		-- non necessaria): in 4.0 l'originale perderebbe la rettifica e i suoi valori operativi
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'E',
			'Originale importato con una rettifica confermata non importata',
			'tblRentriRegistrazioniRettifiche',
			t.IDRegistrazione,
			CONCAT('Originale ', o.Numero, '/', YEAR(o.[Data]), ', rettifica ', x.Numero, '/', YEAR(x.[Data]))
		FROM
			dbo.syn31RentriRegistrazioniRettifiche t
			INNER JOIN #registrazioni o ON t.IDRettifica = o.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni x ON t.IDRegistrazione = x.Id COLLATE DATABASE_DEFAULT
		WHERE
			o.Importabile = 1
			AND x.Importabile = 0
			AND ISNULL(x.Lock, 0) = 0;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Autorizzazione usata ma non trovata', 'tblRifiutiAutorizzazioni', x.Id, NULL
		FROM
			#autorizzazioni x
			LEFT JOIN dbo.syn31RifiutiAutorizzazioni a ON x.Id = a.IDAutorizzazione COLLATE DATABASE_DEFAULT
		WHERE a.IDAutorizzazione IS NULL;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'I', 'Autorizzazione usata ma cancellata nella 3.1: importata cancellata (Lock 4)', 'tblRifiutiAutorizzazioni', a.IDAutorizzazione, a.Numero
		FROM
			#autorizzazioni x
			INNER JOIN dbo.syn31RifiutiAutorizzazioni a ON x.Id = a.IDAutorizzazione COLLATE DATABASE_DEFAULT
		WHERE ISNULL(a.Lock, 0) <> 0;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'E', 'Codice non mappato', u.Tabella, MIN(u.Id), CONCAT('Codice ', u.Codice, ': ', COUNT(*), ' autorizzazioni')
		FROM
			(
				SELECT Id = a.IDAutorizzazione, Tabella = 'tblRifiutiRuoli', Codice = CONVERT(VARCHAR(20), a.IDCategoria)
				FROM
					#autorizzazioni x
					INNER JOIN dbo.syn31RifiutiAutorizzazioni a ON x.Id = a.IDAutorizzazione COLLATE DATABASE_DEFAULT
				UNION ALL
				SELECT a.IDAutorizzazione, 'tblRifiutiAutorizzazioniTipi', CONVERT(VARCHAR(20), a.IDTipo)
				FROM
					#autorizzazioni x
					INNER JOIN dbo.syn31RifiutiAutorizzazioni a ON x.Id = a.IDAutorizzazione COLLATE DATABASE_DEFAULT
				UNION ALL
				SELECT d.IDAutorizzazione, 'tblRifiutiAttivitaRecuperoSmaltimento', CONVERT(VARCHAR(20), d.IDDestinazione)
				FROM
					#autorizzazioni x
					INNER JOIN dbo.syn31RifiutiAutorizzazioniDestinazioni d ON x.Id = d.IDAutorizzazione COLLATE DATABASE_DEFAULT
			) u
					LEFT JOIN dbo.tblMigrazioniCodici k ON k.Versione = '31' AND k.Tabella = u.Tabella AND k.CodiceOrigine = u.Codice COLLATE DATABASE_DEFAULT
		WHERE
			NULLIF(LTRIM(RTRIM(u.Codice)), '') IS NOT NULL
			AND k.CodiceDestinazione IS NULL
		GROUP BY u.Tabella, u.Codice;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'EER dell''autorizzazione non presente nella 4.0 (scartato)', 'tblRifiutiAutorizzazioniCER', c.IDAutorizzazione, c.IDCER
		FROM
			#autorizzazioni x
			INNER JOIN dbo.syn31RifiutiAutorizzazioniCER c ON x.Id = c.IDAutorizzazione COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblRifiutiEer e ON c.IDCER = e.Id COLLATE DATABASE_DEFAULT
		WHERE e.Id IS NULL;

		-- Conducenti: la 3.1 chiede "Nome e Cognome" in un solo campo; in 4.0 sono separati e obbligatori. Regola: prima
		-- parola = nome, il resto = cognome (cognomi composti interi). Da controllare: una sola parola (va nel cognome,
		-- nome "-") e piu' di due parole (un nome doppio finirebbe in parte nel cognome)
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT
			'W',
			IIF(CHARINDEX(' ', LTRIM(RTRIM(c.Nome))) = 0, 'Conducente con una sola parola: nome "-"', 'Conducente con piu'' di due parole: verificare nome e cognome'),
			'tblRifiutiAutorizzazioniConducenti',
			c.IDAutorizzazione,
			c.Nome
		FROM
			#autorizzazioni x
			INNER JOIN dbo.syn31RifiutiAutorizzazioniConducenti c ON x.Id = c.IDAutorizzazione COLLATE DATABASE_DEFAULT
		WHERE
			CHARINDEX(' ', LTRIM(RTRIM(c.Nome))) = 0
			OR LEN(LTRIM(RTRIM(c.Nome))) - LEN(REPLACE(LTRIM(RTRIM(c.Nome)), ' ', '')) > 1;

		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'W', 'Comune dell''indirizzo non presente nella 4.0', 'tblIndirizzi', s.Id, CONCAT(i.IDComune, ' ', c.Nome, IIF(ms.IDComuneNuovo IS NULL, '', CONCAT(' -> ', ms.IDComuneNuovo, ' (mappatura Sardegna)')))
		FROM
			#sedi s
			INNER JOIN dbo.syn31SediIndirizzi si ON s.Id = si.IDSede COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.syn31Indirizzi i ON si.IDIndirizzo = i.IDIndirizzo
			LEFT JOIN dbo.syn31Comuni c ON i.IDComune = c.IDComune
			LEFT JOIN dbo.syn31MappingComuniSardegna ms ON i.IDComune = ms.IDComune
			LEFT JOIN dbo.tblComuni x ON i.IDComune = x.Id COLLATE DATABASE_DEFAULT
		WHERE
			i.IDComune IS NOT NULL
			AND x.Id IS NULL;

		-- Conteggi del perimetro
		INSERT INTO #anomalie (Livello, Controllo, Tabella, IdOrigine, Dettaglio)
		SELECT 'I', 'Perimetro', 'tblSedi', NULL, CONCAT(COUNT(*), ' sedi (aziende interne, sedi esterne e aziende padre)')
		FROM #sedi
		UNION ALL
		SELECT 'I', 'Perimetro', 'tblRifiutiAutorizzazioni', NULL, CONCAT(COUNT(*), ' autorizzazioni')
		FROM #autorizzazioni
		UNION ALL
		SELECT 'I', 'Perimetro', 'tblRifiutiRegistrazioni', NULL, CONCAT(ISNULL(SUM(IIF(Importabile = 1, 1, 0)), 0), ' registrazioni importabili (A dal 2025: ', ISNULL(SUM(IIF(Gruppo = 'A', 1, 0)), 0), ', B carichi precedenti: ', ISNULL(SUM(IIF(Gruppo = 'B', 1, 0)), 0), ', C scarichi precedenti: ', ISNULL(SUM(IIF(Gruppo = 'C', 1, 0)), 0), ', D trattamenti precedenti: ', ISNULL(SUM(IIF(Gruppo = 'D', 1, 0)), 0), '), ', ISNULL(SUM(IIF(Importabile = 0 AND ISNULL(Lock, 0) = 0, 1, 0)), 0), ' precedenti non necessarie, ', ISNULL(SUM(IIF(ISNULL(Lock, 0) <> 0, 1, 0)), 0), ' bozze o cancellate')
		FROM #registrazioni
		UNION ALL
		SELECT 'I', 'Perimetro', 'tblRifiutiRegistrazioniRelazioni', NULL, CONCAT(COUNT(*), ' relazioni (', ISNULL(SUM(IIF(l.[Quantità] = -1, 1, 0)), 0), ' derivazioni)')
		FROM
			dbo.syn31RifiutiRegistrazioniRelazioni l
			INNER JOIN #registrazioni c ON l.IDCarico = c.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni s ON l.IDScarico = s.Id COLLATE DATABASE_DEFAULT
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1
		UNION ALL
		SELECT 'I', 'Perimetro', 'tblRentriRegistrazioniRettifiche', NULL, CONCAT(COUNT(*), ' rettifiche (', ISNULL(SUM(IIF(t.Annullata = 1, 1, 0)), 0), ' annullamenti)')
		FROM
			dbo.syn31RentriRegistrazioniRettifiche t
			INNER JOIN #registrazioni o ON t.IDRettifica = o.Id COLLATE DATABASE_DEFAULT
			INNER JOIN #registrazioni x ON t.IDRegistrazione = x.Id COLLATE DATABASE_DEFAULT
		WHERE
			o.Importabile = 1
			AND x.Importabile = 1;
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
