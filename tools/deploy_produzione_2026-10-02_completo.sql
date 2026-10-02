/*
Deploy produzione 2026-10-02 (pomeriggio) - da deployed-prod 4c4d752 a 9706e9e

Esegue in sequenza i due bundle del giorno, ciascuno con la propria transazione:
  1) deploy_produzione_2026-10-02_login_blocco_aree_visibilita.sql
     - login rifiutato con "Dominio sospeso", "Dominio scaduto", "Utente scaduto"
       (dominio Master mai bloccato)
     - l'azienda proprietaria vede sempre le proprie anagrafiche anche se sono in un'area
  2) deploy_produzione_2026-10-02_aree_due_aziende.sql
     - Impostazioni > Aree solo con almeno 2 aziende interne nel dominio
       (l'amministratore del dominio Master la vede sempre)

Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -I -f 65001 -b -i <questo file>
App da pubblicare: master 031cb0f (il blocco del login richiede l'app aggiornata; l'ordine
DB/app non conta). Le modifiche valgono dal login successivo degli utenti.
*/

-- ===== PARTE 1 : deploy_produzione_2026-10-02_login_blocco_aree_visibilita.sql =====

/*
Deploy produzione 2026-10-02 - Blocco login e visibilità delle anagrafiche condivise

1) uspUtenti_get_LoginByEmail: nuova colonna Blocco ("Dominio sospeso", "Dominio scaduto",
   "Utente scaduto"), applicata dall'app solo dopo la verifica della password. Il dominio
   Master non viene mai bloccato. Da deployare insieme all'app (LoginData.Blocco).

2) L'azienda proprietaria vede sempre le proprie anagrafiche (soggetti e sedi esterne,
   persone, oggetti) anche se sono in un'area di cui non fa parte. Corrette le funzioni
   ufn*NonCondivis*ByUtente: escludono un'anagrafica solo se l'utente la vede già come
   condivisa. Le funzioni sono WITH SCHEMABINDING: nella stessa transazione si eliminano
   le 6 dipendenti, si modificano le 4 funzioni e si ricreano le dipendenti dai file del repo.
*/

-- 1) Blocco login

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_LoginByEmail]
	@Email NVARCHAR(255) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizzazione: rimuove spazi, vuoti e forza minuscolo
		-- LOWER() rende il confronto sicuro senza COLLATE runtime
		SET @Email = LOWER(NULLIF(LTRIM(RTRIM(@Email)), ''));

		IF @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Email non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @StatoAttivo NVARCHAR(10) = 'AT'; -- AT = Attivo (tblUtentiStati)

		SELECT TOP 1
			u.Id,
			u.IdDominio,
			u.IdRuolo,
			u.Email,
			p.[Password],
			PasswordScaduta = CAST(
				CASE
					WHEN p.Temporanea = 1 THEN 1
					WHEN u.PasswordScadenzaGiorni > 0
						 AND DATEDIFF(
							 DAY,
							 ISNULL(p.[Data], GETDATE()),
							 GETDATE()
						 ) > u.PasswordScadenzaGiorni THEN 1
					ELSE 0
				END
			AS BIT),
			-- Blocco dell'accesso, mostrato solo dopo la verifica della password (lato C#, per non
			-- rivelare lo stato del dominio a chi non conosce la password). Valgono fino al giorno di
			-- scadenza compreso. Il dominio Master non viene mai bloccato: i suoi amministratori
			-- riattivano gli altri domini o ne spostano la scadenza
			Blocco = CASE
				WHEN ISNULL(d.[Master], 0) = 1 THEN NULL
				WHEN d.IdStato = 'SO' THEN 'Dominio sospeso'
				WHEN d.Scadenza < CAST(GETDATE() AS DATE) THEN 'Dominio scaduto'
				WHEN u.Scadenza < CAST(GETDATE() AS DATE) THEN 'Utente scaduto'
				ELSE NULL
			END
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblDomini d ON u.IdDominio = d.Id
			OUTER APPLY (
				SELECT TOP 1 [Password], [Data], Temporanea
				FROM dbo.tblUtentiPassword
				WHERE Id = u.Id
				ORDER BY [Data] DESC
			) p
		WHERE
			u.Email = @Email
			AND u.IdStato = @StatoAttivo
			AND u.Lock = 0
		ORDER BY
			u.Id ASC;

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

