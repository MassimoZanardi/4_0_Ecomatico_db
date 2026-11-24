/*
	Deploy produzione 2026-11-24 - Campi aggiuntivi dei tipi di scadenza e di servizio

	Da eseguire DOPO deploy_produzione_2026-11-23c_sovrapposizioni_bacheca.sql (gia' in produzione, tag deployed-prod
	fae0347): contiene i commit del repo DB e7390c5 e 77808d6. Solo 4_0_ecomatico. Una colonna nuova con default
	(aggiunta solo se manca), i nomi dei quattro tipi di campo, tre funzioni e nove stored procedure CREATE OR ALTER:
	lo script e' rieseguibile. Nessun dato dei clienti modificato (la colonna nasce a 0 = facoltativo). Da eseguire
	da SSMS sul database 4_0_ecomatico (o con sqlcmd -f 65001 -I).

	Prima il DB, poi l'app (commit 4.0 d4594ee o successivo). L'app precedente funziona con le SP nuove: i parametri
	in piu' hanno un default.

	1. tblTipiProprieta.Obbligatorio (BIT, default 0): campo obbligatorio per segnare come eseguito (S3.6).
	2. tblTipiDati: nomi per l'utente (Testo, Numero, Data, Casella si/no) (S3.3).
	3-5. ufnEventi_get_ProprietaValori_List, ufnEventi_get_ProprietaObbligatoriaMancante (nuova),
	     ufnEventi_get_TipoProprieta: Numero con i decimali (S3.4.1), campi obbligatori (S3.6).
	6-9. uspTipi_del, uspTipi_ins_Proprieta, uspTipi_get_Proprieta_List, uspTipi_upd_ProprietaObbligatorio (nuova).
	10-12. uspScadenze_upd, uspServizi_upd, uspServiziAssegnati_upd: controllo dei campi obbligatori con Eseguito.
	13-14. uspServizi_get_Stampa_Proprieta, uspServiziAssegnati_get_Bacheca_List.

	In fondo la verifica: funzioni e procedure con data di modifica e QUOTED_IDENTIFIER, colonna e nomi dei tipi.
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

-- ===== 3. ufnEventi_get_ProprietaValori_List (sql/functions/ufnEventi_get_ProprietaValori_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Valori delle proprietà di un evento inviati dalla scheda (JSON [{"Id":"I00","Valore":"12"}, ...]), controllati e
-- normalizzati per tipo di dato. Restituisce solo le proprietà del tipo @IdTipo presenti nel JSON (le altre sono
-- ignorate). Valore NULL = da togliere; Errore valorizzato = valore non ammesso (la SP chiamante lo restituisce).
-- Formati salvati: Sì/No 'true'/'false', Numero con il punto e al massimo 4 decimali (dal 2026-11-23, prima solo intero;
-- dalla scheda arriva con la virgola), Data 'yyyy-MM-dd', Testo fino a 50 caratteri.
-- Usata da uspScadenze_upd, uspServizi_upd, uspServiziAssegnati_upd
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_ProprietaValori_List]
(
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
		CROSS APPLY (
			SELECT Valore = CASE p.IdTipoDato
				WHEN 'B' THEN IIF(LOWER(j.Valore) IN ('true', 'false'), CAST(LOWER(j.Valore) AS VARCHAR(50)), NULL)
				WHEN 'I' THEN IIF(n.Numero IS NOT NULL AND n.Numero = ROUND(n.Numero, 4), FORMAT(CAST(n.Numero AS DECIMAL(18, 4)), '0.####', 'en-US'), NULL)
				WHEN 'D' THEN CONVERT(VARCHAR(50), TRY_CONVERT(DATE, j.Valore, 23), 23)
				ELSE IIF(LEN(j.Valore) <= 50, CAST(j.Valore AS VARCHAR(50)), NULL)
			END
		) v
	WHERE t.Id = @IdTipo
);
GO

GO

-- ===== 4. ufnEventi_get_ProprietaObbligatoriaMancante (sql/functions/ufnEventi_get_ProprietaObbligatoriaMancante.sql)
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
-- quello gia' salvato sull'evento. Una casella si/no obbligatoria deve essere spuntata ('true').
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
		Messaggio = 'Per segnare come eseguito ' + IIF(p.IdTipoDato = 'B', 'spuntare', 'compilare') + ' il campo "' + t.Nome + '"'
	FROM
		dbo.tblTipiProprieta t
		INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
		OUTER APPLY (
			SELECT TOP (1) v.IdProprieta, v.Valore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdTipo, @Proprieta) v
			WHERE v.IdProprieta = t.IdProprieta
		) j
		LEFT JOIN dbo.tblEventiProprieta e ON e.Id = @IdEvento AND e.IdProprieta = t.IdProprieta
		CROSS APPLY (
			SELECT Valore = IIF(j.IdProprieta IS NOT NULL, j.Valore, NULLIF(LTRIM(RTRIM(e.Valore)), ''))
		) x
	WHERE
		t.Id = @IdTipo
		AND t.Lock = 0
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

-- ===== 5. ufnEventi_get_TipoProprieta (sql/functions/ufnEventi_get_TipoProprieta.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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
			-- Numero salvato con il punto, nella scheda con la virgola
			Valore = CASE p.IdTipoDato
				WHEN 'B' THEN ISNULL(e.Valore, 'false')
				WHEN 'I' THEN REPLACE(ISNULL(e.Valore, ''), '.', ',')
				ELSE ISNULL(e.Valore, '')
			END
		FROM
			dbo.tblTipiProprieta t
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta e ON t.IdProprieta = e.IdProprieta
											   AND e.Id = @Id
		WHERE
			t.Id = @IdTipo
			AND t.Lock = 0
		ORDER BY
			t.Pos
		FOR JSON PATH
	);
END;

GO

-- ===== 6. uspTipi_del (sql/procedures/uspTipi_del.sql)
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

-- ===== 7. uspTipi_ins_Proprieta (sql/procedures/uspTipi_ins_Proprieta.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspTipi_ins_Proprieta]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipoDato CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Obbligatorio BIT = 0
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
			SET @returnMessage = 'Sono già presenti 5 campi di questo tipo, il massimo consentito';
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

-- ===== 8. uspTipi_get_Proprieta_List (sql/procedures/uspTipi_get_Proprieta_List.sql)
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
			t.Obbligatorio
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

-- ===== 9. uspTipi_upd_ProprietaObbligatorio (sql/procedures/uspTipi_upd_ProprietaObbligatorio.sql)
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

-- ===== 10. uspScadenze_upd (sql/procedures/uspScadenze_upd.sql)
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
			FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
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
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
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

-- ===== 11. uspServizi_upd (sql/procedures/uspServizi_upd.sql)
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
			FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
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
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
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

-- ===== 12. uspServiziAssegnati_upd (sql/procedures/uspServiziAssegnati_upd.sql)
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
			FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
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
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@idTipo, @Proprieta)
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

-- ===== 13. uspServizi_get_Stampa_Proprieta (sql/procedures/uspServizi_get_Stampa_Proprieta.sql)
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
		WHERE s.Id = @Id
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

-- ===== 14. uspServiziAssegnati_get_Bacheca_List (sql/procedures/uspServiziAssegnati_get_Bacheca_List.sql)
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
					AND IIF(EXISTS (SELECT 1 FROM dbo.tblTipiProprieta o WHERE o.Id = s.IdTipo AND o.Lock = 0 AND o.Obbligatorio = 1),
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

-- ===== Verifica
SELECT o.name, o.type_desc, o.modify_date, m.uses_quoted_identifier
FROM
	sys.objects o
	INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (N'ufnEventi_get_ProprietaValori_List', N'ufnEventi_get_ProprietaObbligatoriaMancante', N'ufnEventi_get_TipoProprieta', N'uspTipi_del', N'uspTipi_ins_Proprieta', N'uspTipi_get_Proprieta_List', N'uspTipi_upd_ProprietaObbligatorio', N'uspScadenze_upd', N'uspServizi_upd', N'uspServiziAssegnati_upd', N'uspServizi_get_Stampa_Proprieta', N'uspServiziAssegnati_get_Bacheca_List')
ORDER BY o.name;

SELECT 'Colonna tblTipiProprieta.Obbligatorio' AS Oggetto,
	IIF(COL_LENGTH('dbo.tblTipiProprieta', 'Obbligatorio') IS NOT NULL, 'ok', 'DA CONTROLLARE') AS Esito
UNION ALL
SELECT 'Nomi dei tipi di campo',
	IIF((SELECT COUNT(*) FROM dbo.tblTipiDati WHERE Id IN ('B', 'D', 'I', 'S') AND Nome IN (N'Casella sì/no', N'Data', N'Numero', N'Testo')) = 4, 'ok', 'DA CONTROLLARE');
GO