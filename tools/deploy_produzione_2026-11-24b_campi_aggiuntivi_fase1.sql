/*
	Deploy produzione 2026-11-24b - Campi aggiuntivi dei tipi + fase 1 di Servizi e Scadenze (bundle unico)

	Contiene TUTTI i commit del repo DB dopo il tag deployed-prod fae0347 fino a 772bf50. Sostituisce
	deploy_produzione_2026-11-24_campi_aggiuntivi.sql: se quello e' gia' stato eseguito, questo si puo' eseguire lo
	stesso (colonne, tabella e posti aggiunti solo se mancano, funzioni e procedure CREATE OR ALTER, script della serie
	rieseguibile). Solo 4_0_ecomatico. Da eseguire da SSMS sul database 4_0_ecomatico (o con sqlcmd -f 65001 -I).

	Prima il DB, poi SUBITO l'app (commit 4.0 4e8f3d9 o successivo).

	Campi aggiuntivi (fae0347..9124aaf):
	1. tblTipiProprieta.Obbligatorio (BIT, default 0) (S3.6).
	2. tblTipiDati: nomi per l'utente dei tipi di campo (S3.3).
	3. Elenco a scelta (S3.7), 20 posti per tipo di campo (S3.3), tblTipiProprieta.Attivo (S3.8), tblTipiProprietaVoci.
	4-7. ufnTipi_get_ProprietaVoci_List, ufnEventi_get_ProprietaValori_List, ufnEventi_get_ProprietaObbligatoriaMancante,
	     ufnEventi_get_TipoProprieta.
	8-14. uspTipi_del, _ins_Proprieta, _get_Proprieta_List, _del_Proprieta, _upd_ProprietaObbligatorio,
	      _upd_ProprietaAttivo, _upd_ProprietaVoci.
	15-17. uspScadenze_upd (anche S5.9: la serie ricorrente non si esegue), uspServizi_upd, uspServiziAssegnati_upd.
	18-19. uspServizi_get_Stampa_Proprieta, uspServiziAssegnati_get_Bacheca_List.
	20-21. uspSYS_del_SedeInternaCascade, uspSYS_del_SedeEsternaCascade.

	Fase 1 di Servizi e Scadenze (dc9f934..772bf50):
	22-23. uspServizi_upd_Eseguiti, uspScadenze_upd_Eseguite (nuove): Azioni > Segna eseguiti (S6.8, S5.10).
	24. uspFatture_get_Fatturato: report Documenti non ancora fatturati (P2.9).
	25. Le serie di scadenze gia' segnate Eseguito tornano Da eseguire (S5.9). Prima dell'UPDATE elenca le serie che
	    cambiano, dopo ne mostra il numero: e' l'unico punto che modifica dati dei clienti.

	In fondo la verifica: funzioni e procedure con data di modifica e QUOTED_IDENTIFIER, colonne, tabella, tipi di campo,
	posti e serie di scadenze ancora eseguite (deve essere 0).
*/

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

-- ===== 1. tipi_proprieta_obbligatorio_colonna - colonna tblTipiProprieta.Obbligatorio (tools/tipi_proprieta_obbligatorio_colonna.sql)
-- Campi aggiuntivi dei tipi (tblTipiProprieta): campo obbligatorio per segnare come eseguito un servizio o una scadenza
-- (S3.6, decisione dell'utente del 2026-11-23). 0 = facoltativo, come tutti i campi prima di questa modifica.
-- Da installare prima delle SP e della funzione che leggono la colonna. Si puo' rilanciare.
-- Eseguito su dev il 2026-11-23. NON ancora eseguito in produzione.

IF COL_LENGTH('dbo.tblTipiProprieta', 'Obbligatorio') IS NULL
	ALTER TABLE dbo.tblTipiProprieta ADD Obbligatorio BIT NOT NULL CONSTRAINT DF_tblTipiProprieta_Obbligatorio DEFAULT (0);
GO

SELECT COL_LENGTH('dbo.tblTipiProprieta', 'Obbligatorio') AS Obbligatorio;
GO

GO

-- ===== 2. tipi_dati_nomi_campi - nomi dei tipi di campo (tools/tipi_dati_nomi_campi.sql)
SET NOCOUNT ON;

-- Tipi di campo dei campi aggiuntivi dei tipi di scadenza e di servizio (tblTipiDati, S3.3): nomi per l'utente al posto
-- dei termini da sviluppatore ("Sì/No (booleano)", "Numerico (intero)", "Testo (stringa)"), decisione dell'utente del
-- 2026-11-23. Cambiano solo i nomi mostrati nella scheda del tipo; Id e controlli restano. Rieseguibile.
-- Eseguito su dev il 2026-11-23. NON ancora eseguito in produzione.

UPDATE d
SET Nome = n.Nome
FROM
	dbo.tblTipiDati d
	INNER JOIN (VALUES
		('B', 'Casella sì/no'),
		('D', 'Data'),
		('I', 'Numero'),
		('S', 'Testo')
	) n (Id, Nome) ON d.Id = n.Id COLLATE Latin1_General_CI_AS
WHERE d.Nome <> n.Nome COLLATE Latin1_General_CI_AS;

SELECT Id, Nome FROM dbo.tblTipiDati ORDER BY Id;
GO
GO

-- ===== 3. tipi_proprieta_elenco_attivo - Elenco a scelta, 20 posti per tipo di campo, colonna Attivo, tblTipiProprietaVoci (tools/tipi_proprieta_elenco_attivo.sql)
-- Campi aggiuntivi dei tipi di scadenza e di servizio (decisioni dell'utente del 2026-11-24):
-- 1. tipo di campo "Elenco a scelta" (tblTipiDati L) e le voci dell'elenco del campo (tblTipiProprietaVoci): sull'evento
--    si salva il testo della voce (S3.7);
-- 2. campo disattivato (tblTipiProprieta.Attivo = 0): sparisce dalle schede dove e' vuoto, dove ha un valore resta in
--    sola lettura, non e' obbligatorio; i valori non si perdono e si puo' riattivare (S3.8);
-- 3. al massimo 20 campi per tipo in qualunque combinazione (S3.3, prima 5 per tipo di campo): 20 posti in tblProprieta
--    per ogni tipo di campo (B00-B19, D00-D19, I00-I19, L00-L19, S00-S19); il totale lo controlla uspTipi_ins_Proprieta.
-- Da installare prima delle SP e delle funzioni che leggono le nuove colonne e la nuova tabella. Si puo' rilanciare.
-- Eseguito su dev il 2026-11-24. NON ancora eseguito in produzione.

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.tblTipiDati WHERE Id = 'L')
	INSERT dbo.tblTipiDati (Id, Nome) VALUES ('L', 'Elenco a scelta');

INSERT dbo.tblProprieta (Id, IdTipoDato)
SELECT n.Id, d.Id
FROM
	(VALUES ('B'), ('D'), ('I'), ('L'), ('S')) d (Id)
	CROSS JOIN (VALUES ('00'), ('01'), ('02'), ('03'), ('04'), ('05'), ('06'), ('07'), ('08'), ('09'),
		('10'), ('11'), ('12'), ('13'), ('14'), ('15'), ('16'), ('17'), ('18'), ('19')) g (Numero)
	CROSS APPLY (SELECT Id = CAST(d.Id + g.Numero AS CHAR(3))) n
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblProprieta p WHERE p.Id = n.Id COLLATE Latin1_General_CI_AS);

IF COL_LENGTH('dbo.tblTipiProprieta', 'Attivo') IS NULL
	ALTER TABLE dbo.tblTipiProprieta ADD Attivo BIT NOT NULL CONSTRAINT DF_tblTipiProprieta_Attivo DEFAULT (1);
GO

IF OBJECT_ID('dbo.tblTipiProprietaVoci', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblTipiProprietaVoci (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdProprieta CHAR(3) COLLATE Latin1_General_CI_AS NOT NULL,
		Pos INT NOT NULL,
		Nome VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		CONSTRAINT PK_tblTipiProprietaVoci PRIMARY KEY CLUSTERED (Id ASC, IdProprieta ASC, Pos ASC),
		CONSTRAINT FK_tblTipiProprietaVoci_tblTipiProprieta FOREIGN KEY (Id, IdProprieta) REFERENCES dbo.tblTipiProprieta (Id, IdProprieta)
	);
	CREATE UNIQUE NONCLUSTERED INDEX UX_tblTipiProprietaVoci_Nome ON dbo.tblTipiProprietaVoci (Id ASC, IdProprieta ASC, Nome ASC);
END
GO

SELECT Id, Nome FROM dbo.tblTipiDati ORDER BY Id;
SELECT IdTipoDato, Posti = COUNT(*) FROM dbo.tblProprieta GROUP BY IdTipoDato ORDER BY IdTipoDato;
SELECT COL_LENGTH('dbo.tblTipiProprieta', 'Attivo') AS Attivo, OBJECT_ID('dbo.tblTipiProprietaVoci', 'U') AS tblTipiProprietaVoci;
GO

GO

-- ===== 4. ufnTipi_get_ProprietaVoci_List (sql/functions/ufnTipi_get_ProprietaVoci_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Voci di un campo "Elenco a scelta" (S3.7) inviate dalla scheda del tipo come JSON ["Voce 1","Voce 2", ...], nell'ordine
-- dell'elenco: spazi tolti, righe vuote ignorate, Pos da 1. Errore valorizzato = voce non ammessa (la SP chiamante
-- restituisce il primo, per Pos): piu' di 50 caratteri, ripetuta (maiuscole e minuscole non contano), piu' di 50 voci.
-- Nessuna riga = nessuna voce (la SP chiamante chiede di indicarne almeno una).
-- Usata da uspTipi_ins_Proprieta, uspTipi_upd_ProprietaVoci
CREATE OR ALTER FUNCTION [dbo].[ufnTipi_get_ProprietaVoci_List]
(
	@Voci NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN (
	WITH cteVoci AS (
		SELECT
			Ordine = CAST(j.[key] AS INT),
			Testo = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(j.[value], CHAR(13), ''), CHAR(10), ''), CHAR(9), ' ')))
		FROM OPENJSON(@Voci) j
		WHERE j.[type] IN (1, 2)
	),
	cteNumerate AS (
		SELECT
			Pos = ROW_NUMBER() OVER (ORDER BY Ordine),
			Testo,
			Ripetuta = COUNT(*) OVER (PARTITION BY Testo COLLATE Latin1_General_CI_AS),
			PrimaRipetuta = ROW_NUMBER() OVER (PARTITION BY Testo COLLATE Latin1_General_CI_AS ORDER BY Ordine),
			Totale = COUNT(*) OVER ()
		FROM cteVoci
		WHERE Testo <> ''
	)
	SELECT
		Pos,
		Nome = CAST(LEFT(Testo, 50) AS VARCHAR(50)),
		Errore = CASE
			WHEN Totale > 50 THEN 'L''elenco può avere al massimo 50 voci'
			WHEN LEN(Testo) > 50 THEN 'La voce "' + LEFT(Testo, 30) + '..." supera i 50 caratteri'
			WHEN Ripetuta > 1 AND PrimaRipetuta > 1 THEN 'La voce "' + Testo + '" è ripetuta'
		END
	FROM cteNumerate
);
GO

GO

