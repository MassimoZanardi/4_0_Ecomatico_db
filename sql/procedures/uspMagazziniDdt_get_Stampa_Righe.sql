SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Righe stampate sul DDT di un movimento, nell'ordine di posizione (M5.9): articoli (codice, nome e lotto), righe
-- descrittive (solo testo) e materiali EoW (in kg, come i lotti EoW). Imballo "Alla rinfusa" se indicato così.
-- I controlli sul DDT da stampare sono in uspMagazziniDdt_get_Stampa
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get_Stampa_Righe
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

		-- Il movimento è dell'azienda del contesto, come in uspMagazziniDdt_get
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
			Descrizione,
			Imballo,
			Colli,
			UnitaMisura,
			Quantita,
			IsNumero
		FROM
			(
				SELECT
					r.Pos,
					r.Id,
					-- Riga descrittiva: solo il testo
					Descrizione = IIF(r.IdArticolo IS NULL, r.Descrizione, ISNULL(a.Codice + ' - ', '') + a.Nome + ISNULL(' - Lotto ' + l.Nome, '')),
					Imballo = IIF(ISNULL(r.AllaRinfusa, 0) = 1, 'Alla rinfusa', im.Nome),
					Colli = NULLIF(r.Colli, 0),
					UnitaMisura = u.Codice,
					Quantita = IIF(r.IdArticolo IS NULL, NULL, r.Quantita),
					IsNumero = CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT)
				FROM
					dbo.tblMagazziniMovimentiRighe r
					LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
					LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
					LEFT JOIN dbo.tblMagazziniLotti l ON r.IdLotto = l.Id
					LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
				WHERE
					r.IdMovimento = @IdMovimento
					AND r.Lock < 2
				UNION ALL
				SELECT
					r.Pos,
					r.Id,
					Descrizione = m.Nome + ISNULL(' - Lotto ' + l.Nome, ''),
					Imballo = IIF(ISNULL(r.AllaRinfusa, 0) = 1, 'Alla rinfusa', im.Nome),
					Colli = NULLIF(r.Colli, 0),
					UnitaMisura = 'KG',
					r.Quantita,
					IsNumero = CAST(0 AS BIT)
				FROM
					dbo.tblMagazziniMovimentiRigheEoW r
					LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
					LEFT JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
					LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
				WHERE
					r.IdMovimento = @IdMovimento
					AND r.Lock < 2
			) x
		ORDER BY
			x.Pos,
			x.Id;

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
