CREATE FUNCTION [dbo].[ufnFunzioni_get_ByUtente_List] (
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
		AND (d.[Master] = 1 OR f.[Master] = 0)
		AND EXISTS ( SELECT 1 FROM dbo.tblModuliFunzioni mf INNER JOIN dbo.tblModuli m ON mf.Id = m.Id WHERE mf.IdFunzione = f.Id AND m.Attivo = 1 AND ( d.[Master] = 1 OR EXISTS ( SELECT 1 FROM dbo.tblDominiModuli dm WHERE dm.Id = d.Id AND dm.IdModulo = mf.Id ) ) )
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
		AND ( EXISTS ( SELECT 1 FROM dbo.tblModuliFunzioni mf WHERE mf.IdFunzione = f.Id AND mf.Id = 'BAS' ) OR ( uf.Id IS NOT NULL AND EXISTS ( SELECT 1 FROM dbo.tblDominiModuli dm INNER JOIN dbo.tblModuliFunzioni mf ON dm.IdModulo = mf.Id INNER JOIN dbo.tblModuli m ON mf.Id = m.Id WHERE dm.Id = d.Id AND mf.IdFunzione = f.Id AND m.Attivo = 1 ) ) )
);
