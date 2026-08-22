CREATE PROCEDURE [dbo].[uspRifiutiFormulari_get_Etichette_SelectList]
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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Pre-calcola IdSede FUORI dalla query principale: evita subquery scalare ripetuta per riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = g.IdSede
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE f.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = t.Id,
			[Text] = (
				SELECT
					e.Nome,
					Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
					e.Descrizione,
					e.Visualizzazione
				FROM dbo.tblEtichette e
				INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
				WHERE t.Id = e.Id FOR JSON PATH),
			Selected = CAST(IIF(sel.IdEtichetta IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblEtichette t
			LEFT JOIN (
				SELECT IdEtichetta
				FROM dbo.tblRifiutiFormulariEtichette
				WHERE Id = @Id) sel ON t.Id = sel.IdEtichetta
		WHERE
			t.IdSede = @idSede
			AND t.IdModulo = 'RIF'
			AND t.Lock = 0
		ORDER BY
			Selected DESC, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
