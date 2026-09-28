SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiLimiti_get_Verifica_List] (
	@IdSede CHAR(16) = NULL)
RETURNS TABLE
AS
RETURN
(
	-- Righe di verifica effettive per ciascun limite: un limite con IdRegistro esplicito
	-- produce sempre una sola riga (verifica ristretta a quel registro); un limite senza
	-- registro produce una riga aggregata di sede (VerificaPerRegistro=0) oppure una riga
	-- per ciascun registro della sede, indipendente (VerificaPerRegistro=1, default).
	WITH LimitiEspansi AS (
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
	-- Quantità, EER e unità di misura sono i valori effettivi (viewRifiutiRegistrazioniEffettive),
	-- mai quelli dell'originale: una rettifica non modifica la registrazione originale.
	QuantitaAssegnata AS (
		SELECT
			l.Id,
			Quantita = SUM(l.Quantita)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni l
			INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
		WHERE
			p.Lock = 0
			-- Uno scarico annullato ha Quantita = 0: le sue relazioni restano ma non consumano piu' il carico
			AND vp.Quantita > 0
			AND p.[Data] <= CAST(GETDATE() AS DATE)
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
		INNER JOIN LimitiEspansi le ON le.IdLimite = c.Id
		LEFT JOIN dbo.tblRifiutiRegistri rv ON rv.Id = le.IdRegistroVerifica
		CROSS APPLY (
			SELECT
				GiacenzaQuantita = SUM(x.ResiduoUnitaMisura),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(x.DataSeResiduo), CAST(GETDATE() AS DATE))
			FROM (
				SELECT
					-- Le due espressioni portano un riferimento esterno (c.IdUnitaMisura):
					-- va isolato in una derived table prima dell'aggregazione, altrimenti
					-- SQL Server rifiuta l'aggregato per riferimento esterno misto a colonne locali.
					ResiduoUnitaMisura = CASE WHEN v.IdUnitaMisura = c.IdUnitaMisura THEN (v.Quantita - ISNULL(a.Quantita, 0)) END,
					DataSeResiduo = CASE WHEN (v.Quantita - ISNULL(a.Quantita, 0)) > 0 THEN r.[Data] END
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
					LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				WHERE
					r.Lock = 0
					AND r.[Data] <= CAST(GETDATE() AS DATE)
					AND (
						(le.IdRegistroVerifica IS NOT NULL AND m.IdRegistro = le.IdRegistroVerifica)
						OR (le.IdRegistroVerifica IS NULL AND m.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = c.IdSede AND Lock = 0))
					)
					AND v.Quantita > 0
					-- Una registrazione di rettifica o annullamento non è un movimento reale: mai in giacenza
					AND v.IsRettifica = 0
					AND (
						(ISNULL(m.IdOperazione, '') <> 'R' AND o.Operazione = 'C')
						OR (m.IdOperazione = 'R' AND o.Operazione = 'S')
					)
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
						OR v.IdEer IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
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
					QuantitaUnitaMisura = CASE WHEN v.IdUnitaMisura = c.IdUnitaMisura THEN v.Quantita END
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
				WHERE
					r.Lock = 0
					AND r.[Data] <= CAST(GETDATE() AS DATE)
					AND r.[Data] >= CASE c.Intervallo
						WHEN 'GG' THEN CAST(GETDATE() AS DATE)
						WHEN 'WK' THEN CAST(DATEADD(WEEK, DATEDIFF(WEEK, 0, CAST(GETDATE() AS DATE)), 0) AS DATE)
						WHEN 'MM' THEN DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
						WHEN 'YY' THEN DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
					END
					AND (
						(le.IdRegistroVerifica IS NOT NULL AND m.IdRegistro = le.IdRegistroVerifica)
						OR (le.IdRegistroVerifica IS NULL AND m.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = c.IdSede AND Lock = 0))
					)
					-- Un annullamento operativo porta la quantità effettiva a 0: esclusa
					AND v.Quantita > 0
					-- Bug pre-esistente: le registrazioni di rettifica/annullamento venivano contate come operazioni
					AND v.IsRettifica = 0
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
						OR v.IdEer IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
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
);
