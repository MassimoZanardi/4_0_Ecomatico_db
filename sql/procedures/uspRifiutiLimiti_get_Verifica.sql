SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_get_Verifica]
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @Data DATE = CAST(GETDATE() AS DATE);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Se @IdSede è indicata, deve essere una sede interna della sessione
		IF @IdSede IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			WHERE i.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Righe di verifica effettive per ciascun limite: un limite con @IdRegistro esplicito
		-- produce sempre una sola riga (verifica ristretta a quel registro); un limite senza
		-- registro produce una riga aggregata di sede (VerificaPerRegistro=0) oppure una riga
		-- per ciascun registro della sede, indipendente (VerificaPerRegistro=1, default).
		;WITH LimitiEspansi AS (
			SELECT
				IdLimite = c.Id,
				IdRegistroVerifica = c.IdRegistro
			FROM dbo.tblRifiutiLimiti c
			WHERE c.IdRegistro IS NOT NULL

			UNION ALL

			SELECT
				IdLimite = c.Id,
				IdRegistroVerifica = NULL
			FROM dbo.tblRifiutiLimiti c
			WHERE
				c.IdRegistro IS NULL
				AND ISNULL(c.VerificaPerRegistro, 1) = 0

			UNION ALL

			SELECT
				IdLimite = c.Id,
				IdRegistroVerifica = r.Id
			FROM
				dbo.tblRifiutiLimiti c
				INNER JOIN dbo.tblRifiutiRegistri r ON r.IdSede = c.IdSede AND r.Lock = 0
			WHERE
				c.IdRegistro IS NULL
				AND ISNULL(c.VerificaPerRegistro, 1) = 1
		),
		-- Stessa logica di quantità residua di uspRifiutiGiacenze_get_Quantita, non ristretta
		-- a un singolo registro/EER/stato fisico: il filtro per limite avviene nelle APPLY sotto.
		QuantitaAssegnata AS (
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
			c.Id,
			c.Nome,
			c.IdSede,
			c.IdRegistro,
			le.IdRegistroVerifica,
			RegistroVerificaNome = rv.Nome,
			c.IdUnitaMisura,
			c.Riferimento,
			c.Intervallo,
			c.Valore,
			ValoreAttuale = ISNULL(CASE
				WHEN c.Riferimento = 'G' AND c.IdUnitaMisura = 'GG' THEN giac.GiacenzaGiorni
				WHEN c.Riferimento = 'G' THEN giac.GiacenzaQuantita
				WHEN c.Riferimento = 'O' THEN op.OperazioniQuantita
			END, 0),
			Superato = CAST(IIF(ISNULL(CASE
				WHEN c.Riferimento = 'G' AND c.IdUnitaMisura = 'GG' THEN giac.GiacenzaGiorni
				WHEN c.Riferimento = 'G' THEN giac.GiacenzaQuantita
				WHEN c.Riferimento = 'O' THEN op.OperazioniQuantita
			END, 0) >= c.Valore, 1, 0) AS BIT)
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			INNER JOIN LimitiEspansi le ON le.IdLimite = c.Id
			LEFT JOIN dbo.tblRifiutiRegistri rv ON rv.Id = le.IdRegistroVerifica
			CROSS APPLY (
				SELECT
					GiacenzaQuantita = SUM(x.ResiduoUnitaMisura),
					GiacenzaGiorni = DATEDIFF(DAY, MIN(x.DataSeResiduo), @Data)
				FROM (
					SELECT
						-- Le due espressioni portano un riferimento esterno (c.IdUnitaMisura):
						-- va isolato in una derived table prima dell'aggregazione, altrimenti
						-- SQL Server rifiuta l'aggregato per riferimento esterno misto a colonne locali.
						ResiduoUnitaMisura = CASE WHEN m.IdUnitaMisura = c.IdUnitaMisura THEN (m.Quantita - ISNULL(a.Quantita, 0)) END,
						DataSeResiduo = CASE WHEN (m.Quantita - ISNULL(a.Quantita, 0)) > 0 THEN r.[Data] END
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
						INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
						LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
					WHERE
						r.Lock = 0
						AND r.[Data] <= @Data
						AND (
							(le.IdRegistroVerifica IS NOT NULL AND m.IdRegistro = le.IdRegistroVerifica)
							OR (le.IdRegistroVerifica IS NULL AND m.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = c.IdSede AND Lock = 0))
						)
						AND m.Quantita > 0
						AND (
							(ISNULL(m.IdOperazione, '') <> 'R' AND o.Operazione = 'C')
							OR (m.IdOperazione = 'R' AND o.Operazione = 'S')
						)
						AND (
							NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
							OR m.IdEer IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
						)
						AND (
							NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
							OR EXISTS (
								SELECT 1
								FROM dbo.tblRifiutiRegistrazioniEtichette re
								WHERE
									re.Id = r.Id
									AND re.IdEtichetta IN (SELECT IdEtichetta FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
							)
						)
				) x
			) giac
			CROSS APPLY (
				SELECT
					OperazioniQuantita = SUM(x.QuantitaUnitaMisura)
				FROM (
					SELECT
						-- Riferimento esterno c.IdUnitaMisura isolato in derived table, stesso motivo di giac.
						QuantitaUnitaMisura = CASE WHEN m.IdUnitaMisura = c.IdUnitaMisura THEN m.Quantita END
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock = 0
						AND r.[Data] <= @Data
						AND r.[Data] >= CASE c.Intervallo
							WHEN 'GG' THEN @Data
							WHEN 'WK' THEN CAST(DATEADD(WEEK, DATEDIFF(WEEK, 0, @Data), 0) AS DATE)
							WHEN 'MM' THEN DATEFROMPARTS(YEAR(@Data), MONTH(@Data), 1)
							WHEN 'YY' THEN DATEFROMPARTS(YEAR(@Data), 1, 1)
						END
						AND (
							(le.IdRegistroVerifica IS NOT NULL AND m.IdRegistro = le.IdRegistroVerifica)
							OR (le.IdRegistroVerifica IS NULL AND m.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = c.IdSede AND Lock = 0))
						)
						AND m.Quantita > 0
						AND (
							NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
							OR m.IdEer IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
						)
						AND (
							NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
							OR EXISTS (
								SELECT 1
								FROM dbo.tblRifiutiRegistrazioniEtichette re
								WHERE
									re.Id = r.Id
									AND re.IdEtichetta IN (SELECT IdEtichetta FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
							)
						)
						AND (
							NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite = c.Id)
							OR m.IdOperazione IN (SELECT IdOperazione FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite = c.Id)
						)
				) x
			) op
		WHERE
			c.Lock = 0
			AND (@IdSede IS NULL OR c.IdSede = @IdSede)
		ORDER BY c.Nome, rv.Nome
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
