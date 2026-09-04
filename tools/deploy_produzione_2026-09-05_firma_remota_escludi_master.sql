-- =====================================================================================
-- Deploy produzione 2026-09-05: Firma remota - select Utenti dedicata
-- Repo: 4_0_ecomatico
--
-- Nuova SP dedicata per popolare la select "Utente" nella pagina Firma remota, con
-- pattern standard "(Selezionare)" e testo sempre comprensivo di email; esclude gli
-- utenti "ombra" (tblUtenti.Master = 1). uspUtenti_get_ListByDominio resta invariata
-- (usata solo da MenuService per l'invalidazione cache).
--
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -b -i <questo file>
-- =====================================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_SelectListByDominio]
	@IdDominio CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdDominio = NULLIF(LTRIM(RTRIM(@IdDominio)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdDominio non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: si può elencare solo il proprio Dominio, oppure qualsiasi
		-- Dominio se l'Admin appartiene a un Dominio Master.
		IF @IdDominio <> @idDominioSessione
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = '',
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			u.Id,
			[Text] = CAST(
				CASE
					WHEN NULLIF(LTRIM(RTRIM(CONCAT(u.Nome, ' ', u.Cognome))), '') IS NOT NULL
						THEN CONCAT(u.Nome, ' ', u.Cognome, ' (', u.Email, ')')
					ELSE u.Email
				END
			AS VARCHAR(200)),
			Selected = CAST(IIF(u.Id = @IdSelected, 1, 0) AS BIT),
			Pos = 1
		FROM dbo.tblUtenti u
		WHERE
			u.IdDominio = @IdDominio
			AND u.Lock = 0
			AND ISNULL(u.[Master], 0) = 0
		ORDER BY Pos, [Text];

	END TRY
	BEGIN CATCH
		THROW;
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