-- 2) Visibilita' anagrafiche: tutto in una transazione (con -b un errore la annulla)
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Funzioni WITH SCHEMABINDING che dipendono da quelle da modificare (prima il livello 2, poi il livello 1)
DROP FUNCTION IF EXISTS dbo.ufnOsepe_get_ByUtente_List;
DROP FUNCTION IF EXISTS dbo.ufnSedi_get_SediByUtente_List;
DROP FUNCTION IF EXISTS dbo.ufnOggetti_get_ByUtente_List;
DROP FUNCTION IF EXISTS dbo.ufnOsepe_get_NonCondiviseByUtente_List;
DROP FUNCTION IF EXISTS dbo.ufnPersone_get_ByUtente_List;
DROP FUNCTION IF EXISTS dbo.ufnSedi_get_SediEsterneByUtente_List;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_SediEsterneNonCondiviseByUtente_List] (
	@i dbo.tvpAziendeInterneByUtente READONLY)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: sedi esterne dirette
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		@i i
		INNER JOIN dbo.tblSediEsterne e ON i.Id = e.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON e.Id = s.Id
	WHERE
		s.Lock = 0
		-- Esclusa solo se l'utente la vede gia' come condivisa (area di cui fa parte una sua azienda interna):
		-- l'azienda proprietaria vede sempre le proprie anagrafiche, anche in un'area di cui non fa parte
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id INNER JOIN dbo.tblAreeSediInterne ai ON a.Id = ai.Id INNER JOIN @i x ON ai.IdSede = x.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
	UNION ALL -- mutualmente esclusivi: s.Id ≠ s.IdParent per definizione

	-- Ramo 2: sotto-sedi delle sedi esterne
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		@i i
		INNER JOIN dbo.tblSediEsterne e ON i.Id = e.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON e.Id = s.IdParent
	WHERE
		s.Lock = 0
		-- Esclusa solo se l'utente la vede gia' come condivisa (area di cui fa parte una sua azienda interna):
		-- l'azienda proprietaria vede sempre le proprie anagrafiche, anche in un'area di cui non fa parte
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id INNER JOIN dbo.tblAreeSediInterne ai ON a.Id = ai.Id INNER JOIN @i x ON ai.IdSede = x.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.IdParent )
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeEsterneNonCondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		se.Id,
		s.IdParent,
		s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblSediEsterne se ON i.Id = se.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON se.Id = s.Id
	WHERE
		s.Lock = 0
		-- Esclusa solo se l'utente la vede gia' come condivisa (area di cui fa parte una sua azienda interna):
		-- l'azienda proprietaria vede sempre le proprie anagrafiche, anche in un'area di cui non fa parte
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id INNER JOIN dbo.tblAreeSediInterne ai ON a.Id = ai.Id INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) x ON ai.IdSede = x.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnOggetti_get_NonCondivisiByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		s.Id,
		s.IdSede,
		i.IdDominio
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblOggetti s ON i.Id = s.IdSede
	WHERE
		s.Lock = 0
		-- Esclusa solo se l'utente la vede gia' come condivisa (area di cui fa parte una sua azienda interna):
		-- l'azienda proprietaria vede sempre le proprie anagrafiche, anche in un'area di cui non fa parte
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id INNER JOIN dbo.tblAreeSediInterne ai ON a.Id = ai.Id INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) x ON ai.IdSede = x.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnPersone_get_NonCondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		s.Id,
		s.IdSede,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblPersone s ON i.Id = s.IdSede
	WHERE
		s.Lock = 0
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAreeOsepe ae
				INNER JOIN dbo.tblAree a ON ae.Id = a.Id
				INNER JOIN dbo.tblAreeSediInterne ai ON a.Id = ai.Id
				INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) x ON ai.IdSede = x.Id
			-- Esclude solo le persone che l'utente vede gia' come condivise (area di cui fa parte una sua
			-- azienda interna): l'azienda proprietaria vede sempre le proprie, anche in un'area di cui non fa parte
			WHERE a.Lock = 0 AND ae.IdOsepe = s.Id
		)
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnOggetti_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: oggetti CONDIVISI (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Condiviso = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnOggetti_get_CondivisiByUtente_List(@IdUtente)

	UNION ALL -- mutualmente esclusivi per definizione

	-- Ramo 2: oggetti NON condivisi (Pos = 1 → priorità inferiore)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Condiviso = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnOggetti_get_NonCondivisiByUtente_List(@IdUtente)
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER FUNCTION [dbo].[ufnOsepe_get_NonCondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS @result TABLE (
	Id CHAR(16) NOT NULL,
	Tipo CHAR(1) NOT NULL,
	IdSede CHAR(16) NULL,
	IdDominio CHAR(16) NULL,
	Disabilitata BIT NOT NULL,
	[Text] VARCHAR(401) NOT NULL,
	ImpiegabileServizi BIT NOT NULL
)
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @i dbo.tvpAziendeInterneByUtente;

	INSERT @i (Id, IdDominio)
	SELECT Id, IdDominio
	FROM dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente);

	-- Ramo 1: sedi esterne non condivise
	INSERT @result (Id, Tipo, IdSede, IdDominio, Disabilitata, [Text], ImpiegabileServizi)
	SELECT
		i.Id,
		Tipo = 'S',
		IdSede = s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata,
		[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
		ImpiegabileServizi = CAST(0 AS BIT)
	FROM
		dbo.ufnSedi_get_SediEsterneNonCondiviseByUtente_List(@i) i
		INNER JOIN dbo.tblSedi s ON i.Id = s.Id
	WHERE s.Lock = 0;

	-- Ramo 2: persone non condivise
	INSERT @result (Id, Tipo, IdSede, IdDominio, Disabilitata, [Text], ImpiegabileServizi)
	SELECT
		i.Id,
		Tipo = 'P',
		IdSede = i.IdSede,
		i.IdDominio,
		s.Disabilitata,
		[Text] = s.NomeCompleto,
		s.ImpiegabileServizi
	FROM
		dbo.ufnPersone_get_NonCondiviseByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblPersone s ON i.Id = s.Id
	WHERE s.Lock = 0;

	-- Ramo 3: oggetti non condivisi
	INSERT @result (Id, Tipo, IdSede, IdDominio, Disabilitata, [Text], ImpiegabileServizi)
	SELECT
		i.Id,
		Tipo = 'O',
		IdSede = i.IdSede,
		i.IdDominio,
		s.Disabilitata,
		[Text] = s.Nome,
		s.ImpiegabileServizi
	FROM
		dbo.ufnOggetti_get_NonCondivisiByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblOggetti s ON i.Id = s.Id
	WHERE s.Lock = 0;

	RETURN;
END;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnPersone_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: persone CONDIVISE (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Disabilitata,
		Condivisa = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnPersone_get_CondiviseByUtente_List(@IdUtente)

	UNION ALL -- mutualmente esclusivi per definizione

	-- Ramo 2: persone NON condivise (Pos = 1 → priorità inferiore)
	SELECT
		Id,
		IdSede,
		IdDominio,
		Disabilitata,
		Condivisa = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnPersone_get_NonCondiviseByUtente_List(@IdUtente)
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_SediEsterneByUtente_List] (
	@IdUtente CHAR(16))
RETURNS @result TABLE (
	Id CHAR(16) NOT NULL,
	IdParent CHAR(16) NULL,
	IdAziendaInterna CHAR(16) NULL,
	IdDominio CHAR(16) NULL,
	Disabilitata BIT NOT NULL,
	Condivisa BIT NOT NULL,
	Pos INT NOT NULL
)
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @i dbo.tvpAziendeInterneByUtente;

	INSERT @i (Id, IdDominio)
	SELECT Id, IdDominio
	FROM dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente);

	-- Ramo 1: sedi esterne CONDIVISE (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	INSERT @result (Id, IdParent, IdAziendaInterna, IdDominio, Disabilitata, Condivisa, Pos)
	SELECT
		Id,
		IdParent,
		IdAziendaInterna,
		IdDominio,
		Disabilitata,
		Condivisa = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnSedi_get_SediEsterneCondiviseByUtente_List(@i);

	-- Ramo 2: sedi esterne NON condivise (Pos = 1 → priorità inferiore)
	INSERT @result (Id, IdParent, IdAziendaInterna, IdDominio, Disabilitata, Condivisa, Pos)
	SELECT
		Id,
		IdParent,
		IdAziendaInterna,
		IdDominio,
		Disabilitata,
		Condivisa = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnSedi_get_SediEsterneNonCondiviseByUtente_List(@i);

	RETURN;
END;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnOsepe_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: Osepe CONDIVISE (Pos = 0 → precedenza nelle query con ORDER BY Pos)
	SELECT
		Id,
		Tipo,
		IdSede,
		IdDominio,
		Disabilitata,
		[Text],
		ImpiegabileServizi,
		Condivisa = CAST(1 AS BIT),
		Pos = 0
	FROM dbo.ufnOsepe_get_CondiviseByUtente_List(@IdUtente)
	UNION ALL -- mutualmente esclusivi per definizione
	-- Ramo 2: Osepe NON condivise (Pos = 1 → priorità inferiore)
	SELECT
		Id,
		Tipo,
		IdSede,
		IdDominio,
		Disabilitata,
		[Text],
		ImpiegabileServizi,
		Condivisa = CAST(0 AS BIT),
		Pos = 1
	FROM dbo.ufnOsepe_get_NonCondiviseByUtente_List(@IdUtente)
);
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_SediByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Sedi esterne: condivise o non condivise secondo la funzione dedicata
	SELECT
		Id,
		IdParent,
		IdAziendaInterna,
		IdDominio,
		Condivisa,
		Disabilitata,
		Interna = CAST(0 AS BIT)
	FROM
		dbo.ufnSedi_get_SediEsterneByUtente_List(@IdUtente)
	UNION ALL -- mutualmente esclusivi: Interna=1 vs Interna=0
	-- Sedi interne: sempre non condivise per definizione
	SELECT
		Id,
		IdParent,
		IdAziendaInterna,
		IdDominio,
		Condivisa = CAST(0 AS BIT),
		Disabilitata,
		Interna = CAST(1 AS BIT)
	FROM
		dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente)
);
GO

COMMIT TRANSACTION;
GO

-- ===== PARTE 2 : deploy_produzione_2026-10-02_aree_due_aziende.sql =====

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