-- ===== 5. ufnEventi_get_ProprietaValori_List (sql/functions/ufnEventi_get_ProprietaValori_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Valori delle proprietà di un evento inviati dalla scheda (JSON [{"Id":"I00","Valore":"12"}, ...]), controllati e
-- normalizzati per tipo di dato. Restituisce solo le proprietà attive del tipo @IdTipo presenti nel JSON (le altre sono
-- ignorate: un campo disattivato non cambia, S3.8). Valore NULL = da togliere; Errore valorizzato = valore non ammesso
-- (la SP chiamante lo restituisce).
-- Formati salvati: Sì/No 'true'/'false', Numero con il punto e al massimo 4 decimali (dal 2026-11-23, prima solo intero;
-- dalla scheda arriva con la virgola), Data 'yyyy-MM-dd', Testo fino a 50 caratteri, Elenco a scelta (S3.7) il testo di
-- una voce dell'elenco del campo, oppure il valore gia' salvato sull'evento @IdEvento (voce poi tolta o rinominata).
-- Usata da uspScadenze_upd, uspServizi_upd, uspServiziAssegnati_upd, ufnEventi_get_ProprietaObbligatoriaMancante
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_ProprietaValori_List]
(
	@IdEvento CHAR(16),
	@IdTipo CHAR(16),
	@Proprieta NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN (
	SELECT
		t.IdProprieta,
		t.Pos,
		v.Valore,
		Errore = IIF(j.Valore IS NOT NULL AND v.Valore IS NULL,
						'Il campo "' + t.Nome + '" ' + CASE p.IdTipoDato
							WHEN 'B' THEN 'deve essere Sì o No'
							WHEN 'I' THEN 'deve essere un numero, con al massimo 4 decimali'
							WHEN 'D' THEN 'deve essere una data'
							WHEN 'L' THEN 'deve essere una delle voci dell''elenco'
							ELSE 'non può superare i 50 caratteri'
						END,
						NULL)
	FROM
		dbo.tblTipiProprieta t
		INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
		CROSS APPLY (
			SELECT TOP 1 Valore = NULLIF(LTRIM(RTRIM(x.Valore)), '')
			FROM OPENJSON(@Proprieta) WITH (Id CHAR(3) '$.Id', Valore NVARCHAR(4000) '$.Valore') x
			WHERE x.Id = t.IdProprieta
		) j
		-- Numero: con la virgola i punti sono migliaia (1.234,5), senza virgola il punto e' il decimale (12.5)
		CROSS APPLY (
			SELECT Numero = TRY_CONVERT(DECIMAL(28, 10), IIF(CHARINDEX(',', j.Valore) > 0, REPLACE(REPLACE(j.Valore, '.', ''), ',', '.'), j.Valore))
		) n
		-- Elenco a scelta: la voce con il testo dell'elenco, altrimenti il valore gia' salvato uguale a quello inviato
		OUTER APPLY (
			SELECT Voce = COALESCE(
				(
				SELECT TOP 1 o.Nome
				FROM dbo.tblTipiProprietaVoci o
				WHERE
					o.Id = t.Id
					AND o.IdProprieta = t.IdProprieta
					AND o.Nome = j.Valore
				),
				(
				SELECT TOP 1 e.Valore
				FROM dbo.tblEventiProprieta e
				WHERE
					e.Id = @IdEvento
					AND e.IdProprieta = t.IdProprieta
					AND e.Valore = j.Valore
				))
			WHERE p.IdTipoDato = 'L'
		) l
		CROSS APPLY (
			SELECT Valore = CASE p.IdTipoDato
				WHEN 'B' THEN IIF(LOWER(j.Valore) IN ('true', 'false'), CAST(LOWER(j.Valore) AS VARCHAR(50)), NULL)
				WHEN 'I' THEN IIF(n.Numero IS NOT NULL AND n.Numero = ROUND(n.Numero, 4), FORMAT(CAST(n.Numero AS DECIMAL(18, 4)), '0.####', 'en-US'), NULL)
				WHEN 'D' THEN CONVERT(VARCHAR(50), TRY_CONVERT(DATE, j.Valore, 23), 23)
				WHEN 'L' THEN l.Voce
				ELSE IIF(LEN(j.Valore) <= 50, CAST(j.Valore AS VARCHAR(50)), NULL)
			END
		) v
	WHERE
		t.Id = @IdTipo
		AND t.Attivo = 1
);
GO

GO

-- ===== 6. ufnEventi_get_ProprietaObbligatoriaMancante (sql/functions/ufnEventi_get_ProprietaObbligatoriaMancante.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Primo campo obbligatorio del tipo non compilato (S3.6), per segnare come eseguito un servizio o una scadenza: le SP
-- _upd lo chiamano solo con lo stato Eseguito e restituiscono il messaggio. Il valore e' quello inviato dalla scheda
-- (@Proprieta, JSON [{"Id","Valore"}], normalizzato da ufnEventi_get_ProprietaValori_List) se il campo c'e', altrimenti
-- quello gia' salvato sull'evento. Una casella si/no obbligatoria deve essere spuntata ('true'). Un campo disattivato (S3.8) non
-- e' obbligatorio. Messaggio come gli altri campi obbligatori delle schede (dal 2026-11-24, decisione dell'utente; prima
-- 'Per segnare come eseguito compilare il campo "Nome"'): Indicare Nome, Selezionare Nome per l'Elenco a scelta,
-- Spuntare Nome per la casella si/no, con il nome del campo senza virgolette.
-- Usata da uspScadenze_upd, uspServizi_upd, uspServiziAssegnati_upd
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_ProprietaObbligatoriaMancante]
(
	@IdEvento CHAR(16),
	@IdTipo CHAR(16),
	@Proprieta NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN (
	SELECT TOP (1)
		Messaggio = CASE p.IdTipoDato
			WHEN 'B' THEN 'Spuntare'
			WHEN 'L' THEN 'Selezionare'
			ELSE 'Indicare'
		END + ' ' + t.Nome
	FROM
		dbo.tblTipiProprieta t
		INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
		OUTER APPLY (
			SELECT TOP (1) v.IdProprieta, v.Valore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @IdTipo, @Proprieta) v
			WHERE v.IdProprieta = t.IdProprieta
		) j
		LEFT JOIN dbo.tblEventiProprieta e ON e.Id = @IdEvento AND e.IdProprieta = t.IdProprieta
		CROSS APPLY (
			SELECT Valore = IIF(j.IdProprieta IS NOT NULL, j.Valore, NULLIF(LTRIM(RTRIM(e.Valore)), ''))
		) x
	WHERE
		t.Id = @IdTipo
		AND t.Lock = 0
		AND t.Attivo = 1
		AND t.Obbligatorio = 1
		AND
			(
			x.Valore IS NULL
			OR (p.IdTipoDato = 'B' AND x.Valore <> 'true')
			)
	ORDER BY t.Pos
);
GO

GO

-- ===== 7. ufnEventi_get_TipoProprieta (sql/functions/ufnEventi_get_TipoProprieta.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Campi aggiuntivi del tipo con i valori dell'evento @Id, come JSON per la scheda della scadenza, del servizio e del
-- servizio assegnato (_TipoProprietaPartial). Un campo disattivato (S3.8) c'e' solo se ha un valore (una casella si/no
-- solo se spuntata) e la scheda lo mostra in sola lettura. Per l'Elenco a scelta (S3.7) Voci sono le voci dell'elenco,
-- una per riga, nell'ordine.
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_TipoProprieta]
(
	@Id CHAR(16),
	@IdTipo CHAR(16)
)
RETURNS NVARCHAR(MAX)
WITH SCHEMABINDING
AS
BEGIN
	RETURN (
		SELECT
			Id = t.IdProprieta,
			p.IdTipoDato,
			Nome = t.Nome,
			-- Campo obbligatorio per segnare come eseguito (S3.6): la scheda mette l'asterisco
			t.Obbligatorio,
			t.Attivo,
			-- Numero salvato con il punto, nella scheda con la virgola
			Valore = CASE p.IdTipoDato
				WHEN 'B' THEN ISNULL(e.Valore, 'false')
				WHEN 'I' THEN REPLACE(ISNULL(e.Valore, ''), '.', ',')
				ELSE ISNULL(e.Valore, '')
			END,
			Voci = (
				SELECT STRING_AGG(CAST(o.Nome AS NVARCHAR(MAX)), NCHAR(10)) WITHIN GROUP (ORDER BY o.Pos)
				FROM dbo.tblTipiProprietaVoci o
				WHERE
					o.Id = t.Id
					AND o.IdProprieta = t.IdProprieta
					AND p.IdTipoDato = 'L'
			)
		FROM
			dbo.tblTipiProprieta t
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta e ON t.IdProprieta = e.IdProprieta
											   AND e.Id = @Id
		WHERE
			t.Id = @IdTipo
			AND t.Lock = 0
			AND
				(
				t.Attivo = 1
				OR (NULLIF(LTRIM(RTRIM(e.Valore)), '') IS NOT NULL AND NOT (p.IdTipoDato = 'B' AND e.Valore <> 'true'))
				)
		ORDER BY
			t.Pos
		FOR JSON PATH
	);
END;
GO

GO

