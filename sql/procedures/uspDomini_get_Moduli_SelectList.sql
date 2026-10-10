SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_Moduli_SelectList]
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

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso: solo Admin di dominio Master (come uspDomini_get_Moduli_List)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Restituisce i moduli selezionabili per un dominio
		-- escludendo BAS (Base) e IMP (Impostazioni) riservati al sistema.
		-- Con @Id (il dominio) solo quelli non ancora assegnati al dominio
		SELECT
			m.Id,
			[Text] = m.Nome,
			Selected = CAST(0 AS BIT)
		FROM dbo.tblModuli m
		WHERE
			m.Id NOT IN ('BAS', 'IMP')
			AND
				(
				@Id IS NULL
				OR NOT EXISTS (SELECT 1 FROM dbo.tblDominiModuli d WHERE d.Id = @Id AND d.IdModulo = m.Id)
				)
		ORDER BY m.Nome
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO
