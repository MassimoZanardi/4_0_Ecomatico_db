/*
Deploy produzione 2026-10-10 - Impostazioni > Domini: select dei moduli da aggiungere

Da eseguire DOPO deploy_produzione_2026-10-10_report.sql. Rieseguibile. Eseguire con sqlcmd -f 65001 -I.

1. uspDomini_get_Moduli_SelectList: quando il dominio ha gia' tutti i moduli restituisce l'unica voce
   "(Nessuno)", con Id a zeri, invece di un elenco vuoto.

Va deployato insieme all'app (il pulsante Aggiungi e' disabilitato quando la select ha solo "(Nessuno)").

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'uspDomini_get_Moduli_SelectList.sql';
GO
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
		-- Con @Id (il dominio) solo quelli non ancora assegnati al dominio.
		-- Se non ne resta nessuno, l'unica voce è "(Nessuno)" con Id a zeri: non è un modulo da aggiungere
		DECLARE @moduli TABLE (
			Id CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT @moduli (Id, Nome)
		SELECT
			m.Id,
			m.Nome
		FROM dbo.tblModuli m
		WHERE
			m.Id NOT IN ('BAS', 'IMP')
			AND
				(
				@Id IS NULL
				OR NOT EXISTS (SELECT 1 FROM dbo.tblDominiModuli d WHERE d.Id = @Id AND d.IdModulo = m.Id)
				)
		OPTION (RECOMPILE);

		IF EXISTS (SELECT 1 FROM @moduli)
			SELECT
				m.Id,
				[Text] = m.Nome,
				Selected = CAST(0 AS BIT)
			FROM @moduli m
			ORDER BY m.Nome;
		ELSE
			SELECT
				Id = CAST(REPLICATE('0', 3) AS CHAR(3)),
				[Text] = CAST('(Nessuno)' AS VARCHAR(50)),
				Selected = CAST(1 AS BIT);

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

GO