-- ===== 8. uspTipi_del (sql/procedures/uspTipi_del.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspTipi_del]
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

		-- Controllo permesso sulla funzione (TPO = Gestione Tipi)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il tipo esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblTipi
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblTipi
		WHERE Id = @Id);

		-- ── CASO 1: tipo attivo (Lock = 0) → soft delete ─────────────────
		IF @lock = 0
		BEGIN
			-- Verifica dipendenze PRIMA della transazione (sono letture)
			IF EXISTS (SELECT 1
			FROM dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un tipo che ha campi aggiuntivi non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenze s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdTipo = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un tipo che ha scadenze associate non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdTipo = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un tipo che ha servizi associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblTipi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			-- Log FUORI dalla transazione
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: tipo in bozza (Lock = 2) → hard delete ───────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblTipi
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

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



GO

-- ===== 9. uspTipi_ins_Proprieta (sql/procedures/uspTipi_ins_Proprieta.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspTipi_ins_Proprieta]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipoDato CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Obbligatorio BIT = 0,
	-- Voci dell'Elenco a scelta (S3.7), JSON ["Voce 1","Voce 2", ...]: obbligatorie per il tipo di campo L, ignorate per gli altri
	@Voci NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipoDato = NULLIF(LTRIM(RTRIM(@IdTipoDato)), '');
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
		IF @IdTipoDato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdTipoDato non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		-- Voci dell'Elenco a scelta (S3.7): almeno una, controllate da ufnTipi_get_ProprietaVoci_List
		IF @IdTipoDato = 'L'
		BEGIN
			IF ISJSON(@Voci) = 0
				SET @Voci = NULL;

			IF NOT EXISTS (SELECT 1 FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare le voci dell''elenco, una per riga';
				GOTO BRANCH_END;
			END

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Al massimo 20 campi per tipo, in qualunque combinazione di tipi di campo, contando anche i disattivati (dal
		-- 2026-11-24, decisione dell'utente; prima 5 per tipo di campo). Ogni tipo di campo ha 20 posti in tblProprieta
		IF 20 <= (SELECT COUNT(*) FROM dbo.tblTipiProprieta WHERE Id = @Id AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sono già presenti 20 campi, il massimo consentito';
			GOTO BRANCH_END;
		END
		-- Trova la prima proprietà disponibile del tipo dato non ancora usata
		DECLARE @idProprieta CHAR(3);
		SELECT TOP 1 @idProprieta = Id
		FROM dbo.tblProprieta
		WHERE
			IdTipoDato = @IdTipoDato
			AND Id NOT IN ( SELECT IdProprieta FROM dbo.tblTipiProprieta WHERE Id = @Id AND Lock = 0 )
		ORDER BY Id;
		IF @idProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sono già presenti 20 campi, il massimo consentito';
			GOTO BRANCH_END;
		END
		IF EXISTS (
			SELECT 1
			FROM dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND IdProprieta <> @idProprieta
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro campo con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END
		-- Posizione = max corrente + 1, oppure 0 se prima proprietà
		DECLARE @pos INT = (
			SELECT MAX(Pos)
			FROM dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND Lock = 0
		);
		BEGIN TRANSACTION;
			INSERT INTO dbo.tblTipiProprieta (Id, IdProprieta, Nome, Pos, Lock, Obbligatorio)
			VALUES (@Id, @idProprieta, @Nome, ISNULL(@pos + 1, 0), 0, ISNULL(@Obbligatorio, 0));

			IF @IdTipoDato = 'L'
				INSERT INTO dbo.tblTipiProprietaVoci (Id, IdProprieta, Pos, Nome)
				SELECT @Id, @idProprieta, Pos, Nome
				FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci);
		COMMIT TRANSACTION;
		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';
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

GO

-- ===== 10. uspTipi_get_Proprieta_List (sql/procedures/uspTipi_get_Proprieta_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspTipi_get_Proprieta_List]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		SELECT TOP 50
			p.Id,
			t.Nome,
			p.IdTipoDato,
			TipoDato = d.Nome,
			t.Pos,
			t.Obbligatorio,
			-- Campo disattivato (S3.8): l'elenco lo mostra in grigio
			t.Attivo,
			-- Voci dell'Elenco a scelta (S3.7), una per riga, nell'ordine
			Voci = (
				SELECT STRING_AGG(CAST(o.Nome AS VARCHAR(MAX)), CHAR(10)) WITHIN GROUP (ORDER BY o.Pos)
				FROM dbo.tblTipiProprietaVoci o
				WHERE
					o.Id = t.Id
					AND o.IdProprieta = t.IdProprieta
			)
		FROM
			dbo.tblTipiProprieta t
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			INNER JOIN dbo.tblTipiDati d ON p.IdTipoDato = d.Id
		WHERE
			t.Id = @Id
			AND t.Lock = 0
			AND
				(
				@Search IS NULL
				OR t.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY
			t.Pos;
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

GO

-- ===== 11. uspTipi_del_Proprieta (sql/procedures/uspTipi_del_Proprieta.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspTipi_del_Proprieta]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');

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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (TPO = Gestione Tipi)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Rimuove la proprietà dagli eventi scadenza del tipo
			DELETE e
			FROM dbo.tblScadenze s
			INNER JOIN dbo.tblEventiProprieta e ON s.IdEvento = e.Id
			WHERE
				s.IdTipo = @Id
				AND e.IdProprieta = @IdProprieta;
			-- Rimuove la proprietà dagli eventi servizio del tipo
			DELETE e
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventiProprieta e ON s.IdEvento = e.Id
			WHERE
				s.IdTipo = @Id
				AND e.IdProprieta = @IdProprieta;
			-- Voci dell'Elenco a scelta (S3.7)
			DELETE dbo.tblTipiProprietaVoci
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta;
			-- Rimuove la proprietà dal tipo
			DELETE dbo.tblTipiProprieta
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta;
			-- Ricompatta le posizioni rimanenti
			UPDATE r
			SET Pos = t.Pos
			FROM dbo.tblTipiProprieta r
			INNER JOIN (
					   SELECT
						   IdProprieta,
						   Pos = ROW_NUMBER() OVER (ORDER BY Pos)
					   FROM dbo.tblTipiProprieta
					   WHERE Id = @Id) t ON r.IdProprieta = t.IdProprieta
			WHERE r.Id = @Id;
		COMMIT TRANSACTION;
		-- Log FUORI dalla transazione: uspId_upd gestisce la propria transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';
		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END
END;

GO

-- ===== 12. uspTipi_upd_ProprietaObbligatorio (sql/procedures/uspTipi_upd_ProprietaObbligatorio.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspTipi_upd_ProprietaObbligatorio]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL,
	@Obbligatorio BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');
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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Obbligatorio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Obbligatorio non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		-- Campo obbligatorio per segnare come eseguito un servizio o una scadenza del tipo (S3.6)
		UPDATE dbo.tblTipiProprieta
		SET Obbligatorio = @Obbligatorio
		WHERE
			Id = @Id
			AND IdProprieta = @IdProprieta
			AND Lock = 0;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Campo non trovato: aggiornare la pagina';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

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
GO
GO

-- ===== 13. uspTipi_upd_ProprietaAttivo (sql/procedures/uspTipi_upd_ProprietaAttivo.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Attiva o disattiva un campo aggiuntivo del tipo (S3.8, decisione dell'utente del 2026-11-24). Un campo disattivato
-- sparisce dalle schede dove e' vuoto, dove ha un valore resta in sola lettura, non e' obbligatorio per segnare come
-- eseguito; i valori gia' inseriti restano e tornano modificabili riattivandolo
CREATE OR ALTER PROCEDURE [dbo].[uspTipi_upd_ProprietaAttivo]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL,
	@Attivo BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');
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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Attivo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Attivo non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblTipiProprieta
		SET Attivo = @Attivo
		WHERE
			Id = @Id
			AND IdProprieta = @IdProprieta
			AND Lock = 0;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Campo non trovato: aggiornare la pagina';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

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
GO

GO

-- ===== 14. uspTipi_upd_ProprietaVoci (sql/procedures/uspTipi_upd_ProprietaVoci.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Voci di un campo "Elenco a scelta" del tipo (S3.7, decisione dell'utente del 2026-11-24): sostituisce l'elenco con
-- quello inviato dalla scheda del tipo (JSON ["Voce 1","Voce 2", ...], nell'ordine). Sugli eventi e' salvato il testo
-- della voce: togliere o rinominare una voce non cambia le schede gia' compilate, che tengono il testo precedente
CREATE OR ALTER PROCEDURE [dbo].[uspTipi_upd_ProprietaVoci]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL,
	@Voci NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');
		IF ISJSON(@Voci) = 0
			SET @Voci = NULL;
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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblTipiProprieta t
				INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			WHERE
				t.Id = @Id
				AND t.IdProprieta = @IdProprieta
				AND t.Lock = 0
				AND p.IdTipoDato = 'L')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Campo non trovato: aggiornare la pagina';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare le voci dell''elenco, una per riga';
			GOTO BRANCH_END;
		END

		SELECT TOP 1 @returnMessage = Errore
		FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci)
		WHERE Errore IS NOT NULL
		ORDER BY Pos;

		IF @returnMessage IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblTipiProprietaVoci
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta;

			INSERT INTO dbo.tblTipiProprietaVoci (Id, IdProprieta, Pos, Nome)
			SELECT @Id, @IdProprieta, Pos, Nome
			FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci);
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

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
GO

GO

-- ===== 15. uspScadenze_upd (sql/procedures/uspScadenze_upd.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

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
	@OccorrenzaESuccessive BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
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
	DECLARE @idTipo CHAR(16);

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

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblScadenze
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Campi obbligatori del tipo (S3.6): per segnare come eseguito la scadenza vanno compilati (le caselle si/no spuntate),
		-- con i valori inviati dalla scheda o quelli gia' salvati
		IF @IdStato = 'E'
		BEGIN
			IF @idTipo IS NULL
				SELECT @idTipo = IdTipo
				FROM dbo.tblScadenze
				WHERE Id = @Id;

			SELECT @returnMessage = Messaggio
			FROM dbo.ufnEventi_get_ProprietaObbligatoriaMancante(@IdEvento, @idTipo, @Proprieta);

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- La serie è solo pianificazione, come nei servizi (S5.9, dal 2026-11-24): le occorrenze generate hanno lo stato
		-- della serie, quindi una serie Eseguita renderebbe eseguite anche quelle future. Si esegue l'occorrenza
		-- modificata, che è una scadenza a sé (sostituto di un'eccezione della serie)
		IF @IdStato = 'E'
		   AND (@Ricorre = 1 OR @OccorrenzaESuccessive = 1)
		   AND NOT EXISTS (SELECT 1
		FROM dbo.tblRicorrenzeEccezioni
		WHERE IdEvento = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una scadenza ricorrente non può essere eseguita: per segnare come eseguita un''occorrenza, modificare la sola occorrenza';
			GOTO BRANCH_END;
		END

		-- Limiti della serie: le date ammesse dall'applicazione (ufnDate_get_Min / _Max = Constants.SQL.MinDate / MaxDate)
		IF @Ricorre = 1 AND @Data < dbo.ufnDate_get_Min()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data minima per le scadenze ricorrenti è il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy');
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
			SET @frequenzaMax = DATEDIFF(YEAR, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' anni';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @IdIntervallo = 'MM'
		BEGIN
			SET @frequenzaMax = DATEDIFF(MONTH, @Data, dbo.ufnDate_get_Max()) - 1;
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

				-- La serie originale finisce il giorno prima dell'occorrenza scelta (la data della nuova serie
				-- prima del salvataggio, scritta da uspScadenze_ins), anche se la nuova serie viene spostata
				SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				SET @dataFineParent =
					DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
						DATEADD(DAY, DATEDIFF(DAY, 0, DATEADD(MINUTE, -ISNULL(@minuti, 0), @Data)), -1)));

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

				-- Le occorrenze cancellate o modificate della serie originale dalla data scelta in poi passano alla
				-- nuova serie, spostate come la nuova serie (stessa regola della modifica di tutta la serie):
				-- cancellate, una cancellata ricomparirebbe e una modificata sarebbe doppia. Se cambia la frequenza
				-- le date non coincidono piu': passano solo le occorrenze modificate (eventi a se', S5.4)
				INSERT dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				SELECT @IdEvento, DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data]), z.IdEvento, z.Lock
				FROM
					dbo.tblRicorrenzeEccezioni z
					INNER JOIN dbo.tblRicorrenze p ON z.Id = p.Id
				WHERE
					z.Id = @idEventoParent
					AND z.[Data] > @dataFineParent
					AND
						(
						z.IdEvento IS NOT NULL
						OR
							(
							p.IdIntervallo = @IdIntervallo
							AND p.Frequenza = @Frequenza
							AND p.Relativo = @Relativo
							)
						)
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenzeEccezioni y
						WHERE
							y.Id = @IdEvento
							AND y.[Data] = DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data])
					);

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @idEventoParent
					AND [Data] > @dataFineParent;
			END

			-- Sblocca l'eccezione di ricorrenza che referenzia questo evento come sostituto
			-- (occorrenza singola modificata): senza questo sblocco l'occorrenza originale
			-- resta visibile in calendario insieme a quella modificata. No-op se @IdEvento
			-- non e' il sostituto di nessuna eccezione.
			UPDATE dbo.tblRicorrenzeEccezioni
			SET Lock = 0
			WHERE
				IdEvento = @IdEvento
				AND Lock <= 2;

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

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

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
GO

GO

-- ===== 16. uspServizi_upd (sql/procedures/uspServizi_upd.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@DataRichiesta SMALLDATETIME = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@FirmaRichiedente IMAGE = NULL,
	@FirmaEsecutore IMAGE = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Durata INT = NULL,
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
	@OccorrenzaESuccessive BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;
		DECLARE @frequenzaMax INT = 0;
		DECLARE @minuti INT;
		DECLARE @idEventoParent CHAR(16);
		DECLARE @dataFineParent SMALLDATETIME;
		DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
		DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;
		DECLARE @idTipo CHAR(16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdRichiedente = NULLIF(LTRIM(RTRIM(@IdRichiedente)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @Email = dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1);

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
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
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

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblServizi
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Campi obbligatori del tipo (S3.6): per segnare come eseguito il servizio vanno compilati (le caselle si/no spuntate),
		-- con i valori inviati dalla scheda o quelli gia' salvati
		IF @IdStato = 'E'
		BEGIN
			IF @idTipo IS NULL
				SELECT @idTipo = IdTipo
				FROM dbo.tblServizi
				WHERE Id = @Id;

			SELECT @returnMessage = Messaggio
			FROM dbo.ufnEventi_get_ProprietaObbligatoriaMancante(@IdEvento, @idTipo, @Proprieta);

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Durata in minuti, facoltativa (NULL = non indicata): il servizio termina entro la mezzanotte del giorno di
		-- inizio, cosi' non occupa il giorno successivo (vale anche per le occorrenze della serie, alla stessa ora).
		-- "In giornata" non ha un'ora precisa: la durata arriva a 24 ore, qualunque sia l'ora rimasta nella data
		IF @Durata IS NOT NULL AND @Durata <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La durata del servizio deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @Durata IS NOT NULL
		   AND DATEADD(MINUTE, @Durata, IIF(ISNULL(@InGiornata, 0) = 1, CAST(CAST(@Data AS DATE) AS DATETIME), CAST(@Data AS DATETIME)))
			   > DATEADD(DAY, 1, CAST(CAST(@Data AS DATE) AS DATETIME))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: ridurre la durata o anticipare l''ora';
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND EXISTS (SELECT 1
		FROM dbo.tblEventiUtenti
		WHERE Id = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio assegnato non può essere ricorrente';
			GOTO BRANCH_END;
		END

		-- Limiti della serie: le date ammesse dall'applicazione (ufnDate_get_Min / _Max = Constants.SQL.MinDate / MaxDate)
		IF @Ricorre = 1 AND @Data < dbo.ufnDate_get_Min()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data minima per i servizi ricorrenti è il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND @DataFine IS NOT NULL AND @DataFine < @Data
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine della serie non può essere inferiore alla data di inizio';
			GOTO BRANCH_END;
		END

		-- La serie è solo pianificazione: si esegue (e si fattura) l'occorrenza modificata, che è un
		-- servizio a sé. Serie = ricorrenza propria (casella Ricorre o "Questa e le successive"), mai
		-- l'occorrenza modificata, che è il sostituto di un'eccezione della serie
		IF @IdStato = 'E'
		   AND (@Ricorre = 1 OR @OccorrenzaESuccessive = 1)
		   AND NOT EXISTS (SELECT 1
		FROM dbo.tblRicorrenzeEccezioni
		WHERE IdEvento = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio ricorrente non può essere eseguito: per segnare come eseguita un''occorrenza, modificare la sola occorrenza';
			GOTO BRANCH_END;
		END

		IF @IdIntervallo = 'YY'
		BEGIN
			SET @frequenzaMax = DATEDIFF(YEAR, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' anni';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @IdIntervallo = 'MM'
		BEGIN
			SET @frequenzaMax = DATEDIFF(MONTH, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' mesi';
				GOTO BRANCH_END;
			END
		END

		IF @FirmaRichiedente IS NOT NULL
			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

		IF @FirmaEsecutore IS NOT NULL
			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

		BEGIN TRANSACTION;

			-- Gestione ricorrenze
			IF EXISTS (SELECT 1
			FROM dbo.tblRicorrenze
			WHERE Id = @IdEvento)
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
						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @IdEvento
							AND IdEvento IS NULL;

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

				-- La serie originale finisce il giorno prima dell'occorrenza scelta (la data della nuova serie
				-- prima del salvataggio, scritta da uspServizi_ins), anche se la nuova serie viene spostata
				SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				SET @dataFineParent =
					DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
						DATEADD(DAY, DATEDIFF(DAY, 0, DATEADD(MINUTE, -ISNULL(@minuti, 0), @Data)), -1)));

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

				-- Le occorrenze cancellate o modificate della serie originale dalla data scelta in poi passano alla
				-- nuova serie, spostate come la nuova serie (stessa regola della modifica di tutta la serie):
				-- cancellate, una cancellata ricomparirebbe e una modificata sarebbe doppia. Se cambia la frequenza
				-- le date non coincidono piu': passano solo le occorrenze modificate (eventi a se', S5.4)
				INSERT dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				SELECT @IdEvento, DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data]), z.IdEvento, z.Lock
				FROM
					dbo.tblRicorrenzeEccezioni z
					INNER JOIN dbo.tblRicorrenze p ON z.Id = p.Id
				WHERE
					z.Id = @idEventoParent
					AND z.[Data] > @dataFineParent
					AND
						(
						z.IdEvento IS NOT NULL
						OR
							(
							p.IdIntervallo = @IdIntervallo
							AND p.Frequenza = @Frequenza
							AND p.Relativo = @Relativo
							)
						)
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenzeEccezioni y
						WHERE
							y.Id = @IdEvento
							AND y.[Data] = DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data])
					);

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @idEventoParent
					AND [Data] > @dataFineParent;
			END

			-- Sblocca l'eccezione di ricorrenza che referenzia questo evento come sostituto
			-- (occorrenza singola modificata): senza questo sblocco l'occorrenza originale
			-- resta visibile in calendario insieme a quella modificata. No-op se @IdEvento
			-- non e' il sostituto di nessuna eccezione.
			UPDATE dbo.tblRicorrenzeEccezioni
			SET Lock = 0
			WHERE
				IdEvento = @IdEvento
				AND Lock <= 2;

			-- Gestione firma richiedente
			IF @FirmaRichiedente IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'R';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaRichiedente;
			END
			ELSE IF @idFirmaRichiedente IS NULL
			BEGIN
				SET @idFirmaRichiedente = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaRichiedente, @FirmaRichiedente);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaRichiedente, 'R');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaRichiedente
				WHERE Id = @idFirmaRichiedente;

			-- Gestione firma esecutore
			IF @FirmaEsecutore IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'E';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaEsecutore;
			END
			ELSE IF @idFirmaEsecutore IS NULL
			BEGIN
				SET @idFirmaEsecutore = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaEsecutore, @FirmaEsecutore);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaEsecutore, 'E');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaEsecutore
				WHERE Id = @idFirmaEsecutore;

			UPDATE dbo.tblServizi
			SET
				IdRichiedente = @IdRichiedente,
				DataRichiesta = @DataRichiesta,
				Descrizione = @Descrizione,
				Durata = @Durata
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Servizio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			DELETE dbo.tblEventiEtichette
			WHERE Id = @IdEvento;

			INSERT dbo.tblEventiEtichette (Id, IdEtichetta)
			SELECT TOP 3 @IdEvento, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value
			WHERE v.value <> '';

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				AvvisoAnticipo = IIF(@Avviso = 0, NULL, @AvvisoAnticipo),
				Email = IIF(@Avviso = 0, NULL, @Email),
				Avviso = t.Nome + ' - ' + r.NomeCompleto + ' - ' + r.IndirizzoCompleto,
				Etichette = dbo.ufnEventi_get_Etichette(e.Id),
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
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
GO

