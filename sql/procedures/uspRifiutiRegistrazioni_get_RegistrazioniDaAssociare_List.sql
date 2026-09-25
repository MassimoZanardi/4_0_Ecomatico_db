SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
			v.IdUnitaMisura,
			Quantita = ISNULL(a.Quantita, 0),
			QuantitaResidua = v.Quantita - ISNULL(a.Quantita, 0),
			EerNome = e.Nome,
			StatoFisicoNome = s.Nome,
			Anno = YEAR(r.[Data])
		INTO #cte
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN (
				SELECT
					l.Id,
					Quantita = SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
				WHERE
					p.Lock < 2
					-- Valori effettivi (viewRifiutiRegistrazioniEffettive): uno scarico annullato ha Quantita = 0,
					-- le sue relazioni restano per la stampa ma non consumano piu' il carico
					AND vp.Quantita > 0
				GROUP BY l.Id
			) a ON r.Id = a.Id
					LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
					LEFT JOIN dbo.tblRifiutiStatiFisici s ON v.IdStatoFisico = s.Id
		WHERE
			r.Lock = 0
			AND m.IdRegistro = @IdRegistro
			AND
				(
				@idOperazione IN ('M', 'K')
				OR v.IdEer = @IdEer
				)
			AND
				(
				@idOperazione IN ('M', 'K')
				OR v.IdStatoFisico = @IdStatoFisico
				)
			AND
				(
				@idOperazione IN ('M', 'K')
				OR v.IdUnitaMisura = @IdUnitaMisura
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
			AND (v.Quantita - ISNULL(a.Quantita, 0)) > 0
			AND r.Id NOT IN ( SELECT Id FROM dbo.tblRifiutiRegistrazioniRelazioni WHERE IdParent = @IdParent )
			-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
			-- proprie: non deve mai comparire come candidata da associare
			AND v.IsRettifica = 0;

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
