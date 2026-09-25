SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
			WHERE
				p.Lock = 0
				-- Valori effettivi (viewRifiutiRegistrazioniEffettive): uno scarico annullato ha Quantita = 0,
				-- le sue relazioni restano per la stampa ma non consumano piu' il carico
				AND vp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		-- Una registrazione Materiale non compare mai come Id (figlio) in tblRifiutiRegistrazioniRelazioni
		-- (blocco applicativo in uspRifiutiRegistrazioni_ins_Relazione/_ins_RelazioniTutte): l'unica causa
		-- di riduzione della sua giacenza è l'allocazione a un lotto EoW.
		QuantitaAllocataEoW AS (
			SELECT
				w.IdRegistrazione AS Id,
				Quantita = SUM(w.Quantita)
			FROM dbo.tblEoWLottiRifiutiRegistrazioni w
			GROUP BY w.IdRegistrazione
		),
		Giacenze AS (
			SELECT
				TipoCodice = 'P',
				Tipo = 'Rifiuto prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN v.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(v.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN v.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(v.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON v.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND v.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR v.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND v.IsRettifica = 0
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(v.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'T',
				Tipo = 'Rifiuto trattato',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN v.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(v.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN v.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(v.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON v.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND v.Quantita > 0
				AND o.Operazione = 'S'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR v.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND v.IsRettifica = 0
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(v.Quantita - ISNULL(a.Quantita, 0)) > 0

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
				Quantita = SUM(v.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN v.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(v.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAllocataEoW a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND v.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('M', 'T')
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND v.IsRettifica = 0
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(v.Quantita - ISNULL(a.Quantita, 0)) > 0
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