GO

-- ===== 17. uspServiziAssegnati_upd (sql/procedures/uspServiziAssegnati_upd.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@DataRichiesta SMALLDATETIME = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@FirmaRichiedente IMAGE = NULL,
	@FirmaEsecutore IMAGE = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
		DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;
		DECLARE @idTipo CHAR(16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdRichiedente = NULLIF(LTRIM(RTRIM(@IdRichiedente)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

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
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Verifica che il servizio appartenga a un calendario accessibile dalla sessione e sia assegnato all'utente
		-- della sessione: in Servizi > Assegnati ognuno vede e gestisce solo i propri servizi
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			INNER JOIN dbo.tblEventiUtenti u ON e.Id = u.Id
			INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente AND ss.Id = @IdSessione
			WHERE
				s.Id = @Id
				AND e.Id = @IdEvento
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate. L'operatore le
		-- compila solo sui servizi assegnati a lui (controllo sopra)
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblServizi
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Campi obbligatori del tipo (S3.6): per segnare come eseguito il servizio vanno compilati (le caselle si/no spuntate),
		-- con i valori inviati dalla scheda o quelli gia' salvati
		IF @IdStato = 'E'
		BEGIN
			IF @idTipo IS NULL
				SELECT @idTipo = IdTipo
				FROM dbo.tblServizi
				WHERE Id = @Id;

			SELECT @returnMessage = Messaggio
			FROM dbo.ufnEventi_get_ProprietaObbligatoriaMancante(@IdEvento, @idTipo, @Proprieta);

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- La durata non si cambia da qui (la decide chi gestisce i Servizi), ma con la nuova data e ora il servizio
		-- deve ancora terminare entro la mezzanotte del giorno di inizio (regola di uspServizi_upd)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblServizi
			WHERE
				Id = @Id
				AND Durata IS NOT NULL
				AND ISNULL(@InGiornata, 0) = 0
				AND DATEADD(MINUTE, Durata, CAST(@Data AS DATETIME)) > DATEADD(DAY, 1, CAST(CAST(@Data AS DATE) AS DATETIME))
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: con la sua durata non può iniziare a quest''ora';
			GOTO BRANCH_END;
		END

		IF @FirmaRichiedente IS NOT NULL
			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

		IF @FirmaEsecutore IS NOT NULL
			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

		BEGIN TRANSACTION;

			-- Gestione firma richiedente
			IF @FirmaRichiedente IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'R';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaRichiedente;
			END
			ELSE IF @idFirmaRichiedente IS NULL
			BEGIN
				SET @idFirmaRichiedente = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaRichiedente, @FirmaRichiedente);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaRichiedente, 'R');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaRichiedente
				WHERE Id = @idFirmaRichiedente;

			-- Gestione firma esecutore
			IF @FirmaEsecutore IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'E';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaEsecutore;
			END
			ELSE IF @idFirmaEsecutore IS NULL
			BEGIN
				SET @idFirmaEsecutore = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaEsecutore, @FirmaEsecutore);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaEsecutore, 'E');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaEsecutore
				WHERE Id = @idFirmaEsecutore;

			UPDATE dbo.tblServizi
			SET
				IdRichiedente = @IdRichiedente,
				DataRichiesta = @DataRichiesta,
				Descrizione = @Descrizione
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Servizio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				Avviso = t.Nome + ' - ' + r.NomeCompleto + ' - ' + r.IndirizzoCompleto,
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
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

GO

-- ===== 18. uspServizi_get_Stampa_Proprieta (sql/procedures/uspServizi_get_Stampa_Proprieta.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Proprietà del tipo stampate sul Rapporto di intervento, nell'ordine del tipo (Pos), anche senza valore: la stampa
-- mette al loro posto lo spazio da compilare a mano. Data in formato dd/MM/yyyy, Sì/No in Spuntata. Stessi diritti
-- di uspServizi_get_Stampa, che fa anche i controlli sul servizio da stampare
CREATE OR ALTER PROCEDURE dbo.uspServizi_get_Stampa_Proprieta
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @assegnato BIT;

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

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		-- Servizio assegnato all'utente della sessione: con la sola SRA si stampano solo questi
		SET @assegnato = IIF(EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventiUtenti u ON s.IdEvento = u.Id
				INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente
			WHERE
				s.Id = @Id
				AND ss.Id = @IdSessione
		), 1, 0);

		-- Calendario di una sede accessibile e permesso SRV, oppure SRA sul servizio assegnato
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		   OR NOT (@permessoSrv >= 1 OR (@permessoSra >= 1 AND @assegnato = 1))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			t.Nome,
			p.IdTipoDato,
			Valore = CASE p.IdTipoDato
				WHEN 'D' THEN CONVERT(VARCHAR(10), TRY_CONVERT(DATE, ep.Valore, 23), 103)
				WHEN 'B' THEN NULL
				WHEN 'I' THEN REPLACE(NULLIF(ep.Valore, ''), '.', ',')
				ELSE NULLIF(ep.Valore, '')
			END,
			Spuntata = CAST(IIF(p.IdTipoDato = 'B' AND ep.Valore = 'true', 1, 0) AS BIT)
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblTipiProprieta t ON s.IdTipo = t.Id
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta ep ON s.IdEvento = ep.Id
												  AND t.IdProprieta = ep.IdProprieta
		WHERE
			s.Id = @Id
			AND t.Lock = 0
			-- Campo disattivato (S3.8): solo se ha un valore (una casella si/no se spuntata)
			AND
				(
				t.Attivo = 1
				OR (NULLIF(LTRIM(RTRIM(ep.Valore)), '') IS NOT NULL AND NOT (p.IdTipoDato = 'B' AND ep.Valore <> 'true'))
				)
		ORDER BY t.Pos;

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

GO

-- ===== 19. uspServiziAssegnati_get_Bacheca_List (sql/procedures/uspServiziAssegnati_get_Bacheca_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_get_Bacheca_List]
	@IdSessione CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL
