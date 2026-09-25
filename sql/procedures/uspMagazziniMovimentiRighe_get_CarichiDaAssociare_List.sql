SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_CarichiDaAssociare_List
	@IdParent CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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

		-- Riga di scarico (padre) nell'azienda interna corrente della sessione
		DECLARE @idSede CHAR(16), @idArticolo CHAR(16), @data DATE, @numero INT;
		SELECT
			@idSede = r.IdSede,
			@idArticolo = r.IdArticolo,
			@data = ISNULL(m.[Data], CAST(GETDATE() AS DATE)),
			@numero = m.Numero
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			r.Id = @IdParent
			AND e.Id = @IdSessione
			AND m.IdOperazione = 'S'
			AND m.Lock IN (0, 2);

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga di scarico non esiste';
			GOTO BRANCH_END;
		END

		-- Righe di carico associabili (stessi filtri di uspMagazziniMovimenti_upd): stessa
		-- Sede+Articolo, movimento di carico confermato, cronologicamente precedente allo
		-- scarico (a parità di data, numero inferiore; scarico non ancora numerato = dopo
		-- tutti i confermati), residuo > 0, non già associate a questa riga
		SELECT
			rc.Id,
			MovimentoNumero = mc.Numero,
			MovimentoData = mc.[Data],
			LottoNome = l.Nome,
			LottoDataChiusura = l.DataChiusura,
			rc.Quantita,
			Residuo = rc.Quantita - ISNULL(c.Consumata, 0)
		FROM
			dbo.tblMagazziniMovimentiRighe rc
			INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
			OUTER APPLY (
				SELECT Consumata = SUM(rel.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel.Id = rc.Id
					AND mp.Lock IN (0, 2)
			) c
		WHERE
			mc.IdOperazione = 'C'
			AND mc.Lock = 0
			AND rc.Lock = 0
			AND rc.IdSede = @idSede
			AND rc.IdArticolo = @idArticolo
			AND (
				mc.[Data] < @data
				OR (mc.[Data] = @data AND (@numero IS NULL OR mc.Numero < @numero))
			)
			AND rc.Quantita - ISNULL(c.Consumata, 0) > 0
			AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheRelazioni x WHERE x.Id = rc.Id AND x.IdParent = @IdParent)
		ORDER BY mc.[Data], mc.Numero
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
