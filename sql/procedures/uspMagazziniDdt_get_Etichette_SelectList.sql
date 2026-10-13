SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Etichette assegnabili al DDT del movimento @IdMovimento: quelle attive del modulo Magazzino della sede interna
-- del DDT, con Selected = 1 su quelle già assegnate. Nessuna riga se il movimento non ha un DDT. Le etichette del
-- magazzino si applicano solo ai DDT.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get_Etichette_SelectList
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

		-- Controlla il permesso sulla funzione
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

		-- DDT del movimento, di una sede che la sessione vede
		DECLARE @idDdt CHAR(16), @idSede CHAR(16);
		SELECT
			@idDdt = d.Id,
			@idSede = d.IdSede
		FROM
			dbo.tblMagazziniDdt d
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON d.IdSede = i.Id
		WHERE
			d.IdMovimento = @IdMovimento
			AND d.Lock <= 2;

		SELECT
			t.Id,
			[Text] = (
				SELECT
					e.Nome,
					Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
					e.Descrizione,
					e.Visualizzazione
				FROM
					dbo.tblEtichette e
					INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
				WHERE t.Id = e.Id
				FOR JSON PATH),
			Selected = CAST(IIF(sel.IdEtichetta IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblEtichette t
			LEFT JOIN dbo.tblMagazziniDdtEtichette sel ON sel.Id = @idDdt
													   AND t.Id = sel.IdEtichetta
		WHERE
			t.IdSede = @idSede
			AND t.IdModulo = 'MAG'
			AND t.Lock = 0
		ORDER BY
			Selected DESC,
			[Text];

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
