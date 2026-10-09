SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture clienti dell'intervallo scelto per la generazione dei file XML della fattura elettronica: attive,
-- numerate (le pre-fatture non hanno numero), dell'azienda interna corrente della sessione, con il numero tra
-- @DalNumero e @AlNumero e la data di emissione nell'anno @Anno. @Sezionale: NULL tutti i sezionali, '0' solo
-- le fatture senza sezionale, altrimenti la lettera. @EscludiGenerate = 1 lascia fuori le fatture di cui è già
-- stato generato il file (DataXml). Con @Id si considera solo quella fattura (generazione di una fattura sola,
-- anche con allegati): valgono gli stessi requisiti, non numero, anno, sezionale e @EscludiGenerate.
-- Usata dalle uspFatture_get_Xml*_List, che devono vedere le stesse fatture.
CREATE OR ALTER FUNCTION dbo.ufnFatture_get_XmlIntervallo
(
	@IdSessione CHAR(16),
	@DalNumero INT,
	@AlNumero INT,
	@Anno INT,
	@Sezionale CHAR(1),
	@EscludiGenerate BIT,
	@Id CHAR(16)
)
RETURNS TABLE
AS
RETURN
(
	SELECT f.Id
	FROM
		dbo.tblFatture f
		INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
	WHERE
		e.Id = @IdSessione
		AND f.Tipo = 'C'
		AND f.Lock = 0
		AND f.Numero IS NOT NULL
		AND ISNULL(f.IdTipo, '') <> 'TD00'
		AND
			(
			(@Id IS NOT NULL AND f.Id = @Id)
			OR
				(
				@Id IS NULL
				AND f.Numero >= ISNULL(@DalNumero, 1)
				AND f.Numero <= ISNULL(@AlNumero, 2147483647)
				-- Con @Id l'anno non serve e può non essere valido: le due date devono comunque potersi calcolare
				AND f.DataEmissione >= DATEFROMPARTS(IIF(@Id IS NULL, @Anno, 2000), 1, 1)
				AND f.DataEmissione < DATEFROMPARTS(IIF(@Id IS NULL, @Anno, 2000) + 1, 1, 1)
				AND
					(
					@Sezionale IS NULL
					OR (@Sezionale = '0' AND f.Sezionale IS NULL)
					OR f.Sezionale = @Sezionale
					)
				AND (ISNULL(@EscludiGenerate, 0) = 0 OR f.DataXml IS NULL)
				)
			)
);
GO
