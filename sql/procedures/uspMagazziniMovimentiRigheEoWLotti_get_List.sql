SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoWLotti_get_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
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
			@IdFunzione = 'MAG',
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
				dbo.tblMagazziniMovimentiRigheEoW r
				INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			WHERE
				r.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Lotti EoW da cui la riga EoW di scarico ha scaricato, nell'ordine di consumo:
		-- Quantita = quanto questo scarico ne ha scaricato; Residuo = quanto resta oggi del
		-- lotto (quote di registrazioni M attive meno gli scarichi non eliminati). Carichi =
		-- le registrazioni rifiuti M attive che hanno prodotto il lotto fino alla data dello
		-- scarico (lo scarico preleva dal lotto, non dalla singola registrazione)
		SELECT
			rl.IdLotto,
			LottoNome = l.Nome,
			MagazzinoNome = g.Nome,
			Carichi = cr.Carichi,
			CaricoUltimo = cu.CaricoUltimo,
			CarichiNumero = ISNULL(cr.CarichiNumero, 0),
			rl.Quantita,
			Residuo = ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0),
			rl.Pos
		FROM
			dbo.tblMagazziniMovimentiRigheEoWLotti rl
			INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rl.Id = re.Id
			INNER JOIN dbo.tblMagazziniMovimenti mv ON re.IdMovimento = mv.Id
			INNER JOIN dbo.tblEoWLotti l ON rl.IdLotto = l.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			OUTER APPLY (
				SELECT
					Carichi = STRING_AGG(CAST(CONCAT('n. ', rc.Numero, ' del ', FORMAT(rc.[Data], 'dd/MM/yyyy')) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY rc.[Data], rc.Numero),
					CarichiNumero = COUNT(*)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni qc
					INNER JOIN dbo.tblRifiutiRegistrazioni rc ON qc.IdRegistrazione = rc.Id
				WHERE
					qc.IdLotto = l.Id
					AND rc.Lock < 2
					AND (mv.[Data] IS NULL OR rc.[Data] <= mv.[Data])
			) cr
			-- Registrazione più recente, mostrata in forma compatta con il numero delle altre
			-- (l'elenco completo resta in Carichi, per il tooltip)
			OUTER APPLY (
				SELECT TOP 1 CaricoUltimo = CONCAT('n. ', rc.Numero, ' del ', FORMAT(rc.[Data], 'dd/MM/yyyy'))
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni qc
					INNER JOIN dbo.tblRifiutiRegistrazioni rc ON qc.IdRegistrazione = rc.Id
				WHERE
					qc.IdLotto = l.Id
					AND rc.Lock < 2
					AND (mv.[Data] IS NULL OR rc.[Data] <= mv.[Data])
				ORDER BY rc.[Data] DESC, rc.Numero DESC
			) cu
			OUTER APPLY (
				SELECT Prodotta = SUM(q.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni q
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = l.Id
					AND rr.Lock < 2
			) p
			OUTER APPLY (
				SELECT Scaricata = SUM(rs.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rs
					INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rs.IdLotto = l.Id
					AND mp.Lock IN (0, 2)
			) sc
		WHERE rl.Id = @Id
		ORDER BY rl.Pos, l.Nome
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
