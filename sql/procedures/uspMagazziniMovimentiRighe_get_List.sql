SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_List
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
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdArticolo,
			ArticoloNome = a.Nome,
			UnitaMisuraNome = u.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Riga di scarico: quantità già relazionata alle righe di carico consumate
			-- (le righe di carico non hanno relazioni proprie, sono esse stesse la giacenza)
			Relazionata = ISNULL(q.Relazionata, 0),
			r.IdLotto,
			LottoNome = l.Nome,
			IsNumero = CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			-- Riga di scarico di un movimento confermato: quantità residua (giacenza attuale)
			-- del lotto da cui la riga ha scaricato; se i carichi consumati appartengono a più
			-- lotti, somma dei residui con il dettaglio per lotto. NULL su movimento in bozza
			-- (residuo non ancora noto) e sulle righe di carico.
			ResiduoLotti = IIF(m.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(m.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			r.IdImballo,
			ImballoNome = im.Nome,
			r.Colli,
			AllaRinfusa = ISNULL(r.AllaRinfusa, 0),
			-- Riga descrittiva del DDT: solo Descrizione, senza articolo, lotto, criterio e quantità
			r.Descrizione,
			r.Pos,
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON r.IdLotto = l.Id
			LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
			OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					(
						SELECT DISTINCT rc.IdLotto
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
						WHERE rel.IdParent = r.Id
					) lu
					INNER JOIN dbo.tblMagazziniLotti lg ON lu.IdLotto = lg.Id
					-- Giacenza del lotto: righe di carico confermate meno relazioni di scarichi
					-- confermati (stesso calcolo di uspMagazziniLotti_get_List)
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(rc2.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRighe rc2
									INNER JOIN dbo.tblMagazziniMovimenti mc2 ON rc2.IdMovimento = mc2.Id
								WHERE
									rc2.IdLotto = lg.Id
									AND mc2.IdOperazione = 'C'
									AND rc2.Lock = 0
									AND mc2.Lock = 0
							), 0) - ISNULL((
								SELECT SUM(rel2.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheRelazioni rel2
									INNER JOIN dbo.tblMagazziniMovimentiRighe rc3 ON rel2.Id = rc3.Id
									INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel2.IdParent = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rc3.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
					CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, IIF(a.IdUnitaMisura = 'NR', 'N0', 'N2'), 'it-IT') AS NVARCHAR(MAX))) t
			) z
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
