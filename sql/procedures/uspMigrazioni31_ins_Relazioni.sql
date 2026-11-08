SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 6a: relazioni carico/scarico. SP interna di uspMigrazioni31_ins, eseguita dentro la
-- sua transazione dopo la fase 5 (registrazioni gia' migrate); legge #registrazioni e scrive nel #log del chiamante.
-- Nella 3.1 la relazione e' IDCarico/IDScarico; in 4.0 IdParent = padre (chi sceglie le associate), Id = figlio,
-- Operazione = operazione del padre (registrazioni-rettifiche.md, C:\MyDoc\db\CLAUDE.md):
-- - consumo (quantita' 3.1 > 0): padre = scarico, figlio = carico, quantita' della 3.1;
-- - derivazione (quantita' 3.1 = -1, carico CMC/CRC nato dal trattamento SFC): padre = carico K/M, figlio = scarico R,
--   quantita' secondo ufnMigrazioni31_get_Derivazioni (prelievo fino a esaurimento dello scarico, poi 0).
-- Una relazione legata nella 3.1 a una registrazione di rettifica passa al suo originale: in 4.0 una rettifica non ha
-- relazioni proprie (R2.7). Se dopo lo spostamento la stessa coppia compare due volte, vale la quantita' maggiore.
-- Si migrano solo le relazioni tra registrazioni entrambe migrate e attive, con una coppia di operazioni ammessa
-- (tblRifiutiOperazioniRelazioni: Id = operazione del padre, IdParent = del figlio). Relazioni con quantita' 0 nella
-- 3.1 non associavano nulla (la 3.1 invia al RENTRI solo quelle > 0): scartate. Pos: ordine 3.1 sotto lo stesso padre.
-- Idempotenza: una relazione gia' presente in 4.0 non si reinserisce.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Relazioni
	@IdMigrazione INT = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @IdMigrazione IS NULL OR @IdDominioA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdMigrazione e @IdDominioA sono obbligatori';
			GOTO BRANCH_END;
		END

		CREATE TABLE #rel (
			IdCarico31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdScarico31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			Derivazione BIT NOT NULL,
			Spostata BIT NOT NULL,
			Pos31 INT NULL,
			Quantita DECIMAL(18, 2) NULL,
			IdPadre CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdFiglio CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Esito VARCHAR(20) COLLATE DATABASE_DEFAULT NULL,
			PRIMARY KEY (IdCarico31, IdScarico31)
		);

		-- Relazioni 3.1 tra registrazioni attive, con le rettifiche spostate sul loro originale
		;WITH r31 AS (
			SELECT
				IdCarico = ISNULL(tc.IDRettifica, l.IDCarico) COLLATE DATABASE_DEFAULT,
				IdScarico = ISNULL(ts.IDRettifica, l.IDScarico) COLLATE DATABASE_DEFAULT,
				Derivazione = IIF(l.[Quantità] = -1, 1, 0),
				Spostata = IIF(tc.IDRettifica IS NULL AND ts.IDRettifica IS NULL, 0, 1),
				l.Pos,
				l.[Quantità]
			FROM
				dbo.syn31RifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.syn31RifiutiRegistrazioni c0 ON l.IDCarico = c0.IDRegistrazione
				INNER JOIN dbo.syn31RifiutiRegistrazioni s0 ON l.IDScarico = s0.IDRegistrazione
				LEFT JOIN dbo.syn31RentriRegistrazioniRettifiche tc ON l.IDCarico = tc.IDRegistrazione
				LEFT JOIN dbo.syn31RentriRegistrazioniRettifiche ts ON l.IDScarico = ts.IDRegistrazione
			WHERE
				ISNULL(c0.Lock, 0) = 0
				AND ISNULL(s0.Lock, 0) = 0
		)
		INSERT INTO #rel (IdCarico31, IdScarico31, Derivazione, Spostata, Pos31, Quantita, IdPadre, IdFiglio)
		SELECT
			k.IdCarico,
			k.IdScarico,
			k.Derivazione,
			k.Spostata,
			k.Pos,
			IIF(k.Derivazione = 1, dv.Prelievo, k.Quantita),
			IIF(k.Derivazione = 1, mc.IdDestinazione, ms.IdDestinazione),
			IIF(k.Derivazione = 1, ms.IdDestinazione, mc.IdDestinazione)
		FROM
			(
				SELECT
					IdCarico,
					IdScarico,
					Derivazione = MAX(Derivazione),
					Spostata = MAX(Spostata),
					Pos = MIN(Pos),
					Quantita = MAX(IIF([Quantità] > 0, [Quantità], 0))
				FROM r31
				GROUP BY IdCarico, IdScarico
			) k
				INNER JOIN #registrazioni c ON k.IdCarico = c.Id
				INNER JOIN #registrazioni s ON k.IdScarico = s.Id
				INNER JOIN dbo.tblMigrazioniId mc ON mc.Versione = '31'
				AND mc.IdDominioA = @IdDominioA
				AND mc.Tabella = 'tblRifiutiRegistrazioni'
				AND mc.IdOrigine = c.Id
				INNER JOIN dbo.tblMigrazioniId ms ON ms.Versione = '31'
				AND ms.IdDominioA = @IdDominioA
				AND ms.Tabella = 'tblRifiutiRegistrazioni'
				AND ms.IdOrigine = s.Id
				LEFT JOIN dbo.ufnMigrazioni31_get_Derivazioni() dv ON k.IdCarico = dv.IdCarico COLLATE DATABASE_DEFAULT
				AND k.IdScarico = dv.IdScarico COLLATE DATABASE_DEFAULT
		WHERE
			c.Importabile = 1
			AND s.Importabile = 1;

		-- Relazioni da scartare
		UPDATE x
		SET Esito = CASE WHEN x.Derivazione = 0 AND ISNULL(x.Quantita, 0) <= 0 THEN 'Quantita zero' WHEN NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni rp INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id INNER JOIN dbo.tblRifiutiRegistrazioni rf ON x.IdFiglio = rf.Id INNER JOIN dbo.tblRifiutiMovimenti mf ON rf.IdMovimento = mf.Id INNER JOIN dbo.tblRifiutiOperazioniRelazioni o ON o.Id = mp.IdOperazione AND o.IdParent = mf.IdOperazione WHERE rp.Id = x.IdPadre) THEN 'Coppia non ammessa' WHEN EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioniRelazioni e WHERE e.Id = x.IdFiglio AND e.IdParent = x.IdPadre) THEN 'Gia migrata' END
		FROM #rel x;

		INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
		SELECT
			'Relazioni',
			IIF(Esito = 'Gia migrata', 'I', 'W'),
			'tblRifiutiRegistrazioniRelazioni',
			IdScarico31,
			CONCAT(CASE Esito
				WHEN 'Quantita zero' THEN 'Relazione con quantita'' 0 nella 3.1: scartata'
				WHEN 'Coppia non ammessa' THEN 'Coppia di operazioni non ammessa in 4.0: relazione scartata'
				ELSE 'Relazione gia'' migrata'
			END, ' (carico ', IdCarico31, ')')
		FROM #rel
		WHERE Esito IS NOT NULL;

		INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
		SELECT 'Relazioni', 'W', 'tblRifiutiRegistrazioniRelazioni', IdScarico31, CONCAT('Relazione legata a una rettifica nella 3.1: spostata sull''originale (carico ', IdCarico31, ')')
		FROM #rel
		WHERE
			Spostata = 1
			AND Esito IS NULL;

		INSERT INTO dbo.tblRifiutiRegistrazioniRelazioni (Id, IdParent, Operazione, Quantita, Pos)
		SELECT
			x.IdFiglio,
			x.IdPadre,
			rp.Operazione,
			ISNULL(x.Quantita, 0),
			ROW_NUMBER() OVER (PARTITION BY x.IdPadre ORDER BY x.Pos31, rf.[Data], rf.Numero, x.IdFiglio) - 1
				+ ISNULL((SELECT MAX(e.Pos) + 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni e
				WHERE e.IdParent = x.IdPadre), 0)
		FROM
			#rel x
			INNER JOIN dbo.tblRifiutiRegistrazioni rp ON x.IdPadre = rp.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni rf ON x.IdFiglio = rf.Id
		WHERE x.Esito IS NULL;

		INSERT INTO #log (Fase, Livello, Tabella, Righe, Messaggio)
		SELECT
			'Relazioni',
			'I',
			'tblRifiutiRegistrazioniRelazioni',
			COUNT(*),
			CONCAT('Migrate ', SUM(IIF(Derivazione = 0, 1, 0)), ' relazioni di consumo e ', SUM(IIF(Derivazione = 1, 1, 0)), ' derivazioni (',
				SUM(IIF(Derivazione = 1 AND Quantita = 0, 1, 0)), ' con prelievo 0)')
		FROM #rel
		WHERE Esito IS NULL
		HAVING COUNT(*) > 0;
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
