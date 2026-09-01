/*
	Deploy produzione - 2026-09-01 - Fix formattazione (righe vuote raddoppiate)

	Il precedente bundle (deploy_produzione_2026-09-01_rentri_sincronizzata_campo.sql)
	aveva un bug nello script di generazione: applicava una conversione CRLF due volte
	su contenuto gia' CRLF, raddoppiando ogni \r\n in \r\r\n - visibile in SSMS come
	una riga vuota extra dopo ogni riga di codice. La tabella non ne risente (nessun
	testo "definizione" per una tabella), ma le 2 funzioni schema-bound e la SP si'
	(il loro corpo e' salvato come testo in sys.sql_modules).

	Questo script NON tocca la tabella (gia' corretta dal deploy precedente) - si limita
	a riscrivere il testo di questi 3 oggetti con CREATE OR ALTER, senza bisogno di
	droppare prima le FK/la tabella: lo schema referenziato non cambia, solo la
	formattazione del testo salvato.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-01_fix_formattazione.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore]
(
	@Id CHAR(16),
	@Quantita DECIMAL(18, 2),
	@RegistrazioneData DATE,
	@RegistrazioneNumero INT,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@NoParametri BIT = 0
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	-- FIX: Quantita e IdUnitaMisura spostate da tblRifiutiRegistrazioni (r/p2) a tblRifiutiMovimenti (m/mp2)
	DECLARE @TotaleDisponibile DECIMAL(38, 2);
	SELECT
		@TotaleDisponibile =
			ISNULL(SUM(
				CONVERT(DECIMAL(38, 2), m.Quantita)
				+ lp.QuantitaAssegnataCorrente
				- ISNULL(qa.QuantitaAssociataTotale, 0)
			), 0)
	FROM
	(
		SELECT
			l.Id,
			SUM(CONVERT(DECIMAL(38, 2), l.Quantita)) AS QuantitaAssegnataCorrente
		FROM dbo.tblRifiutiRegistrazioniRelazioni l
		WHERE l.IdParent = @Id
		GROUP BY l.Id
	) lp
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON r.Id = lp.Id
		INNER JOIN dbo.tblRifiutiMovimenti m ON m.Id = r.IdMovimento
		INNER JOIN dbo.tblRifiutiRegistrazioni rp ON rp.Id = @Id
		INNER JOIN dbo.tblRifiutiMovimenti mp ON mp.Id = rp.IdMovimento
		OUTER APPLY (
			SELECT
				SUM(CONVERT(DECIMAL(38, 2), l2.Quantita)) AS QuantitaAssociataTotale
			FROM dbo.tblRifiutiRegistrazioniRelazioni l2
			INNER JOIN dbo.tblRifiutiRegistrazioni p2 ON p2.Id = l2.IdParent
			INNER JOIN dbo.tblRifiutiMovimenti mp2 ON mp2.Id = p2.IdMovimento
			WHERE
				l2.Id = lp.Id
				AND p2.Lock < 2
				AND mp2.Quantita > 0
		) qa
	WHERE
		r.Lock = 0
		AND
			(
			@NoParametri = 1
			OR
				(
					(
					r.[Data] < @RegistrazioneData
					OR
						(
						r.[Data] = @RegistrazioneData
						AND r.Numero < @RegistrazioneNumero
						)
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR m.IdEer = @IdEer
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR m.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR m.IdUnitaMisura = @IdUnitaMisura
					)
				)
			);
	RETURN CASE
		WHEN @Quantita > ISNULL(@TotaleDisponibile, 0) THEN 1
		ELSE 0
	END;
END;
GO

--------------------------------------------------------------------------------
-- 2) dbo.ufnRifiutiRegistrazioni_get_UltimoNumero
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_UltimoNumero]
(
	@IdRegistro CHAR(16),
	@Data DATE
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @PrimoGiornoAnno DATE = DATEFROMPARTS(YEAR(@Data), 1, 1);

	RETURN
	(
		SELECT ISNULL(MAX(r.Numero), 0)
		FROM dbo.tblRifiutiMovimenti m
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
		WHERE
			m.IdRegistro = @IdRegistro
			AND r.Data >= @PrimoGiornoAnno
			AND r.Data <= @Data
			AND r.Lock < 2
	);
END;
GO

--------------------------------------------------------------------------------
-- 3) dbo.uspRentriRegistrazioni_upd_Sincronizza
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Sincronizza in blocco un elenco di registrazioni con un dato già presente su RENTRI ma non
-- ancora confermato lato app (invio asincrono: RENTRI ha ricevuto/elaborato le registrazioni
-- ma la conferma non è mai arrivata/stata scritta sull'app, es. per un problema di rete o un
-- crash durante l'attesa). Usata da Rifiuti/Registrazioni/Index (checkbox "sincronizza" in
-- modale 2) dopo un confronto con l'elenco reale restituito da RENTRI - non chiamata
-- direttamente dall'utente, nessuna registrazione "nuova" viene mai creata qui, solo
-- aggiornati RentriIdentificativo/RentriData su righe già esistenti e mai confermate prima.
-- RentriSincronizzata = 1 marca esplicitamente che la conferma è arrivata da questa
-- sincronizzazione e non da un invio normale, per tracciabilità.
-- @Registrazioni: JSON array [{numero, anno, identificativo}, ...]. @RentriData catturato
-- una volta sola per l'intero blocco (stesso pattern di 1_0_rentri..uspRegistrazioni_upd_ByRegistrazioni,
-- non per singola riga). Comportamento best-effort: una riga del JSON senza corrispondenza
-- (già sincronizzata, Lock diverso da 0, ecc.) viene semplicemente saltata, non blocca le
-- altre - il chiamante ha già verificato l'elenco momenti prima, un singolo mancato match
-- non deve interrompere il resto del blocco. Ritorna il conteggio delle righe aggiornate.
-- Rinominata da uspRentriRegistrazioni_upd (2026-09-01) per distinguerla chiaramente da un
-- generico update della registrazione - lega nome SP, checkbox "sincronizza" e campo
-- RentriSincronizzata. Passata da chiamata singola a blocco JSON lo stesso giorno, per
-- evitare N round-trip separati quando ci sono più registrazioni da sincronizzare.
-- exec dbo.uspRentriRegistrazioni_upd_Sincronizza @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Registrazioni='[{"numero":3,"anno":2026,"identificativo":"..."}]', @RentriData='2026-08-15 10:30:00'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_Sincronizza]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Registrazioni NVARCHAR(MAX) = NULL,
	@RentriData DATETIME2(0) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @sincronizzate INT = 0;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL OR @IdSessione IS NULL OR @Registrazioni IS NULL OR @RentriData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri mancanti';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Numero INT, @Anno INT, @Identificativo VARCHAR(50);

		DECLARE c CURSOR LOCAL FAST_FORWARD FOR
		SELECT Numero, Anno, Identificativo
		FROM OPENJSON(@Registrazioni) WITH (
			Numero INT '$.numero',
			Anno INT '$.anno',
			Identificativo VARCHAR(50) '$.identificativo'
		);

		OPEN c;
		FETCH c INTO @Numero, @Anno, @Identificativo;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			UPDATE r
			SET
				RentriIdentificativo = @Identificativo,
				RentriData = @RentriData,
				RentriSincronizzata = 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				m.IdRegistro = @IdRegistro
				AND r.Numero = @Numero
				AND YEAR(r.[Data]) = @Anno
				AND r.Lock = 0
				AND r.RentriIdentificativo IS NULL
				AND r.RentriData IS NULL;

			SET @sincronizzate = @sincronizzate + @@ROWCOUNT;

			FETCH c INTO @Numero, @Anno, @Identificativo;
		END

		CLOSE c;
		DEALLOCATE c;

	END TRY
	BEGIN CATCH
		IF CURSOR_STATUS('local', 'c') >= -1
		BEGIN
			CLOSE c;
			DEALLOCATE c;
		END;
		THROW;
	END CATCH

	BRANCH_END:

	SET NOCOUNT, XACT_ABORT OFF;

	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Sincronizzate = @sincronizzate;

END
GO
