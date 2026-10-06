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
	-- Valori effettivi da viewRifiutiRegistrazioniEffettive (ultima correzione confermata, 0 se annullata):
	-- la vista non e' schema-bound, quindi la funzione non puo' piu' essere WITH SCHEMABINDING
	DECLARE @TotaleDisponibile DECIMAL(38, 2);
	SELECT
		@TotaleDisponibile =
			ISNULL(SUM(
				CONVERT(DECIMAL(38, 2), v.Quantita)
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
		INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON v.Id = r.Id
		INNER JOIN dbo.tblRifiutiRegistrazioni rp ON rp.Id = @Id
		INNER JOIN dbo.tblRifiutiMovimenti mp ON mp.Id = rp.IdMovimento
		OUTER APPLY (
			SELECT
				SUM(CONVERT(DECIMAL(38, 2), l2.Quantita)) AS QuantitaAssociataTotale
			FROM dbo.tblRifiutiRegistrazioniRelazioni l2
			INNER JOIN dbo.tblRifiutiRegistrazioni p2 ON p2.Id = l2.IdParent
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp2 ON vp2.Id = p2.Id
			WHERE
				l2.Id = lp.Id
				AND p2.Lock < 2
				AND vp2.Quantita > 0
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
					OR v.IdEer = @IdEer
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR v.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					mp.IdOperazione IN ('K', 'M')
					OR v.IdUnitaMisura = @IdUnitaMisura
					)
				)
			);
	RETURN CASE
		WHEN @Quantita > ISNULL(@TotaleDisponibile, 0) THEN 1
		ELSE 0
	END;
END;
GO
