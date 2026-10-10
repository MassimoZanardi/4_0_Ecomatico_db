SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rifiuti > Report: registri della sede del contesto per il filtro "Registro" della ricerca. La prima voce
-- (sedici zeri) vale "tutti i registri della sede". Senza sede nel contesto resta solo quella.
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_Report_Registri_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede)
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, @idSediciZeri)
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			x.Id,
			x.[Text],
			x.Selected
		FROM
			(
				SELECT
					Id = @idSediciZeri,
					[Text] = CAST('(Tutti i registri della sede)' AS VARCHAR(500)),
					Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
					Pos = 0
				UNION ALL
				SELECT
					r.Id,
					[Text] = r.Nome,
					Selected = CAST(IIF(r.Id = @IdSelected, 1, 0) AS BIT),
					Pos = 1
				FROM dbo.tblRifiutiRegistri r
				WHERE
					r.IdSede = @idSede
					AND r.Lock = 0
			) x
		ORDER BY
			x.Pos,
			x.[Text];

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
