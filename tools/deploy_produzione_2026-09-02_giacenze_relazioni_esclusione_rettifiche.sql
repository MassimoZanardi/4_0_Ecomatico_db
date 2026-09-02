/*
	Deploy produzione - 2026-09-02 - Esclusione rettifiche/annullamenti da giacenze e relazioni carico/scarico

	Le registrazioni di rettifica (correzione o annullamento, tblRentriRegistrazioniRettifiche) sono
	"registrazioni meta" che documentano una correzione/annullamento gia' trasmesso al RENTRI, non
	movimenti reali di rifiuto. Fino a questo deploy, una volta confermate (Lock=0) venivano contate
	come un vero carico/scarico dalle SP di giacenza, e potevano comparire come candidate selezionabili
	nelle relazioni di carico/scarico di ALTRE registrazioni (il vincolo "una rettifica non ha mai
	relazioni proprie" era gia' garantito lato INSERT, ma nessuna SP impediva che un'altra registrazione
	selezionasse una rettifica come propria fonte/destinazione).

	Oggetti inclusi (tutti con lo stesso filtro aggiuntivo
	"AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)"):
	1. dbo.uspRifiutiGiacenze_get_List (3 rami: Rifiuto prodotto/trattato, Materiale prodotto)
	2. dbo.uspRifiutiGiacenze_get_Carichi_List (stessi 3 rami, dettaglio dei singoli carichi)
	3. dbo.uspRifiutiGiacenze_get_Quantita (giacenza puntuale Registro+Eer+StatoFisico)
	4. dbo.uspRifiutiRegistrazioni_get_RegistrazioniDaAssociare_List (select list "Registrazioni da associare")
	5. dbo.uspRifiutiRegistrazioni_ins_RelazioniTutte (bulk "associa tutte" - candidate + guardia su @IdParent)
	6. dbo.uspRifiutiRegistrazioni_ins_Relazione (difesa in profondita' sull'INSERT diretto, sia su @Id che @IdParent)

	Testato con dati reali su dev (dominio test1.net, dati di test ripuliti a fine sessione): confermata
	una rettifica di correzione su una registrazione con quantita' in giacenza -> giacenza/carichi/quantita
	puntuale invariati (la rettifica non compare mai), candidate list la esclude, insert diretto della
	relazione bloccato con messaggio esplicito.
*/

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('E', 'M', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve valere ''E'', ''M'' oppure ''T''';
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

		-- Titolarità: prima non esisteva alcun controllo che @IdRegistro appartenesse
		-- all'azienda della sessione — chiunque conoscesse un Id di registro poteva
		-- leggere le giacenze di un'altra azienda.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;
		IF @Data IS NULL SET @Data = GETDATE();

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- @Vista IN ('E', 'M'): solo righe Rifiuto prodotto/trattato, raggruppate per EER + stato fisico.
		-- @Vista = 'M': solo righe Materiale prodotto, raggruppate per materiale.
		-- @Vista = 'T': tutti i tipi, raggruppati per combinazione esatta di etichette (r.Etichette,
		-- JSON canonico già mantenuto da uspEtichette_upd/_del su tblRifiutiRegistrazioni.Etichette;
		-- NULL = bucket "Nessuna etichetta"). Le tre modalità condividono la stessa query: i rami
		-- P/T (Rifiuto prodotto/trattato) sono attivi per @Vista IN ('E','T'), il ramo M (Materiale)
		-- per @Vista IN ('M','T'); la chiave di GROUP BY usa CASE su @Vista, così la dimensione non
		-- richiesta collassa a una costante per ogni riga e non spezza ulteriormente i gruppi.
		-- StatoValore/StatoDescrizione (semaforo anzianità giacenza) sono derivati in un SELECT
		-- esterno alla CTE Giacenze, per non ripetere tre volte l'espressione DATEDIFF.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		Giacenze AS (
			SELECT
				TipoCodice = 'P',
				Tipo = 'Rifiuto prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR m.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'T',
				Tipo = 'Rifiuto trattato',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'S'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR m.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'M',
				Tipo = 'Materiale prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				IdStatoFisico = NULL,
				StatoFisico = CASE WHEN @Vista IN ('E', 'M') THEN 'nd' END,
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('M', 'T')
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0
		)
		SELECT
			TipoCodice, Tipo, Id, Nome, Descrizione, IdStatoFisico, StatoFisico, Etichette,
			Quantita, GiacenzaGiorni, MovimentiNumero,
			StatoValore = CASE
				WHEN GiacenzaGiorni > 365 THEN 2
				WHEN GiacenzaGiorni > 30  THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN GiacenzaGiorni > 365 THEN 'In giacenza da oltre un anno (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni > 30  THEN 'In giacenza da oltre 30 giorni (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni = 1   THEN 'In giacenza da 1 giorno'
				ELSE 'In giacenza da ' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni'
			END
		FROM Giacenze
		ORDER BY
			GiacenzaGiorni DESC,
			Nome,
			StatoFisico,
			Tipo,
			Etichette
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_Carichi_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Tipo CHAR(1) = NULL,
	@Id CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Etichette VARCHAR(2000) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @Etichette = NULLIF(LTRIM(RTRIM(@Etichette)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('E', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve valere ''E'' oppure ''T''';
			GOTO BRANCH_END;
		END
		-- @Tipo = NULL: vista "senza filtri", elenca tutti i carichi in giacenza a prescindere
		-- da tipo/EER/etichetta (raggiungibile direttamente dal menu Azioni). Se invece @Tipo è
		-- valorizzato (drill-down da una riga EER o Etichette), deve essere uno dei tre codici noti.
		IF @Tipo IS NOT NULL AND @Tipo NOT IN ('P', 'T', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve valere ''P'', ''T'' oppure ''M''';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NOT NULL AND @Vista = 'E' AND @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto con @Vista = ''E''';
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

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;
		IF @Data IS NULL SET @Data = GETDATE();

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Dettaglio dei singoli carichi (registrazioni) che compongono una riga aggregata
		-- di uspRifiutiGiacenze_get_List: stessa logica di quantità residua (Quantita -
		-- QuantitaAssegnata), stesse tre casistiche (Rifiuto prodotto/trattato, Materiale
		-- prodotto), ma senza aggregazione e filtrate sul gruppo scelto da chi ha cliccato
		-- la riga (@Vista = 'E' -> @Id [+@IdStatoFisico], @Vista = 'T' -> @Etichette).
		-- RowsCount e StatoValore/StatoDescrizione (semaforo anzianità giacenza) sono calcolati
		-- nel SELECT esterno alla CTE Carichi, non dentro ciascun ramo: altrimenti con @Tipo =
		-- NULL (nessun filtro, tutti i rami attivi) RowsCount riporterebbe solo il conteggio
		-- parziale del proprio ramo invece del totale.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		Carichi AS (
			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = m.IdStatoFisico,
				StatoFisico = s.Nome,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'P')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR (e.Id = @Id AND m.IdStatoFisico = @IdStatoFisico))
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR e.Id LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)

			UNION ALL

			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = m.IdStatoFisico,
				StatoFisico = s.Nome,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'T')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'S'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR (ISNULL(e.Id, '') = ISNULL(@Id, '') AND ISNULL(m.IdStatoFisico, '') = ISNULL(@IdStatoFisico, '')))
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR ISNULL(e.Id, '') LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)

			UNION ALL

			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = NULL,
				StatoFisico = NULL,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'M')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR e.Id = @Id)
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
		)
		SELECT
			Id, Numero, [Data], IdEer, EerNome, IdStatoFisico, StatoFisico, Etichette,
			IdUnitaMisura, Quantita, QuantitaAssegnata, QuantitaResidua, GiacenzaGiorni,
			StatoValore = CASE
				WHEN GiacenzaGiorni > 365 THEN 2
				WHEN GiacenzaGiorni > 30  THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN GiacenzaGiorni > 365 THEN 'In giacenza da oltre un anno (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni > 30  THEN 'In giacenza da oltre 30 giorni (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni = 1   THEN 'In giacenza da 1 giorno'
				ELSE 'In giacenza da ' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni'
			END,
			RowsCount = COUNT(*) OVER ()
		FROM Carichi
		ORDER BY GiacenzaGiorni DESC, EerNome, Numero
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_Quantita]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Data DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @Giacenza DECIMAL(18, 2);

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdEer IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEer non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
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

		-- Titolarità: stesso controllo di uspRifiutiGiacenze_get_List/_get_Carichi_List.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @Data = ISNULL(@Data, GETDATE());

		-- Stessa logica di quantità residua di uspRifiutiGiacenze_get_List/_get_Carichi_List
		-- (Quantita - QuantitaAssegnata), ma senza raggruppamento/paginazione: un unico SUM
		-- per la combinazione Registro+Eer+StatoFisico richiesta. I due rami "Rifiuto prodotto"
		-- (IdOperazione <> 'R', Operazione = 'C') e "Rifiuto trattato" (IdOperazione = 'R',
		-- Operazione = 'S') sono mutuamente esclusivi sullo stesso record, quindi si possono
		-- unire in un solo OR invece di due UNION ALL separate.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		)
		SELECT
			@Giacenza = SUM(m.Quantita - ISNULL(a.Quantita, 0))
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
		WHERE
			r.Lock = 0
			AND r.[Data] <= @Data
			AND m.IdRegistro = @IdRegistro
			AND m.IdEer = @IdEer
			AND m.IdStatoFisico = @IdStatoFisico
			AND m.Quantita > 0
			AND (
				(ISNULL(m.IdOperazione, '') <> 'R' AND o.Operazione = 'C')
				OR (m.IdOperazione = 'R' AND o.Operazione = 'S')
			)
			AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
			-- Una registrazione di rettifica o annullamento non è un movimento reale di
			-- carico/scarico: non deve mai contribuire alla giacenza
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id);

		SELECT rtn = ISNULL(@Giacenza, 0);

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

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_RegistrazioniDaAssociare_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Legge l'operazione della registrazione padre FUORI dalla query principale
		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		-- Materializzazione unica del set "registrazioni da associare": evita di
		-- ricalcolare la stessa catena di join/aggregazioni due volte (una per il
		-- risultato principale, una per il NOT EXISTS del placeholder)
		SELECT
			Verso = 1,
			r.Id,
			r.Operazione,
			r.Numero,
			r.[Data],
			m.IdUnitaMisura,
			Quantita = ISNULL(a.Quantita, 0),
			QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
			EerNome = e.Nome,
			StatoFisicoNome = s.Nome,
			Anno = YEAR(r.[Data])
		INTO #cte
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN (
				SELECT
					l.Id,
					Quantita = SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
				WHERE
					p.Lock < 2
					AND mp.Quantita > 0
				GROUP BY l.Id
			) a ON r.Id = a.Id
					LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
					LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
		WHERE
			r.Lock = 0
			AND m.IdRegistro = @IdRegistro
			AND
				(
				@idOperazione IN ('M', 'K')
				OR m.IdEer = @IdEer
				)
			AND
				(
				@idOperazione IN ('M', 'K')
				OR m.IdStatoFisico = @IdStatoFisico
				)
			AND
				(
				@idOperazione IN ('M', 'K')
				OR m.IdUnitaMisura = @IdUnitaMisura
				)
			AND
				(
				r.[Data] < @Data
				OR
					(
					r.[Data] = @Data
					AND r.Numero < @Numero
					)
				)
			AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
			AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
			AND r.Id NOT IN ( SELECT Id FROM dbo.tblRifiutiRegistrazioniRelazioni WHERE IdParent = @IdParent )
			-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
			-- proprie: non deve mai comparire come candidata da associare
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id);

		CREATE UNIQUE CLUSTERED INDEX IX_cte_Anno_Numero ON #cte (Anno, Numero, Id);

		;WITH cteTotali AS (
			SELECT
				Operazione,
				Registrazioni = COUNT(*),
				Totali = IIF(Operazione = 'S', 'Scarichi ', 'Carichi ') +
					'da associare: ' + FORMAT(COUNT(*), 'N0', 'IT-it') +
					' | Tot. q.tà associata: ' + FORMAT(ISNULL(SUM(Quantita), 0), 'N2', 'IT-it') +
					' | Tot. q.tà residua: ' + FORMAT(ISNULL(SUM(QuantitaResidua), 0), 'N2', 'IT-it')
			FROM #cte
			GROUP BY Operazione
		)
		SELECT
			c.Verso, c.Id, c.Operazione, c.Numero, c.[Data],
			c.IdUnitaMisura, c.Quantita, c.QuantitaResidua,
			c.EerNome, c.StatoFisicoNome, c.Anno,
			t.Registrazioni, t.Totali
		FROM #cte c
		CROSS JOIN cteTotali t

		UNION ALL

		SELECT
			Verso = 1,
			Id = NULL,
			Operazione = NULL,
			Numero = 0,
			[Data] = '19000101',
			IdUnitaMisura = NULL,
			Quantita = 0,
			QuantitaResidua = 0,
			EerNome = NULL,
			StatoFisicoNome = NULL,
			Anno = 1900,
			Registrazioni = 0,
			Totali = IIF(r.Operazione = 'C', 'Scarichi da associare', 'Carichi da associare')
		FROM dbo.tblRifiutiRegistrazioni r
		WHERE
			r.Id = @IdParent
			AND NOT EXISTS (SELECT 1 FROM #cte)
		ORDER BY Anno, Numero
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_RelazioniTutte]
	@IdSessione CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Calcolata una sola volta e riusata nei due controlli titolarità sottostanti,
		-- invece di richiamare la function separatamente per ciascuno
		DECLARE @sedi TABLE (Id CHAR(16) PRIMARY KEY);
		INSERT @sedi (Id)
		SELECT Id
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione);

		IF (
			SELECT COUNT(DISTINCT g.Id)
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdParent
				AND (RentriIdentificativo IS NOT NULL OR RentriData IS NOT NULL)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie - difesa in profondità, la UI già nasconde la sezione per queste registrazioni
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni s
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;

		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		BEGIN TRANSACTION;

			--      QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0)
			INSERT dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			SELECT TOP(499 - @pos)
				r.Id,
				@IdParent,
				IIF(r.Operazione = 'C', 'S', 'C'),
				0,
				@pos + ROW_NUMBER() OVER (ORDER BY YEAR(r.[Data]), r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN (
					SELECT
						l.Id,
						Quantita = SUM(l.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
						INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
					WHERE
						p.Lock < 2
						AND mp.Quantita > 0
					GROUP BY l.Id
				) a ON r.Id = a.Id
			WHERE
				r.Lock = 0
				AND m.IdRegistro = @IdRegistro
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdEer = @IdEer
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdUnitaMisura = @IdUnitaMisura
					)
				AND
					(
					r.[Data] < @Data
					OR
						(
						r.[Data] = @Data
						AND r.Numero < @Numero
						)
					)
				AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
				AND m.Quantita - ISNULL(a.Quantita, 0) > 0 -- QuantitaResidua > 0
				AND NOT EXISTS ( SELECT 1 FROM dbo.tblRifiutiRegistrazioniRelazioni x WHERE x.Id = r.Id AND x.IdParent = @IdParent )
				-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
				-- proprie: non deve mai comparire come candidata da associare
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			ORDER BY YEAR(r.[Data]), r.Numero;

			SET @returnValue = @@ROWCOUNT;

			-- Imposta la registrazione nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;

		COMMIT TRANSACTION;

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

	SELECT ReturnValue = @returnValue;
END;

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Recupera l'operazione del padre e verifica che esista
		DECLARE @operazioneParent CHAR(1);
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT
			@operazioneParent = Operazione,
			@rentriIdentificativo = RentriIdentificativo,
			@rentriData = RentriData
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @IdParent;

		IF @operazioneParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione padre non trovata';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie (né come padre né come figlia) - difesa in profondità, la UI già la esclude
		-- dalle liste di selezione (uspRifiutiRegistrazioni_get_RegistrazioniDaAssociare_List)
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica IN (@Id, @IdParent))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		IF (
			SELECT COUNT(DISTINCT r.Id)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id IN (@Id, @IdParent)) < 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1) + 1
		FROM dbo.tblRifiutiRegistrazioniRelazioni s
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;
		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			VALUES
				(@Id, @IdParent, @operazioneParent, 0, @pos);

			-- Imposta la registrazione padre nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;

GO