AS
-- Servizi > Assegnati, vista Bacheca (S7.6): i servizi del calendario del contesto assegnati all'utente della sessione
-- nel giorno @Data, annullati esclusi, piu' quelli rimasti indietro, qualunque sia il giorno guardato: da eseguire con
-- la data di un giorno passato (riquadro Scaduti) e in esecuzione dei giorni passati (colonna In esecuzione).
-- Colonna: S scaduti, D da eseguire, I in esecuzione, E eseguiti. Come uspServiziAssegnati_get_List mostra i servizi
-- singoli e le occorrenze modificate (ufnEventi_get_Assegnati_List), mai le occorrenze generate di una serie
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Data non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 1 > @permessoSrv AND 1 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		DECLARE @idCal CHAR(16);

		SELECT @idUtente = IdUtente, @idCal = IdCalendario
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id) SELECT @idCal
		WHERE @idCal IS NOT NULL;

		-- Il giorno guardato e l'inizio di oggi: prima di oggi i servizi da eseguire o in esecuzione sono rimasti indietro
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@Data AS DATE) AS SMALLDATETIME);
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, DATEADD(DAY, 1, @inizio));
		DECLARE @oggi SMALLDATETIME = CAST(CAST(GETDATE() AS DATE) AS SMALLDATETIME);
		DECLARE @ieri SMALLDATETIME = DATEADD(MINUTE, -1, @oggi);

		;WITH cteEventi AS (
			-- Il giorno guardato
			SELECT e.Id, e.IdStato, e.[Data], e.InGiornata
			FROM dbo.ufnEventi_get_Assegnati_List(@inizio, @fine, @idUtente, @IdCalendario) e
			WHERE e.IdStato <> 'A'
			UNION
			-- Rimasti indietro, dai giorni passati
			SELECT e.Id, e.IdStato, e.[Data], e.InGiornata
			FROM dbo.ufnEventi_get_Assegnati_List('19000101', @ieri, @idUtente, @IdCalendario) e
			WHERE e.IdStato IN ('D', 'I')
		)
		SELECT
			s.Id,
			s.IdEvento,
			e.[Data],
			InGiornata = CAST(ISNULL(e.InGiornata, 0) AS BIT),
			s.Durata,
			e.IdStato,
			Colonna = CASE
				WHEN e.IdStato = 'D' AND e.[Data] < @oggi THEN 'S'
				ELSE e.IdStato
			END,
			-- Come negli altri elenchi: da eseguire o in esecuzione con la data passata (anche oggi, a un'ora gia' passata)
			Scaduto = CAST(IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0) AS BIT),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			Tipo = t.Nome,
			Richiedente = r.NomeCompleto,
			Indirizzo = r.IndirizzoCompleto,
			ev.Etichette,
			-- Proprieta' del tipo compilate (con un valore) e in tutto, per l'icona della scheda. Le caselle si/no (tipo dato
			-- B) non contano: la scheda le salva sempre (false se non spuntate) e "no" e' gia' una risposta
			ProprietaCompilate = ISNULL(p.Compilate, 0),
			ProprietaTotali = ISNULL(p.Totali, 0)
		FROM
			cteEventi e
			INNER JOIN dbo.tblEventi ev ON e.Id = ev.Id
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			OUTER APPLY (
				-- Con campi obbligatori (S3.6) contano solo quelli (una casella obbligatoria e' compilata se spuntata)
				SELECT
					Totali = COUNT(*),
					Compilate = SUM(IIF(NULLIF(LTRIM(RTRIM(v.Valore)), '') IS NULL OR (pr.IdTipoDato = 'B' AND v.Valore <> 'true'), 0, 1))
				FROM
					dbo.tblTipiProprieta tp
					LEFT JOIN dbo.tblEventiProprieta v ON v.Id = e.Id AND v.IdProprieta = tp.IdProprieta
					INNER JOIN dbo.tblProprieta pr ON tp.IdProprieta = pr.Id
				WHERE
					tp.Id = s.IdTipo
					AND tp.Lock = 0
					-- I campi disattivati (S3.8) non contano
					AND tp.Attivo = 1
					AND IIF(EXISTS (SELECT 1 FROM dbo.tblTipiProprieta o WHERE o.Id = s.IdTipo AND o.Lock = 0 AND o.Attivo = 1 AND o.Obbligatorio = 1),
						tp.Obbligatorio, IIF(pr.IdTipoDato <> 'B', 1, 0)) = 1
			) p
		ORDER BY
			e.[Data],
			s.Id;

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

GO

-- ===== 20. uspSYS_del_SedeInternaCascade (sql/procedures/uspSYS_del_SedeInternaCascade.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: lotti/allocazioni/magazzini specifici EoW di proprietà della sede (solo sedi
        -- interne, IdSede diretto su tutte e tre le tabelle) - vedi project_eow_module_design in
        -- memoria persistente.
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWAllocazioni FROM dbo.tblEoWAllocazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti hanno IdSede = sede
        -- operativa (può essere una sede figlia diversa dall'Azienda) - vedi project_magazzino
        -- in memoria persistente.
        SELECT Id INTO #MagArticoli FROM dbo.tblMagazziniArticoli WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagLotti FROM dbo.tblMagazziniLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagMovimenti FROM dbo.tblMagazziniMovimenti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa e Fatturazione: schede dell'azienda (o sul soggetto, se nella cascata),
        -- banche/casse e aliquote IVA proprie dell'azienda
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Schede amministratore dell'azienda (o su un soggetto della cascata)
        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture dell'azienda (o di una scheda della cascata) e conti dell'azienda
        SELECT Id INTO #Fatture FROM dbo.tblFatture
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);
        SELECT Id INTO #FattureConti FROM dbo.tblFattureConti WHERE IdSede IN (SELECT Id FROM #Sedi);        SELECT Id INTO #BancheCasse FROM dbo.tblBancheCasse WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #AliquoteIva FROM dbo.tblAliquoteIva WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Dichiarazioni MUD dell'azienda o che citano una sede della cascata
        SELECT Id INTO #RifiutiMud FROM dbo.tblRifiutiMud
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdSedeLegale IN (SELECT Id FROM #Sedi) OR IdSedeUnitaLocale IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);


        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che potrebbero essere
        -- cancellati (quelli dell'azienda o delle sue banche e casse, e quelli che coprono rate di
        -- queste fatture), raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche
        -- rate di altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti
        -- che alla fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #PagamentiCandidati FROM (
            SELECT Id FROM dbo.tblPagamenti
            WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi)
            UNION
            SELECT rp.IdPagamento FROM dbo.tblFattureRatePagamenti rp
            WHERE rp.IdRata IN (SELECT Id FROM #FattureRate)
        ) x;

        -- Offerte e contratti: importi (con le righe) e offerte o contratti dell'azienda, o di una
        -- scheda cliente della cascata
        SELECT Id INTO #Importi FROM dbo.tblImporti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #ImportiRighe FROM dbo.tblImportiRighe WHERE IdImporto IN (SELECT Id FROM #Importi);
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, conti, aliquote,
            -- etichette, tipi e sedi cancellati più sotto. I documenti fatturabili (registrazioni,
            -- movimenti di magazzino, servizi) hanno lo stesso Id del documento
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #MagMovimenti)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdImporto IN (SELECT Id FROM #Importi)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti
            WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti) OR IdImporto IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblImportiRigheDettagli WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRighe WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRifiuti WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiMagazzino WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiServizi WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImporti WHERE Id IN (SELECT Id FROM #Importi);
            -- Importi di ALTRE aziende che citano una sede, un'etichetta, un tipo, un conto o
            -- un'aliquota della cascata (non previsto dalle regole): perdono solo il collegamento
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdSedePartenza = NULL WHERE IdSedePartenza IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdSedeInterna = NULL WHERE IdSedeInterna IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino di ALTRE aziende su un articolo della cascata (non previsto): perdono l'articolo
            DELETE FROM dbo.tblImportiRigheMagazzino WHERE IdArticolo IN (SELECT Id FROM #MagArticoli);
            -- Righe di listino di ALTRE aziende su una persona o un oggetto della cascata (condivisi): perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);
            UPDATE dbo.tblImportiRigheDettagli SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            UPDATE dbo.tblImportiRigheDettagli SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            -- Indirizzi di intervento dei formulari unici: dei movimenti cancellati e, negli altri movimenti, quelli
            -- che sono una delle sedi cancellate
            DELETE FROM dbo.tblRifiutiMovimentiSediProduzione WHERE Id IN (SELECT Id FROM #RifiutiMovimenti) OR IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE CASCADE).
            -- Va fatta prima della Gestione EoW: le righe EoW di scarico referenziano tblEoWLotti.
            -- Relazioni carico/scarico in entrambi i versi (righe della sede, dei suoi movimenti o
            -- dei suoi lotti): FK NO_ACTION su Id e IdParent verso tblMagazziniMovimentiRighe.
            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
            INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
            WHERE r.IdSede IN (SELECT Id FROM #Sedi) OR r.IdMovimento IN (SELECT Id FROM #MagMovimenti) OR r.IdLotto IN (SELECT Id FROM #MagLotti);

            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
            INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
            WHERE
                re.IdSede IN (SELECT Id FROM #Sedi)
                OR re.IdMovimento IN (SELECT Id FROM #MagMovimenti)
                OR re.IdLotto IN (SELECT Id FROM #EoWLotti)
                OR rel.IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdSede IN (SELECT Id FROM #Sedi)
                OR IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi)
                OR IdMovimento IN (SELECT Id FROM #MagMovimenti);

            DELETE FROM dbo.tblMagazziniMovimentiRighe
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniMovimentiRigheEoW
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniMovimenti WHERE Id IN (SELECT Id FROM #MagMovimenti);
            DELETE FROM dbo.tblMagazziniLotti WHERE Id IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniArticoli WHERE Id IN (SELECT Id FROM #MagArticoli);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni sottostanti, per rispettare
            -- la FK di tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK
            -- composta con IdLotto - non azzerabile, la riga di collegamento va sempre rimossa,
            -- anche quando referenzia una Registrazione di questa sede legata a un Lotto di un'altra:
            -- stesso motivo dell'OR su #RifiutiRegistrazioni). I lotti/allocazioni EoW di questa sede
            -- vengono invece cancellati per intero (non azzerati) perché sono risorse di proprietà
            -- esclusiva della sede stessa, non condivise con altre sedi.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni
            WHERE IdLotto        IN (SELECT Id FROM #EoWLotti)
               OR IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWLottiAllocazioni
            WHERE IdLotto      IN (SELECT Id FROM #EoWLotti)
               OR IdAllocazione IN (SELECT Id FROM #EoWAllocazioni);
            DELETE FROM dbo.tblEoWLotti       WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWAllocazioni WHERE Id IN (SELECT Id FROM #EoWAllocazioni);

            -- tblEoWLotti.IdMagazzino (nullable, nessun vincolo strutturale che lo leghi allo stesso
            -- IdSede del Lotto) può referenziare un Magazzino di questa sede anche da un Lotto esterno
            -- alla cascata - i Lotti di questa sede sono già stati cancellati sopra, quindi qui restano
            -- solo eventuali riferimenti esterni: azzerati, non cancellati (stessa logica "UPDATE=NULL
            -- dove possibile" delle risorse condivise più sotto).
            DECLARE @eoWLottiScollegati INT;
            UPDATE dbo.tblEoWLotti SET IdMagazzino = NULL WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
            SET @eoWLottiScollegati = @@ROWCOUNT;
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- Allegati VII DIWASS delle aziende cancellate (con i soggetti), soggetti delle sedi cancellate negli altri
            -- Allegati VII, codici e ruoli di firma ricordati per le aziende
            SELECT Id INTO #DiwassAllegatiVii FROM dbo.tblDiwassAllegatiVii WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiViiConferme WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii);
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiVii WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii);
            DELETE FROM dbo.tblDiwassCodiciRifiutiUsati WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassFirmeRuoli WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- Importazioni da RENTRI dei registri (FK su IdRegistro, nessun ON DELETE CASCADE): anteprime e storico;
            -- le tabelle figlie (movimenti, anomalie, soggetti, relazioni, causali) si cancellano a cascata
            DELETE FROM dbo.tblRentriImportazioni WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            -- Dichiarazioni MUD: registri della dichiarazione (FK su tblRifiutiMud e su
            -- tblRifiutiRegistri), poi la dichiarazione
            DELETE FROM dbo.tblRifiutiMudRegistri
            WHERE Id IN (SELECT Id FROM #RifiutiMud) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiMud WHERE Id IN (SELECT Id FROM #RifiutiMud);

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprietaVoci WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Anagrafica estesa e Fatturazione: prima le schede, che referenziano banche/casse e
            -- aliquote; le schede di ALTRE aziende che usano un'aliquota o una banca di questa
            -- (non previsto dalle regole) perdono solo il collegamento
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);
            UPDATE dbo.tblClientiFornitori SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            UPDATE dbo.tblClientiFornitori SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            -- Conti: le righe di ALTRE aziende che li usano (non previsto dalle regole) perdono solo il
            -- collegamento, come per banche/casse e aliquote
            UPDATE dbo.tblFattureRigheImporti SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureConti WHERE Id IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureDatiFiscali WHERE Id IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblFattureRigheImporti SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            UPDATE dbo.tblFatture SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblFattureRatePagamenti
            WHERE IdPagamento IN (SELECT Id FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi));
            DELETE FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi);            DELETE FROM dbo.tblBancheCasse WHERE Id IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblAliquoteIva WHERE Id IN (SELECT Id FROM #AliquoteIva);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediReport WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            -- Associazione alla credenziale DIWASS prima di tblSediInterne (FK su IdAziendaInterna): la credenziale
            -- è del dominio e resta
            DELETE FROM dbo.tblDiwassCredenzialiAziende WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            -- Lo stesso per la credenziale Vi.Vi.FIR (formulario unico degli spurghisti)
            DELETE FROM dbo.tblViviFirCredenzialiAziende WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #MagArticoli
                UNION SELECT Id FROM #MagLotti
                UNION SELECT Id FROM #MagMovimenti
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #FattureConti
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #Importi
                UNION SELECT Id FROM #ImportiRighe
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #BancheCasse
                UNION SELECT Id FROM #AliquoteIva
                UNION SELECT Id FROM #RifiutiMud
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWAllocazioni
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #DiwassAllegatiVii
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Allocazioni EoW rimosse: ', (SELECT COUNT(*) FROM #EoWAllocazioni), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ' (Lotti esterni scollegati: ', @eoWLottiScollegati, ')', ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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

-- ===== 21. uspSYS_del_SedeEsternaCascade (sql/procedures/uspSYS_del_SedeEsternaCascade.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeEsternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'E')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede esterna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + eventuali sotto-sedi collegate tramite tblSedi.IdParent (es. altre
        -- sedi/filiali dello stesso cliente/fornitore esterno), a qualunque profondità. A
        -- differenza di una sede interna, da una sede esterna NON si scende mai tramite
        -- IdAziendaInterna (punta sempre in alto verso la sede interna che la gestisce, mai verso
        -- un'altra sede da cancellare) né tramite tblSediEsterne.IdSedeInterna (stesso concetto).
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT s.Id
            FROM dbo.tblSedi s
            INNER JOIN #Sedi c ON s.IdParent = c.Id
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = s.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). Stessa struttura
        -- generica di uspSYS_del_SedeInternaCascade: tutte queste tabelle referenziano tblSedi.Id
        -- indipendentemente dal tipo (interna/esterna), anche se in pratica per una sede esterna
        -- oggi solo Autorizzazioni e Movimenti risultano popolati (verificato). Gestione EoW esclusa:
        -- i Magazzini EoW sono di sede interna (confermato dall'utente), una sede esterna non ne ha
        -- di propri - può però avere un proprio Registro/Registrazioni referenziati da movimenti EoW
        -- di un magazzino interno, gestiti più sotto.
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa: schede cliente/fornitore sul soggetto
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori WHERE IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture delle schede cliente/fornitore del soggetto
        SELECT Id INTO #Fatture FROM dbo.tblFatture WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti* non è mai popolato per una sede esterna (i Limiti si possono creare
        -- solo su sedi interne, confermato dall'utente): a differenza di uspSYS_del_SedeInternaCascade,
        -- qui non serve raccoglierlo/cancellarlo.

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe sono giunzioni a chiave composita verso risorse condivise
        -- a livello di Dominio (tblAree), non di proprietà della sede: si cancellano solo le righe
        -- di giunzione, mai tblAree stessa.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che coprono le loro
        -- rate, raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche rate di
        -- altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti che alla
        -- fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT DISTINCT rp.IdPagamento AS Id INTO #PagamentiCandidati
        FROM dbo.tblFattureRatePagamenti rp
        WHERE rp.IdRata IN (SELECT Id FROM #FattureRate);

        -- Offerte e contratti: offerte e contratti delle schede cliente del soggetto
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, etichette, tipi e
            -- sedi cancellati più sotto. I documenti fatturabili (registrazioni, servizi) hanno lo
            -- stesso Id del documento. Gli importi dei contratti cancellati restano all'azienda
            -- interna, senza contratto
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            -- Importi che citano una sede, un'etichetta o un tipo della cascata: perdono solo la variabile
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino su una persona o un oggetto della cascata: perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            -- Indirizzi di intervento dei formulari unici: dei movimenti cancellati e, negli altri movimenti, quelli
            -- che sono una delle sedi cancellate
            DELETE FROM dbo.tblRifiutiMovimentiSediProduzione WHERE Id IN (SELECT Id FROM #RifiutiMovimenti) OR IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: questa sede esterna non ha lotti/allocazioni EoW propri (che referenziano
            -- solo Sede Interna), ma le sue Registrazioni possono essere referenziate da
            -- tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK composta con
            -- IdLotto) - non azzerabile come il vecchio tblEoWMovimenti.IdRegistrazione (nullable),
            -- va rimossa la riga di collegamento; il Lotto di una sede interna resta intatto.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiViiSoggetti.IdSede: le sedi cancellate escono dagli Allegati VII DIWASS preparati in Ecomatico;
            -- in quelli ricevuti da DIWASS il soggetto resta con nome e indirizzo letti da DIWASS
            UPDATE x SET IdSede = NULL FROM dbo.tblDiwassAllegatiViiSoggetti x INNER JOIN dbo.tblDiwassAllegatiVii a ON x.Id = a.Id WHERE x.IdSede IN (SELECT Id FROM #Sedi) AND a.Ricevuto = 1;
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            -- In pratica un Registro RENTRI appartiene sempre a una sede interna, ma la SP resta
            -- generica per coerenza con la raccolta #RifiutiRegistri già fatta sopra. Lo stesso per le
            -- importazioni da RENTRI (FK su IdRegistro; le tabelle figlie si cancellano a cascata).
            DELETE FROM dbo.tblRentriImportazioni WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprietaVoci WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata (stessa logica
            -- ibrida di uspSYS_del_SedeInternaCascade: UPDATE=NULL dove la colonna è nullable,
            -- DELETE della riga di giunzione dove è NOT NULL).
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
            -- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
            -- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne). Il DDT viene rimosso,
            -- il movimento di magazzino della sede interna resta.
            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi);

            -- Anagrafica estesa: schede cliente/fornitore sul soggetto
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);

            -- Anagrafica estesa: schede amministratore del soggetto con i loro amministrati, e il
            -- soggetto tolto dagli amministrati delle altre schede
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree non toccata)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare). In pratica associata solo a sedi interne, ma la SP resta generica
            -- per lo stesso motivo della raccolta #RifiutiRegistri sopra.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: il vincolo
            -- auto-referenziato IdParent è verificato a fine istruzione (non riga per riga), quindi
            -- non si blocca da solo anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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

-- ===== 22. uspServizi_upd_Eseguiti (sql/procedures/uspServizi_upd_Eseguiti.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Segna eseguiti (Servizi > Calendario > Elenco, Azioni > Segna eseguiti, S6.8; decisione dell'utente del 2026-11-24):
-- i servizi da eseguire o in esecuzione trovati dalla ricerca dell'Elenco (stessi filtri di uspServizi_get_List:
-- calendario del contesto, periodo, stato, etichetta, descrizione) con l'inizio gia' passato. Un servizio singolo o
-- un'occorrenza modificata cambia stato; un'occorrenza di una serie diventa un'occorrenza modificata eseguita (copia
-- come in uspServizi_upd_Data), perche' la serie non si esegue (S6.2). Restano fuori, e si elencano, quelli con un
-- campo obbligatorio vuoto (S3.6). Al massimo 500 per volta.
-- @Conferma = 0: anteprima senza scritture, restituisce DaSegnare ed Esclusi; con @Esclusi = 1 invece l'elenco degli
-- esclusi con il motivo (al massimo 100).
-- @Conferma = 1: esegue e restituisce Segnati.
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd_Eseguiti]
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@Conferma BIT = 0,
	@Esclusi BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = ISNULL(NULLIF(LTRIM(RTRIM(@Stato)), ''), 'T');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Calendario del contesto, di una sede interna accessibile
		DECLARE @idCalendario CHAR(16) = (SELECT IdCalendario FROM dbo.tblSessioni WHERE Id = @IdSessione);
		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblCalendari c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @idCalendario)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @calendari tvpId_char_16;
		INSERT INTO @calendari (Id) VALUES (@idCalendario);
		DECLARE @tipi tvpId_char_1;
		INSERT INTO @tipi (Id) VALUES ('V');

		-- Stesso periodo di uspServizi_get_List (S4.7.5): dalla data alle 00:00 per l'intervallo, fine esclusa
		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);
		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, CASE
			WHEN @IdIntervallo = '1W' THEN DATEADD(WEEK, 1, @DallaData)
			WHEN @IdIntervallo = '2W' THEN DATEADD(WEEK, 2, @DallaData)
			WHEN @IdIntervallo = '1M' THEN DATEADD(MONTH, 1, @DallaData)
			WHEN @IdIntervallo = '2M' THEN DATEADD(MONTH, 2, @DallaData)
			WHEN @IdIntervallo = '6M' THEN DATEADD(MONTH, 6, @DallaData)
			WHEN @IdIntervallo = '1Y' THEN DATEADD(YEAR, 1, @DallaData)
			ELSE DATEADD(DAY, 1, @DallaData)
		END);

		DECLARE @adesso SMALLDATETIME = GETDATE();

		-- Servizi della ricerca da eseguire o in esecuzione, gia' iniziati (le occorrenze generate hanno lo stato della serie)
		CREATE TABLE #servizi (
			Riga INT IDENTITY(1, 1) PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdTipo CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NOT NULL,
			Ricorre BIT NOT NULL,
			Messaggio NVARCHAR(200) NULL
		);

		INSERT INTO #servizi (Id, IdEvento, IdTipo, [Data], Ricorre)
		SELECT s.Id, s.IdEvento, s.IdTipo, e.[Data], e.Ricorre
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @calendari, @tipi) e ON s.IdEvento = e.Id
		WHERE
			e.IdStato IN ('D', 'I')
			AND e.[Data] <= @adesso
			AND (@Stato IN ('T', 'S') OR e.IdStato = @Stato)
			AND (@Search IS NULL OR s.Descrizione LIKE '%' + @Search + '%')
			AND (@Etichetta IS NULL OR s.IdEvento IN (
				SELECT x.Id
				FROM
					dbo.tblEventiEtichette x
					INNER JOIN dbo.tblEtichette t ON x.IdEtichetta = t.Id
				WHERE t.Nome LIKE '%' + @Etichetta + '%'))
		ORDER BY e.[Data], s.Id;

		-- Campi obbligatori del tipo (S3.6) con i valori salvati (della serie, per un'occorrenza generata)
		UPDATE x
		SET Messaggio = m.Messaggio
		FROM
			#servizi x
			CROSS APPLY dbo.ufnEventi_get_ProprietaObbligatoriaMancante(x.IdEvento, x.IdTipo, NULL) m;

		DECLARE @daSegnare INT = (SELECT COUNT(*) FROM #servizi WHERE Messaggio IS NULL);
		DECLARE @numeroEsclusi INT = (SELECT COUNT(*) FROM #servizi WHERE Messaggio IS NOT NULL);

		IF @daSegnare > 500
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ci sono ' + CAST(@daSegnare AS VARCHAR(10)) + ' servizi da segnare: al massimo 500 per volta, restringere la ricerca';
			GOTO BRANCH_END;
		END

		IF @Conferma = 0
		BEGIN
			IF @Esclusi = 0
			BEGIN
				SELECT DaSegnare = @daSegnare, Esclusi = @numeroEsclusi;
				GOTO BRANCH_END;
			END

			SELECT TOP (100)
				x.[Data],
				Tipo = t.Nome,
				Richiedente = r.NomeCompleto,
				s.Descrizione,
				x.Messaggio
			FROM
				#servizi x
				INNER JOIN dbo.tblServizi s ON x.Id = s.Id
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			WHERE x.Messaggio IS NOT NULL
			ORDER BY x.Riga;

			GOTO BRANCH_END;
		END

		DECLARE @segnati INT = 0;
		DECLARE @riga INT = 0;
		DECLARE @id CHAR(16), @idEvento CHAR(16), @data SMALLDATETIME, @ricorre BIT;
		DECLARE @returnId CHAR(16), @returnIdEvento CHAR(16);

		WHILE 1 = 1
		BEGIN
			SELECT TOP (1) @riga = Riga, @id = Id, @idEvento = IdEvento, @data = [Data], @ricorre = Ricorre
			FROM #servizi
			WHERE
				Riga > @riga
				AND Messaggio IS NULL
			ORDER BY Riga;

			IF @@ROWCOUNT = 0
				BREAK;

			IF @ricorre = 0
			BEGIN
				-- Servizio singolo o occorrenza modificata: cambia lo stato
				UPDATE dbo.tblEventi
				SET IdStato = 'E'
				WHERE
					Id = @idEvento
					AND Lock = 0
					AND IdStato IN ('D', 'I');

				IF @@ROWCOUNT > 0
				BEGIN
					SET @segnati += 1;
					EXEC dbo.uspId_upd @Id = @id, @IdSessione = @IdSessione, @Operazione = 'U';
				END
			END
			ELSE
			BEGIN
				-- Occorrenza di una serie, ancora da modificare: diventa un'occorrenza modificata eseguita (S5.3),
				-- con la copia di uspServizi_upd_Data alla stessa data
				IF NOT EXISTS (
					SELECT 1
					FROM dbo.tblRicorrenzeEccezioni
					WHERE
						Id = @idEvento
						AND [Data] = @data
						AND Lock = 0)
				BEGIN
					-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione)
					SET @returnIdEvento = NULL;
					SET @returnId = NULL;
					EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
					EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

					BEGIN TRANSACTION;

						INSERT INTO dbo.tblEventi
							(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
						SELECT
							@returnIdEvento, IdCalendario, 'E', 'V', @data,
							InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, 0
						FROM dbo.tblEventi
						WHERE Id = @idEvento;

						INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
						SELECT @returnIdEvento, IdProprieta, Valore
						FROM dbo.tblEventiProprieta
						WHERE Id = @idEvento;

						INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
						SELECT @returnIdEvento, IdEtichetta
						FROM dbo.tblEventiEtichette
						WHERE Id = @idEvento;

						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @idEvento
							AND [Data] = @data;

						INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
						VALUES (@idEvento, @data, @returnIdEvento, 0);

						INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata)
						SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata
						FROM dbo.tblServizi
						WHERE IdEvento = @idEvento;

						INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
						SELECT @returnId, o.IdOsepe, o.Quantita
						FROM dbo.tblServiziOsepe o
						WHERE o.Id = @id;

					COMMIT TRANSACTION;

					SET @segnati += 1;
					EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';
				END
			END
		END

		SELECT Segnati = @segnati, Esclusi = @numeroEsclusi;

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

GO

-- ===== 23. uspScadenze_upd_Eseguite (sql/procedures/uspScadenze_upd_Eseguite.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Segna eseguite (Scadenze > Calendario > Elenco, Azioni > Segna eseguite, S5.10; decisione dell'utente del 2026-11-24):
-- le scadenze da eseguire o in esecuzione trovate dalla ricerca dell'Elenco (stessi filtri di uspScadenze_get_List:
-- calendario del contesto, periodo, stato, etichetta, descrizione) con la data gia' passata. Una scadenza singola o
-- un'occorrenza modificata cambia stato; un'occorrenza di una serie diventa un'occorrenza modificata eseguita (copia
-- come in uspScadenze_upd_Data), perche' la serie non si esegue (S5.9). Restano fuori, e si elencano, quelli con un
-- campo obbligatorio vuoto (S3.6). Al massimo 500 per volta.
-- @Conferma = 0: anteprima senza scritture, restituisce DaSegnare ed Esclusi; con @Esclusi = 1 invece l'elenco degli
-- esclusi con il motivo (al massimo 100).
-- @Conferma = 1: esegue e restituisce Segnati.
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_upd_Eseguite]
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@Conferma BIT = 0,
	@Esclusi BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = ISNULL(NULLIF(LTRIM(RTRIM(@Stato)), ''), 'T');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
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

		-- Calendario del contesto, di una sede interna accessibile
		DECLARE @idCalendario CHAR(16) = (SELECT IdCalendario FROM dbo.tblSessioni WHERE Id = @IdSessione);
		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblCalendari c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @idCalendario)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @calendari tvpId_char_16;
		INSERT INTO @calendari (Id) VALUES (@idCalendario);
		DECLARE @tipi tvpId_char_1;
		INSERT INTO @tipi (Id) VALUES ('S');

		-- Stesso periodo di uspScadenze_get_List (S4.7.5): dalla data alle 00:00 per l'intervallo, fine esclusa
		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);
		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, CASE
			WHEN @IdIntervallo = '1W' THEN DATEADD(WEEK, 1, @DallaData)
			WHEN @IdIntervallo = '2W' THEN DATEADD(WEEK, 2, @DallaData)
			WHEN @IdIntervallo = '1M' THEN DATEADD(MONTH, 1, @DallaData)
			WHEN @IdIntervallo = '2M' THEN DATEADD(MONTH, 2, @DallaData)
			WHEN @IdIntervallo = '6M' THEN DATEADD(MONTH, 6, @DallaData)
			WHEN @IdIntervallo = '1Y' THEN DATEADD(YEAR, 1, @DallaData)
			ELSE DATEADD(DAY, 1, @DallaData)
		END);

		DECLARE @adesso SMALLDATETIME = GETDATE();

		-- Scadenze della ricerca da eseguire o in esecuzione, gia' iniziati (le occorrenze generate hanno lo stato della serie)
		CREATE TABLE #scadenze (
			Riga INT IDENTITY(1, 1) PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdTipo CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NOT NULL,
			Ricorre BIT NOT NULL,
			Messaggio NVARCHAR(200) NULL
		);

		INSERT INTO #scadenze (Id, IdEvento, IdTipo, [Data], Ricorre)
		SELECT s.Id, s.IdEvento, s.IdTipo, e.[Data], e.Ricorre
		FROM
			dbo.tblScadenze s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @calendari, @tipi) e ON s.IdEvento = e.Id
		WHERE
			e.IdStato IN ('D', 'I')
			AND e.[Data] <= @adesso
			AND (@Stato IN ('T', 'S') OR e.IdStato = @Stato)
			AND (@Search IS NULL OR s.Descrizione LIKE '%' + @Search + '%')
			AND (@Etichetta IS NULL OR s.IdEvento IN (
				SELECT x.Id
				FROM
					dbo.tblEventiEtichette x
					INNER JOIN dbo.tblEtichette t ON x.IdEtichetta = t.Id
				WHERE t.Nome LIKE '%' + @Etichetta + '%'))
		ORDER BY e.[Data], s.Id;

		-- Campi obbligatori del tipo (S3.6) con i valori salvati (della serie, per un'occorrenza generata)
		UPDATE x
		SET Messaggio = m.Messaggio
		FROM
			#scadenze x
			CROSS APPLY dbo.ufnEventi_get_ProprietaObbligatoriaMancante(x.IdEvento, x.IdTipo, NULL) m;

		DECLARE @daSegnare INT = (SELECT COUNT(*) FROM #scadenze WHERE Messaggio IS NULL);
		DECLARE @numeroEsclusi INT = (SELECT COUNT(*) FROM #scadenze WHERE Messaggio IS NOT NULL);

		IF @daSegnare > 500
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ci sono ' + CAST(@daSegnare AS VARCHAR(10)) + ' scadenze da segnare: al massimo 500 per volta, restringere la ricerca';
			GOTO BRANCH_END;
		END

		IF @Conferma = 0
		BEGIN
			IF @Esclusi = 0
			BEGIN
				SELECT DaSegnare = @daSegnare, Esclusi = @numeroEsclusi;
				GOTO BRANCH_END;
			END

			SELECT TOP (100)
				x.[Data],
				Tipo = t.Nome,
				s.Descrizione,
				x.Messaggio
			FROM
				#scadenze x
				INNER JOIN dbo.tblScadenze s ON x.Id = s.Id
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			WHERE x.Messaggio IS NOT NULL
			ORDER BY x.Riga;

			GOTO BRANCH_END;
		END

		DECLARE @segnati INT = 0;
		DECLARE @riga INT = 0;
		DECLARE @id CHAR(16), @idEvento CHAR(16), @data SMALLDATETIME, @ricorre BIT;
		DECLARE @returnId CHAR(16), @returnIdEvento CHAR(16);

		WHILE 1 = 1
		BEGIN
			SELECT TOP (1) @riga = Riga, @id = Id, @idEvento = IdEvento, @data = [Data], @ricorre = Ricorre
			FROM #scadenze
			WHERE
				Riga > @riga
				AND Messaggio IS NULL
			ORDER BY Riga;

			IF @@ROWCOUNT = 0
				BREAK;

			IF @ricorre = 0
			BEGIN
				-- Scadenza singola o occorrenza modificata: cambia lo stato
				UPDATE dbo.tblEventi
				SET IdStato = 'E'
				WHERE
					Id = @idEvento
					AND Lock = 0
					AND IdStato IN ('D', 'I');

				IF @@ROWCOUNT > 0
				BEGIN
					SET @segnati += 1;
					EXEC dbo.uspId_upd @Id = @id, @IdSessione = @IdSessione, @Operazione = 'U';
				END
			END
			ELSE
			BEGIN
				-- Occorrenza di una serie, ancora da modificare: diventa un'occorrenza modificata eseguita (S5.3),
				-- con la copia di uspScadenze_upd_Data alla stessa data
				IF NOT EXISTS (
					SELECT 1
					FROM dbo.tblRicorrenzeEccezioni
					WHERE
						Id = @idEvento
						AND [Data] = @data
						AND Lock = 0)
				BEGIN
					-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione)
					SET @returnIdEvento = NULL;
					SET @returnId = NULL;
					EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
					EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

					BEGIN TRANSACTION;

						INSERT INTO dbo.tblEventi
							(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
						SELECT
							@returnIdEvento, IdCalendario, 'E', 'S', @data,
							InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, 0
						FROM dbo.tblEventi
						WHERE Id = @idEvento;

						INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
						SELECT @returnIdEvento, IdProprieta, Valore
						FROM dbo.tblEventiProprieta
						WHERE Id = @idEvento;

						INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
						SELECT @returnIdEvento, IdEtichetta
						FROM dbo.tblEventiEtichette
						WHERE Id = @idEvento;

						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @idEvento
							AND [Data] = @data;

						INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
						VALUES (@idEvento, @data, @returnIdEvento, 0);

						INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo, Descrizione)
						SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, Descrizione
						FROM dbo.tblScadenze
						WHERE IdEvento = @idEvento;

						INSERT INTO dbo.tblScadenzeOsepe (Id, IdOsepe)
						SELECT @returnId, o.IdOsepe
						FROM dbo.tblScadenzeOsepe o
						WHERE o.Id = @id;

					COMMIT TRANSACTION;

					SET @segnati += 1;
					EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';
				END
			END
		END

		SELECT Segnati = @segnati, Esclusi = @numeroEsclusi;

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

GO

-- ===== 24. uspFatture_get_Fatturato (sql/procedures/uspFatture_get_Fatturato.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Report: report del fatturato dell'azienda del contesto in un anno, dalle fatture clienti
-- (@Tipo = C) o fornitori (@Tipo = F), raggruppato per mese (@Raggruppamento = M), per cliente o fornitore (S)
-- o per conto (C). La stessa SP serve l'elenco a video e l'esportazione in Excel e in CSV: il nome di ogni
-- colonna è l'intestazione, nell'ordine in cui le colonne vanno mostrate (pagina comune dei report).
-- Contano le fatture attive (Lock = 0: né bozze né cancellate) con data di emissione nell'anno (per un
-- fornitore è la data del suo documento), escluse le pre-fatture (TD00); le note di credito (TD04) contano
-- con il segno meno. Senza @Anno vale l'anno in corso.
-- Per mese (sempre 12 righe) e per cliente o fornitore gli importi sono i totali delle fatture
-- (ufnFatture_get_Totali: il totale comprende il bollo). Per conto si sommano gli imponibili delle righe,
-- perché il conto sta sulla riga: niente IVA né totale, e le righe senza conto vanno in "(Senza conto)".
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che il limite è superato).
-- @Tipo = D, @Raggruppamento = N (P2.9, dal 2026-11-24): documenti dell'anno non ancora fatturati (registrazioni dei
-- rifiuti, DDT di magazzino e servizi eseguiti dei moduli attivi), dalla stessa funzione della procedura automatica
-- (ufnFattureGenera_get_Documenti, pre-fatture comprese), con il motivo per cui la procedura li lascerebbe fuori;
-- esclusi gli annullati e quelli indicati come non fatturabili. Senza il modulo Offerte e contratti nessuna riga.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Fatturato
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Raggruppamento CHAR(1) = NULL,
	@Anno INT = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Raggruppamento = UPPER(NULLIF(LTRIM(RTRIM(@Raggruppamento)), ''));
		SET @Anno = ISNULL(NULLIF(@Anno, 0), YEAR(GETDATE()));
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F', 'D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente), F (fornitore) o D (documenti da fatturare)';
			GOTO BRANCH_END;
		END
		IF @Raggruppamento IS NULL OR @Raggruppamento NOT IN ('M', 'S', 'C', 'N')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Raggruppamento deve essere M (mese), S (cliente o fornitore) o C (conto)';
			GOTO BRANCH_END;
		END
		IF @Anno < 1900 OR @Anno > 2100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare un anno compreso tra 1900 e 2100';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @dataDa DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @dataA DATE = DATEFROMPARTS(@Anno, 12, 31);

		-- Documenti non ancora fatturati (P2.9)
		IF @Tipo = 'D'
		BEGIN
			IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
			BEGIN
				SELECT TOP (0) Documento = CAST(NULL AS VARCHAR(200));
				GOTO BRANCH_END;
			END

			DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda FROM dbo.tblSessioni WHERE Id = @IdSessione);
			DECLARE @rifiuti BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0);
			DECLARE @magazzino BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0);
			DECLARE @servizi BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0);

			SELECT TOP (@MaxRighe + 1)
				Documento = CAST(CASE d.IdModulo
					WHEN 'MAG' THEN 'DDT' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)) + ISNULL('/' + dd.Sezionale, ''), '') + ISNULL(' - ' + sd.NomeCompleto, '')
					WHEN 'SRV' THEN 'Servizio' + ISNULL(' ' + tp.Nome, '') + ISNULL(' - ' + sd.NomeCompleto, '')
					ELSE 'Registrazione' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)), '')
						+ ISNULL(' - EER ' + e.Nome + IIF(e.Pericoloso = 1, '*', ''), '')
				END AS VARCHAR(200)),
				[Data] = CAST(d.[Data] AS DATE),
				Cliente = sc.NomeCompleto,
				Imponibile = CAST(d.Imponibile AS DECIMAL(18, 2)),
				[Pronto da fatturare] = d.Fatturabile,
				Motivo = CAST(CASE d.Esito
					WHEN 'P' THEN 'In pre-fattura del ' + ISNULL(CONVERT(VARCHAR(10), f.DataEmissione, 103), '')
					WHEN 'S' THEN 'Contratto non valido alla data: si applica l''importo standard'
					WHEN 'I' THEN IIF(d.IdImporto IS NOT NULL AND d.IdModulo IN ('MAG', 'SRV'),
						'L''importo "' + ISNULL(i.Nome, '') + '" non ha una riga per ' + IIF(d.IdModulo = 'SRV', 'tutte le risorse del servizio', 'tutti gli articoli o i materiali del DDT'),
						'Nessun importo coincide')
					WHEN 'C' THEN 'Cliente non determinato: ' + CASE d.IdModulo WHEN 'MAG' THEN 'il destinatario' WHEN 'SRV' THEN 'il richiedente' ELSE 'il produttore' END + ' non ha una scheda cliente'
					WHEN 'R' THEN 'L''importo non ha righe applicabili'
					WHEN 'V' THEN 'Aliquota IVA non indicata né sull''importo né sulla scheda del cliente'
				END AS VARCHAR(300))
			FROM
				dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @dataDa, @dataA, NULL, 1, @rifiuti, @magazzino, @servizi) d
				LEFT JOIN dbo.tblRifiutiEer e ON d.IdEer = e.Id
				LEFT JOIN dbo.tblMagazziniDdt dd ON d.IdModulo = 'MAG'
											  AND d.Id = dd.IdMovimento
				LEFT JOIN dbo.tblServizi sv ON d.IdModulo = 'SRV'
										 AND d.Id = sv.Id
				LEFT JOIN dbo.tblTipi tp ON sv.IdTipo = tp.Id
				LEFT JOIN dbo.tblSedi sd ON d.IdModulo IN ('MAG', 'SRV')
										 AND d.IdProduttore = sd.Id
				LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
				LEFT JOIN dbo.tblImporti i ON d.IdImporto = i.Id
				LEFT JOIN dbo.tblFatture f ON d.IdPreFattura = f.Id
			WHERE d.Esito NOT IN ('A', 'N')
			ORDER BY d.[Data], d.Numero, d.Id
			OPTION (RECOMPILE);

			GOTO BRANCH_END;
		END

		-- Fatture dell'anno, con il segno (meno per le note di credito) e i totali
		DECLARE @fatture TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Mese INT NOT NULL,
			Segno INT NOT NULL,
			Imponibile DECIMAL(18, 2) NOT NULL,
			Iva DECIMAL(18, 2) NOT NULL,
			Totale DECIMAL(18, 2) NOT NULL
		);

		INSERT @fatture (Id, IdClienteFornitore, Mese, Segno, Imponibile, Iva, Totale)
		SELECT
			f.Id,
			f.IdClienteFornitore,
			MONTH(f.DataEmissione),
			IIF(f.IdTipo = 'TD04', -1, 1),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Imponibile, 0),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Iva, 0),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Totale, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
		WHERE
			e.Id = @IdSessione
			AND f.Tipo = @Tipo
			AND f.Lock = 0
			AND f.DataEmissione >= @dataDa
			AND f.DataEmissione <= @dataA
			AND ISNULL(f.IdTipo, '') <> 'TD00';

		IF @Raggruppamento = 'M'
			SELECT
				[Mese] = n.Nome,
				[Documenti] = COUNT(f.Id),
				[Imponibile] = ISNULL(SUM(f.Imponibile), 0),
				[IVA] = ISNULL(SUM(f.Iva), 0),
				[Totale] = ISNULL(SUM(f.Totale), 0)
			FROM
				(VALUES (1, 'Gennaio'), (2, 'Febbraio'), (3, 'Marzo'), (4, 'Aprile'), (5, 'Maggio'), (6, 'Giugno'), (7, 'Luglio'), (8, 'Agosto'), (9, 'Settembre'), (10, 'Ottobre'), (11, 'Novembre'), (12, 'Dicembre')) n (Mese, Nome)
				LEFT JOIN @fatture f ON n.Mese = f.Mese
			-- Senza azienda nel contesto nessuna riga, come negli altri raggruppamenti
			WHERE EXISTS (SELECT 1 FROM dbo.tblSessioni e WHERE e.Id = @IdSessione AND NULLIF(e.IdAzienda, REPLICATE('0', 16)) IS NOT NULL)
			GROUP BY
				n.Mese,
				n.Nome
			ORDER BY n.Mese;
		ELSE IF @Raggruppamento = 'S' AND @Tipo = 'C'
			SELECT TOP (@MaxRighe + 1)
				[Cliente] = ISNULL(s.NomeCompleto, '(Senza cliente)'),
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Documenti] = COUNT(*),
				[Imponibile] = SUM(f.Imponibile),
				[IVA] = SUM(f.Iva),
				[Totale] = SUM(f.Totale)
			FROM
				@fatture f
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			GROUP BY
				s.Id,
				s.NomeCompleto,
				s.PartitaIva,
				s.CodiceFiscale
			ORDER BY
				SUM(f.Imponibile) DESC,
				s.NomeCompleto,
				s.Id;
		ELSE IF @Raggruppamento = 'S'
			SELECT TOP (@MaxRighe + 1)
				[Fornitore] = ISNULL(s.NomeCompleto, '(Senza fornitore)'),
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Documenti] = COUNT(*),
				[Imponibile] = SUM(f.Imponibile),
				[IVA] = SUM(f.Iva),
				[Totale] = SUM(f.Totale)
			FROM
				@fatture f
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			GROUP BY
				s.Id,
				s.NomeCompleto,
				s.PartitaIva,
				s.CodiceFiscale
			ORDER BY
				SUM(f.Imponibile) DESC,
				s.NomeCompleto,
				s.Id;
		ELSE
			SELECT TOP (@MaxRighe + 1)
				[Codice] = k.Codice,
				[Conto] = ISNULL(k.Nome, '(Senza conto)'),
				[Righe] = COUNT(*),
				[Imponibile] = SUM(f.Segno * CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2)))
			FROM
				@fatture f
				INNER JOIN dbo.tblFattureRighe r ON f.Id = r.IdFattura
				INNER JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				LEFT JOIN dbo.tblFattureConti k ON i.IdConto = k.Id
			GROUP BY
				k.Id,
				k.Codice,
				k.Nome
			ORDER BY
				IIF(k.Id IS NULL, 1, 0),
				k.Nome,
				k.Id;

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

