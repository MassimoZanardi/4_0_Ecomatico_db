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
		ORDER BY [Data], Numero
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