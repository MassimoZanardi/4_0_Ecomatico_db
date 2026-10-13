SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select degli articoli per la riga a quantità di un importo di magazzino: articoli attivi dell'azienda
-- interna corrente della sessione, al massimo 50, con la ricerca su nome e codice. La prima voce (Id a zeri)
-- è "(Selezionare)". L'articolo selezionato è sempre presente, anche se cancellato, fuori dalla ricerca o
-- oltre i primi 50.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Articoli_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				a.Id,
				[Text] = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(400)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblMagazziniArticoli a
			WHERE
				a.Id = @IdSelected
				AND a.Id <> @idSediciZeri
			UNION ALL
			SELECT
				t.Id,
				t.[Text],
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				(
					SELECT TOP (50)
						a.Id,
						[Text] = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(400))
					FROM
						dbo.tblMagazziniArticoli a
						INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdAzienda
					WHERE
						e.Id = @IdSessione
						AND a.Lock = 0
						AND a.Id <> @IdSelected
						AND
							(
							@Search IS NULL
							OR a.Nome LIKE '%' + @Search + '%'
							OR a.Codice LIKE '%' + @Search + '%'
							)
					ORDER BY a.Nome, a.Id
				) t
		) x
		ORDER BY Pos, [Text]
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
