CREATE PROCEDURE [dbo].[uspMenu_get]
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @Menu VARCHAR(MAX) = NULL;

		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRY
			-- Costruisce il menu JSON con le pagine accessibili dall'utente.
			-- La CTE filtra le pagine per cui l'utente ha accesso alla funzione.
			-- La query esterna filtra le aree:
			--   - Admin Master: accede a tutte le aree senza filtro sui moduli
			--   - Utenti normali: il modulo (IdArea = IdModulo) deve essere
			--     abilitato sul dominio dell'utente
			WITH cte AS (
				SELECT
					m.Id,
					m.IdParent,
					Nome = p.Nome,
					Pagina = LOWER('/' + ISNULL(p.[Url], p.Nome)),
					m.Pos
				FROM
					dbo.tblMenu m
					INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
					INNER JOIN dbo.ufnFunzioni_get_ByUtente_List(@IdUtente) f
											  ON p.IdFunzione = f.Id
			)
			SELECT @Menu = (
				SELECT
					m.Id,
					Nome = a.Nome,
					Icon = a.Icon,
					Pagine = (
						SELECT
							s.Id,
							s.Nome,
							s.Pagina
						FROM cte s
						WHERE
							s.IdParent = m.Id
							AND s.Nome IS NOT NULL
						ORDER BY s.Pos
						FOR JSON PATH
					)
				FROM
					dbo.tblMenu m
					INNER JOIN dbo.tblPagineAree a ON m.IdArea = a.Id
				WHERE
					EXISTS (SELECT 1 FROM cte s WHERE s.IdParent = m.Id)
					AND (
						-- Admin Master: accede a tutte le aree
						EXISTS (
							SELECT 1
							FROM dbo.tblUtenti u
							INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
							WHERE u.Id = @IdUtente
							  AND d.[Master] = 1
						)
						OR
						-- Utenti normali: modulo dell'area abilitato sul dominio
						EXISTS (
							SELECT 1
							FROM dbo.tblDominiModuli dm
							INNER JOIN dbo.tblUtenti u ON dm.Id = u.IdDominio
							WHERE dm.IdModulo = m.IdArea
							  AND u.Id = @IdUtente
						)
					)
				ORDER BY m.Pos
				FOR JSON PATH, ROOT('Aree')
			);
		END TRY
		BEGIN CATCH
			-- Fallback intenzionale: se la generazione del menu fallisce
			-- restituisce il menu minimo con la sola area Home.
			SET @Menu = '{"Aree":[{"Id":"AA0","Nome":"Home","Icon":"fal fa-home","Pagine":[{"Id":"AA1","Nome":"Avvisi","Pagina":"\/Avvisi"}]}]}';
		END CATCH

		SELECT @Menu AS rtn;

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
