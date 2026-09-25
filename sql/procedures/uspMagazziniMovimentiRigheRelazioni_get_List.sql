SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheRelazioni_get_List
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

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimentiRighe r
				INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			WHERE
				r.Id = @IdParent
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Righe di carico relazionate alla riga di scarico @IdParent, nell'ordine di consumo:
		-- Quantita = quanto questo scarico ha scaricato da quel carico; Residuo = quanto resta
		-- oggi del carico, al netto di tutti gli scarichi non eliminati
		SELECT
			rel.Id,
			MovimentoNumero = mc.Numero,
			MovimentoData = mc.[Data],
			LottoNome = l.Nome,
			rel.Quantita,
			Residuo = rc.Quantita - ISNULL(c.Consumata, 0),
			rel.Pos
		FROM
			dbo.tblMagazziniMovimentiRigheRelazioni rel
			INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
			INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
			OUTER APPLY (
				SELECT Consumata = SUM(rel2.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel2
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel2.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel2.Id = rc.Id
					AND mp.Lock IN (0, 2)
			) c
		WHERE rel.IdParent = @IdParent
		ORDER BY rel.Pos
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
