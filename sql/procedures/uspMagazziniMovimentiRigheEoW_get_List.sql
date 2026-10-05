SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdMateriale,
			MaterialeNome = m.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Quantità già relazionata ai lotti EoW consumati (costruita in uspMagazziniMovimenti_upd)
			Relazionata = ISNULL(q.Relazionata, 0),
			-- Numero di lotti EoW da cui la riga ha scaricato: le righe della modale "Carichi"
			LottiNumero = ISNULL(q.LottiNumero, 0),
			r.IdLotto,
			LottoNome = lr.Nome,
			-- Movimento confermato: quantità residua (giacenza attuale) del lotto EoW da cui la
			-- riga ha scaricato; su più lotti somma dei residui con il dettaglio per lotto.
			-- NULL su movimento in bozza (residuo non ancora noto).
			ResiduoLotti = IIF(mv.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(mv.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			-- Anomalia "Scaricato più del prodotto": almeno un lotto EoW da cui la riga ha scaricato ha
			-- giacenza negativa (il registro operativo gli attribuisce meno di quanto già scaricato; il
			-- magazzino EoW prevale, i movimenti non vengono corretti in automatico)
			IsScaricatoPiuDelProdotto = CAST(IIF(mv.Lock = 0 AND ISNULL(z.LottiAnomali, 0) > 0, 1, 0) AS BIT),
			r.IdImballo,
			ImballoNome = im.Nome,
			r.Colli,
			AllaRinfusa = ISNULL(r.AllaRinfusa, 0),
			r.Pos,
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
			INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
			LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
			OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita), LottiNumero = COUNT(*)
			FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl
			WHERE rl.Id = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					LottiAnomali = SUM(IIF(g.Giacenza < 0, 1, 0)),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rl
					INNER JOIN dbo.tblEoWLotti lg ON rl.IdLotto = lg.Id
					-- Giacenza del lotto EoW: quote di registrazioni M attive meno scarichi
					-- confermati di questo modulo
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(qp.Quantita)
								FROM
									dbo.tblEoWLottiRifiutiRegistrazioni qp
									INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
								WHERE
									qp.IdLotto = lg.Id
									AND rr.Lock < 2
							), 0) - ISNULL((
								SELECT SUM(rs.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheEoWLotti rs
									INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rs.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
									CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, 'N2', 'it-IT') AS NVARCHAR(MAX))) t
				WHERE rl.Id = r.Id) z
		WHERE r.IdMovimento = @IdMovimento
		-- Pos NULL (righe precedenti all'introduzione di Pos) per prime, in ordine di Id
		ORDER BY ISNULL(r.Pos, 0), r.Id
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