GO

-- ===== 25. scadenze_serie_eseguite_da_eseguire - serie di scadenze gia' segnate Eseguito riportate a Da eseguire (tools/scadenze_serie_eseguite_da_eseguire.sql)
-- Scadenze ricorrenti: la serie non si esegue (S5.9, decisione dell'utente del 2026-11-24). Le occorrenze generate
-- hanno lo stato della serie: una serie segnata Eseguito rendeva eseguite anche le occorrenze future. La nuova regola
-- vale dai salvataggi successivi (uspScadenze_upd); questo script riporta a Da eseguire le serie gia' segnate Eseguito
-- (decisione dell'utente: le occorrenze passate tornano scadute e si segnano eseguite con la sola occorrenza o con
-- Segna eseguiti). Restano come sono le serie Annullate (annullare tutta la serie e' ammesso, come nei servizi) e le
-- occorrenze modificate, che sono scadenze a se'. Rieseguibile.
-- Eseguito su dev il 2026-11-24 (nessuna serie). NON ancora eseguito in produzione.

SET NOCOUNT ON;

-- Prima: le serie che cambiano
SELECT
	Dominio = d.Nome,
	Calendario = c.Nome,
	SerieDal = e.[Data],
	Descrizione = e.Avviso,
	e.Id
FROM
	dbo.tblScadenze s
	INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
	INNER JOIN dbo.tblRicorrenze r ON r.Id = e.Id
	INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
	INNER JOIN dbo.tblSedi sd ON c.IdSede = sd.Id
	INNER JOIN dbo.tblSediInterne i ON sd.IdAziendaInterna = i.Id
	INNER JOIN dbo.tblDomini d ON i.IdDominio = d.Id
WHERE
	e.IdStato = 'E'
	AND e.Lock = 0
	AND NOT EXISTS (SELECT 1 FROM dbo.tblRicorrenzeEccezioni x WHERE x.IdEvento = e.Id)
ORDER BY d.Nome, c.Nome, e.[Data];

UPDATE e
SET IdStato = 'D'
FROM
	dbo.tblScadenze s
	INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
	INNER JOIN dbo.tblRicorrenze r ON r.Id = e.Id
WHERE
	e.IdStato = 'E'
	AND e.Lock = 0
	AND NOT EXISTS (SELECT 1 FROM dbo.tblRicorrenzeEccezioni x WHERE x.IdEvento = e.Id);

SELECT SerieRiportateDaEseguire = @@ROWCOUNT;
GO

GO

-- ===== Verifica
SELECT o.name, o.type_desc, o.modify_date, m.uses_quoted_identifier
FROM
	sys.objects o
	INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (N'ufnTipi_get_ProprietaVoci_List', N'ufnEventi_get_ProprietaValori_List', N'ufnEventi_get_ProprietaObbligatoriaMancante', N'ufnEventi_get_TipoProprieta', N'uspTipi_del', N'uspTipi_ins_Proprieta', N'uspTipi_get_Proprieta_List', N'uspTipi_del_Proprieta', N'uspTipi_upd_ProprietaObbligatorio', N'uspTipi_upd_ProprietaAttivo', N'uspTipi_upd_ProprietaVoci', N'uspScadenze_upd', N'uspServizi_upd', N'uspServiziAssegnati_upd', N'uspServizi_get_Stampa_Proprieta', N'uspServiziAssegnati_get_Bacheca_List', N'uspSYS_del_SedeInternaCascade', N'uspSYS_del_SedeEsternaCascade', N'uspServizi_upd_Eseguiti', N'uspScadenze_upd_Eseguite', N'uspFatture_get_Fatturato')
ORDER BY o.name;

SELECT 'Oggetti installati (21)' AS Oggetto,
	IIF((SELECT COUNT(*) FROM sys.objects WHERE name IN (N'ufnTipi_get_ProprietaVoci_List', N'ufnEventi_get_ProprietaValori_List', N'ufnEventi_get_ProprietaObbligatoriaMancante', N'ufnEventi_get_TipoProprieta', N'uspTipi_del', N'uspTipi_ins_Proprieta', N'uspTipi_get_Proprieta_List', N'uspTipi_del_Proprieta', N'uspTipi_upd_ProprietaObbligatorio', N'uspTipi_upd_ProprietaAttivo', N'uspTipi_upd_ProprietaVoci', N'uspScadenze_upd', N'uspServizi_upd', N'uspServiziAssegnati_upd', N'uspServizi_get_Stampa_Proprieta', N'uspServiziAssegnati_get_Bacheca_List', N'uspSYS_del_SedeInternaCascade', N'uspSYS_del_SedeEsternaCascade', N'uspServizi_upd_Eseguiti', N'uspScadenze_upd_Eseguite', N'uspFatture_get_Fatturato')) = 21, 'ok', 'DA CONTROLLARE') AS Esito
UNION ALL
SELECT 'Colonna tblTipiProprieta.Obbligatorio',
	IIF(COL_LENGTH('dbo.tblTipiProprieta', 'Obbligatorio') IS NOT NULL, 'ok', 'DA CONTROLLARE')
UNION ALL
SELECT 'Colonna tblTipiProprieta.Attivo',
	IIF(COL_LENGTH('dbo.tblTipiProprieta', 'Attivo') IS NOT NULL, 'ok', 'DA CONTROLLARE')
UNION ALL
SELECT 'Tabella tblTipiProprietaVoci',
	IIF(OBJECT_ID('dbo.tblTipiProprietaVoci', 'U') IS NOT NULL, 'ok', 'DA CONTROLLARE')
UNION ALL
SELECT 'Tipi di campo (5, con i nomi per l''utente)',
	IIF((SELECT COUNT(*) FROM dbo.tblTipiDati WHERE Id IN ('B', 'D', 'I', 'L', 'S') AND Nome IN (N'Casella s' + NCHAR(236) + N'/no', N'Data', N'Numero', N'Elenco a scelta', N'Testo')) = 5, 'ok', 'DA CONTROLLARE')
UNION ALL
SELECT 'Posti dei campi (20 per tipo di campo)',
	IIF((SELECT COUNT(*) FROM dbo.tblProprieta WHERE IdTipoDato IN ('B', 'D', 'I', 'L', 'S')) = 100, 'ok', 'DA CONTROLLARE')
UNION ALL
SELECT 'Serie di scadenze ancora eseguite (0)',
	IIF((SELECT COUNT(*)
		FROM
			dbo.tblScadenze s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblRicorrenze r ON r.Id = e.Id
		WHERE
			e.IdStato = 'E'
			AND e.Lock = 0
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRicorrenzeEccezioni x WHERE x.IdEvento = e.Id)) = 0, 'ok', 'DA CONTROLLARE');
GO