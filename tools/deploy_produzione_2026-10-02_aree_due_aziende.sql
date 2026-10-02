/*
Deploy produzione 2026-10-02 - Aree solo con almeno 2 aziende interne

Impostazioni > Aree (funzione ARE) è visibile e accessibile solo se nel dominio dell'utente ci sono
almeno 2 aziende interne attive; l'amministratore del dominio Master la vede sempre.
- ufnFunzioni_get_ByUtente_List (menu)
- ufnFunzioni_get_PermessoByUtente (permessi di pagine e SP)
- ufnFunzioni_get_PermessoBySessione: solo ricreata (dipende da PermessoByUtente, WITH SCHEMABINDING)
Effetto dal login successivo (menu e permessi si calcolano a inizio sessione). Nessuna modifica all'app.
*/

SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Dipende da ufnFunzioni_get_PermessoByUtente (WITH SCHEMABINDING): si elimina e si ricrea
DROP FUNCTION IF EXISTS dbo.ufnFunzioni_get_PermessoBySessione;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnFunzioni_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- ── RAMO 1: Amministratori ───────────────────────────────────────────
	-- Admin dominio normale (Master=0):
	--   accede alle funzioni (f.Master=0) dei moduli attivi abilitati sul dominio
	-- Admin Master (Master=1):
	--   accede a tutte le funzioni attive del sistema incluse quelle Master
	SELECT
		f.Id,
		Permesso = 2
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblFunzioni f ON f.Attiva = 1
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'AD'
		AND
			(
			d.[Master] = 1
			OR f.[Master] = 0
			)
		AND EXISTS ( SELECT 1 FROM dbo.tblModuliFunzioni mf INNER JOIN dbo.tblModuli m ON mf.Id = m.Id WHERE mf.IdFunzione = f.Id AND m.Attivo = 1 AND ( d.[Master] = 1 OR EXISTS ( SELECT 1 FROM dbo.tblDominiModuli dm WHERE dm.Id = d.Id AND dm.IdModulo = mf.Id ) ) )
		-- Aree (ARE): solo con almeno 2 aziende interne attive nel dominio; l'Admin Master le vede sempre
		-- (stessa regola di ufnFunzioni_get_PermessoByUtente)
		AND
			(
			f.Id <> 'ARE'
			OR d.[Master] = 1
			OR ( SELECT COUNT(*) FROM dbo.tblSediInterne si INNER JOIN dbo.tblSedi s ON si.Id = s.Id WHERE si.IdDominio = d.Id AND s.Lock = 0 ) >= 2
			)
	UNION ALL

	-- ── RAMO 2: Utenti Standard ──────────────────────────────────────────
	-- Accede alle funzioni (f.Master=0) se almeno una delle due condizioni è vera:
	--   A) La funzione appartiene al modulo Base (BAS): Permesso = 2
	--   B) La funzione ha un permesso esplicito in tblUtentiFunzioni
	--      su un modulo attivo abilitato sul dominio: Permesso = IdPermesso
	-- Il LEFT JOIN su tblUtentiFunzioni garantisce al massimo una riga
	-- per combinazione (utente, funzione) grazie alla PK (Id, IdFunzione)
	SELECT
		f.Id,
		Permesso = CASE
			WHEN EXISTS (
				SELECT 1
				FROM dbo.tblModuliFunzioni mf
				WHERE
					mf.IdFunzione = f.Id
					AND mf.Id = 'BAS'
			) THEN 2
			ELSE uf.IdPermesso
		END
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblFunzioni f ON f.Attiva = 1
										   AND f.[Master] = 0
		LEFT JOIN dbo.tblUtentiFunzioni uf ON u.Id = uf.Id
										   AND uf.IdFunzione = f.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'US'
		AND d.[Master] = 0
		AND
			(
			f.Id <> 'ARE'
			OR ( SELECT COUNT(*) FROM dbo.tblSediInterne si INNER JOIN dbo.tblSedi s ON si.Id = s.Id WHERE si.IdDominio = d.Id AND s.Lock = 0 ) >= 2
			)
		AND
			(
			EXISTS ( SELECT 1 FROM dbo.tblModuliFunzioni mf WHERE mf.IdFunzione = f.Id AND mf.Id = 'BAS' )
			OR
				(
				uf.Id IS NOT NULL
				AND EXISTS ( SELECT 1 FROM dbo.tblDominiModuli dm INNER JOIN dbo.tblModuliFunzioni mf ON dm.IdModulo = mf.Id INNER JOIN dbo.tblModuli m ON mf.Id = m.Id WHERE dm.Id = d.Id AND mf.IdFunzione = f.Id AND m.Attivo = 1 )
				)
			)
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnFunzioni_get_PermessoByUtente]
(
	@IdFunzione CHAR(3),
	@IdUtente CHAR(16)
)
RETURNS TINYINT
WITH SCHEMABINDING
AS
BEGIN
	IF @IdFunzione IS NULL OR @IdUtente IS NULL
		RETURN 0;

	-- Aree (ARE): servono solo con almeno 2 aziende interne attive nel dominio dell'utente (le aree
	-- condividono anagrafiche tra aziende interne); l'amministratore del dominio Master le vede sempre.
	-- Stessa regola di ufnFunzioni_get_ByUtente_List (menu)
	IF @IdFunzione = 'ARE'
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblUtenti AS u
				INNER JOIN dbo.tblDomini AS d ON u.IdDominio = d.Id
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo = 'AD'
				AND d.[Master] = 1
		)
		AND (
			SELECT COUNT(*)
			FROM
				dbo.tblUtenti AS u
				INNER JOIN dbo.tblSediInterne AS si ON u.IdDominio = si.IdDominio
				INNER JOIN dbo.tblSedi AS s ON si.Id = s.Id
			WHERE
				u.Id = @IdUtente
				AND s.Lock = 0
		) < 2
		RETURN 0;

	RETURN
	(
		SELECT TOP (1)
			Permesso
		FROM
		(
			-- Utenti non amministratori
			SELECT Permesso = uf.IdPermesso
			FROM dbo.tblUtenti AS u
			INNER JOIN dbo.tblUtentiFunzioni AS uf
				ON u.Id = uf.Id
			INNER JOIN dbo.tblFunzioni AS f
				ON uf.IdFunzione = f.Id
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo <> 'AD'
				AND uf.IdFunzione = @IdFunzione
				AND f.Attiva = 1
			UNION ALL

			-- Amministratori
			SELECT Permesso = CONVERT(TINYINT, 2)
			FROM dbo.tblUtenti AS u
			INNER JOIN dbo.tblDominiModuli AS dm
				ON u.IdDominio = dm.Id
			INNER JOIN dbo.tblModuliFunzioni AS mf
				ON dm.IdModulo = mf.Id
			INNER JOIN dbo.tblFunzioni AS f
				ON mf.IdFunzione = f.Id
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo = 'AD'
				AND f.Id = @IdFunzione
				AND f.[Master] = 0
				AND f.Attiva = 1
			UNION ALL

			-- Amministratori Master
			SELECT Permesso = CONVERT(TINYINT, 2)
			FROM dbo.tblUtenti AS u
			INNER JOIN dbo.tblDomini AS d
				ON u.IdDominio = d.Id
			INNER JOIN dbo.tblFunzioni AS f
				ON f.Id = @IdFunzione
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo = 'AD'
				AND d.[Master] = 1
				AND f.Attiva = 1
			UNION ALL

			SELECT Permesso = CONVERT(TINYINT, 0)
		) AS t
		ORDER BY Permesso DESC
	);
END;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnFunzioni_get_PermessoBySessione]
(
	@IdFunzione CHAR(3),
	@IdSessione CHAR(16)
)
RETURNS TINYINT
WITH SCHEMABINDING
AS
BEGIN
	IF @IdFunzione IS NULL OR @IdSessione IS NULL
		RETURN 0;

	RETURN ISNULL(
		(
			SELECT dbo.ufnFunzioni_get_PermessoByUtente(@IdFunzione, s.IdUtente)
			FROM dbo.tblSessioni AS s
			WHERE s.Id = @IdSessione),
		0
	);
END;
GO

COMMIT TRANSACTION;
GO
