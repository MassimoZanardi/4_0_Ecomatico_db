SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get_SelectList
	@IdSede CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdArticolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdArticolo non può essere vuoto';
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

		-- Solo lotti dello stesso Articolo+Sede, non disabilitati, non chiusi
		SELECT
			l.Id,
			[Text] = l.Nome + ' (disp. ' + FORMAT(ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0), 'N2', 'it-IT') + ')',
			Selected = CAST(IIF(l.Id = @IdSelected, 1, 0) AS BIT)
		FROM
			dbo.tblMagazziniLotti l
			-- Caricato: righe di carico confermate del lotto; Scaricato: relazioni di scarichi
			-- confermati su quelle righe di carico (tblMagazziniMovimentiRigheRelazioni)
			OUTER APPLY (
				SELECT
					Caricato = (
						SELECT SUM(rc.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRighe rc
							INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						WHERE
							rc.IdLotto = l.Id
							AND rc.Lock = 0
							AND mc.Lock = 0
					),
					Scaricato = (
						SELECT SUM(rel.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
							INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rc.IdLotto = l.Id
							AND rp.Lock = 0
							AND mp.Lock = 0
					)
			) q
		WHERE
			l.IdSede = @IdSede
			AND l.IdArticolo = @IdArticolo
			AND l.Lock = 0
			AND ISNULL(l.Disabilitato, 0) = 0
			AND (l.DataChiusura IS NULL OR l.DataChiusura >= CAST(GETDATE() AS DATE))
			AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY l.Nome
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
