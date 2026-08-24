CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E'
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');

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

		-- @Vista = 'E': raggruppa per EER/materiale + stato fisico (comportamento storico, invariato).
		-- @Vista = 'T': raggruppa per combinazione esatta di etichette (r.Etichette, JSON canonico
		-- già mantenuto da uspEtichette_upd/_del su tblRifiutiRegistrazioni.Etichette; NULL = bucket
		-- "Nessuna etichetta"). Le due modalità condividono la stessa query: la chiave di GROUP BY
		-- usa CASE su @Vista, così la dimensione non richiesta collassa a una costante per ogni riga
		-- e non spezza ulteriormente i gruppi.
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
				Id = MIN(CASE WHEN @Vista = 'E' THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista = 'E' THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista = 'E' THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista = 'E' THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista = 'E' THEN s.Nome END),
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
			GROUP BY
				CASE WHEN @Vista = 'E' THEN e.Id END,
				CASE WHEN @Vista = 'E' THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'T',
				Tipo = 'Rifiuto trattato',
				Id = MIN(CASE WHEN @Vista = 'E' THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista = 'E' THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista = 'E' THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista = 'E' THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista = 'E' THEN s.Nome END),
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
			GROUP BY
				CASE WHEN @Vista = 'E' THEN e.Id END,
				CASE WHEN @Vista = 'E' THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'M',
				Tipo = 'Materiale prodotto',
				Id = MIN(CASE WHEN @Vista = 'E' THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista = 'E' THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista = 'E' THEN e.Nome END),
				IdStatoFisico = NULL,
				StatoFisico = CASE WHEN @Vista = 'E' THEN 'nd' END,
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
			GROUP BY
				CASE WHEN @Vista = 'E' THEN e.Id END,
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
			Nome,
			StatoFisico,
			Tipo,
			Etichette
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

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