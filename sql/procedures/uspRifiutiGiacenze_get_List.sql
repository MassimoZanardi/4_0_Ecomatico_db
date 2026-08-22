CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

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
			Id = e.Id,
			Tipo = 'Rifiuto prodotto',
			Nome = e.Nome,
			Descrizione = e.Descrizione,
			StatoFisico = s.Nome,
			Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
			GiacenzaGiorni = DATEDIFF(DAY, MIN(r.[Data]), @Data),
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
			e.Id, e.Nome, s.Nome, e.Descrizione

		UNION ALL

		SELECT
			Id = e.Id,
			Tipo = 'Rifiuto trattato',
			Nome = e.Nome,
			Descrizione = e.Descrizione,
			StatoFisico = s.Nome,
			Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
			GiacenzaGiorni = DATEDIFF(DAY, MIN(r.[Data]), @Data),
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
			e.Id, e.Nome, s.Nome, e.Descrizione

		UNION ALL

		SELECT
			Id = e.Id,
			Tipo = 'Materiale prodotto',
			Nome = e.Nome,
			Descrizione = e.Nome,
			StatoFisico = 'nd',
			Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
			GiacenzaGiorni = DATEDIFF(DAY, MIN(r.[Data]), @Data),
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
			e.Id, e.Nome

		ORDER BY Nome, StatoFisico, Tipo
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
		THROW 50001, @returnMessage, 1;
	END
END;
