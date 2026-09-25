SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Giacenza (coerente con Rifiuti/Giacenze): Quantita = quanto c'è oggi nel lotto, cioè le
		-- quote di registrazioni M attive (Lock < 2: una registrazione eliminata mantiene le sue
		-- quote per un eventuale ripristino, ma non conta più) meno gli scarichi dei movimenti di
		-- magazzino confermati; solo le righe con giacenza > 0. GiacenzaGiorni = giorni dalla
		-- prima registrazione M del lotto. La capacità residua resta riferita alla produzione
		-- (QuantitaMax - quantità attribuita): il lotto EoW è una partita di produzione, gli
		-- scarichi non liberano capienza.
		IF @Vista = 'L'
		BEGIN
			SELECT
				l.Id,
				-- Lotto pieno: la produzione attribuita ha raggiunto la quantità massima
				StatoValore = CASE WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAttribuita, 0) >= l.QuantitaMax THEN 1 ELSE 0 END,
				StatoDescrizione = CASE WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAttribuita, 0) >= l.QuantitaMax THEN 'Lotto pieno: capacità esaurita' ELSE 'OK' END,
				l.Nome,
				MaterialeNome = m.Nome,
				SedeNome = s.Nome,
				l.QuantitaMax,
				QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
				Quantita = ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAttribuita, 0) END,
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWLotti l
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
				INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
				LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				OUTER APPLY (
					SELECT
						QuantitaAttribuita = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLottiRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						r.IdLotto = l.Id
						AND rr.Lock < 2
				) q
				OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblMagazziniMovimentiRigheEoWLotti rs
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						rs.IdLotto = l.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
				) sc
			WHERE
				l.Lock = 0
				AND (@IdSede IS NULL OR l.IdSede = @IdSede)
				AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
				AND ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) > 0
			ORDER BY l.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END
		ELSE
		BEGIN
			SELECT
				g.Id,
				StatoValore = 0,
				StatoDescrizione = 'OK',
				g.Nome,
				MaterialeNome = CAST(NULL AS VARCHAR(100)),
				SedeNome = s.Nome,
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
				Quantita = ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWMagazzini g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
				OUTER APPLY (
					SELECT
						QuantitaAttribuita = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni r ON r.IdLotto = l.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rr.Lock < 2
				) q
				OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoWLotti rs ON rs.IdLotto = l.Id
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
				) sc
			WHERE
				g.Lock = 0
				AND (@IdSede IS NULL OR g.IdSede = @IdSede)
				AND (@Search IS NULL OR g.Nome LIKE '%' + @Search + '%')
				AND ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) > 0
			ORDER BY g.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END

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
