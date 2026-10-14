/*
Deploy produzione 2026-10-14 - Sedi duplicate per gli utenti standard associati a più sedi della stessa azienda

Indipendente dagli altri script. Rieseguibile. Eseguire con sqlcmd -f 65001 -I (oppure da SSMS).

Errore in produzione: "The CREATE UNIQUE INDEX statement terminated because a duplicate key was found ...
IX_sediUtente_Id" in uspRifiutiAutorizzazioni_get_SelectList (scheda del formulario). Causa:
ufnSedi_get_AziendeInterneByUtente_List restituiva l'azienda interna una volta per ogni sede dell'utente, e con lei
si duplicavano sedi esterne, persone e oggetti dell'azienda. Correzione: DISTINCT nel ramo degli utenti standard.

La funzione è referenziata WITH SCHEMABINDING da altre funzioni, che vanno eliminate prima e ricreate dopo (catena
completa, anche indiretta): livello 3, poi 2, poi 1; poi la funzione corretta; poi di nuovo 1, 2, 3.
*/

-- ===== 1. Eliminazione delle funzioni dipendenti
DROP FUNCTION IF EXISTS dbo.ufnOsepe_get_ByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnOggetti_get_ByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnOsepe_get_NonCondiviseByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnPersone_get_ByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnSedi_get_SediByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnOggetti_get_CondivisiByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnOggetti_get_NonCondivisiByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnOsepe_get_CondiviseByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnPersone_get_CondiviseByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnPersone_get_NonCondiviseByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnSedi_get_AziendeEsterneNonCondiviseByUtente_List;
GO
DROP FUNCTION IF EXISTS dbo.ufnSedi_get_SediEsterneByUtente_List;
GO

-- ===== ufnSedi_get_AziendeInterneByUtente_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeInterneByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Amministratori: accesso a tutte le aziende interne del dominio
	SELECT
		i.Id,
		i.IdDominio
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblSediInterne i ON u.IdDominio = i.IdDominio
		INNER JOIN dbo.tblSedi s ON i.Id = s.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'AD' -- AD = Amministratore
		AND s.Lock = 0
	UNION ALL -- ✅ i due rami sono mutualmente esclusivi: UNION ALL evita DISTINCT inutile

	-- Utenti standard: solo le aziende interne direttamente associate. DISTINCT: un utente associato a più sedi
	-- della stessa azienda la riceverebbe più volte, e con lei ogni sede esterna, persona e oggetto dell'azienda
	-- (errore 1505 sull'indice unico di #sediUtente in uspRifiutiAutorizzazioni_get_SelectList)
	SELECT DISTINCT
		i.Id,
		i.IdDominio
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblUtentiSediInterne ui ON u.Id = ui.Id
		INNER JOIN dbo.tblSedi s ON ui.IdSede = s.Id
		INNER JOIN dbo.tblSediInterne i ON s.IdAziendaInterna = i.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo <> 'AD'
		AND s.Lock = 0
);
GO

-- ===== ufnOggetti_get_CondivisiByUtente_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnOggetti_get_CondivisiByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- GROUP BY su s.Id per deduplicare: lo stesso oggetto può apparire più volte
	-- se associato a più aree o se più sedi interne appartengono alla stessa area
	SELECT
		s.Id,
		s.IdSede,
		IdDominio = MIN(ui.IdDominio),
		IdArea = MIN(a.Id),
		Area = MIN(a.Nome)
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
		INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id = ai.IdSede
		INNER JOIN dbo.tblAree a ON ai.Id = a.Id
		INNER JOIN dbo.tblAreeOsepe ae ON a.Id = ae.Id
		INNER JOIN dbo.tblOggetti s ON ae.IdOsepe = s.Id
	WHERE
		a.Lock = 0
		AND s.Lock = 0
	GROUP BY s.Id, s.IdSede
);
GO

-- ===== ufnOggetti_get_NonCondivisiByUtente_List
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

-- ===== ufnOsepe_get_CondiviseByUtente_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnOsepe_get_CondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	WITH cte AS (
		SELECT
			Id = ae.IdOsepe,
			ui.IdDominio,
			IdArea = a.Id,
			Area = a.Nome
		FROM
			dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
			INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id = ai.IdSede
			INNER JOIN dbo.tblAree a ON ai.Id = a.Id
			INNER JOIN dbo.tblAreeOsepe ae ON a.Id = ae.Id
		WHERE a.Lock = 0),
	-- Deduplicazione: se lo stesso Osepe appartiene a più aree,
	-- si tiene una sola riga per Id (la prima per IdArea)
	cteDedup AS (
		SELECT
			Id,
			IdDominio = MIN(IdDominio),
			IdArea = MIN(IdArea),
			Area = MIN(Area)
		FROM cte
		GROUP BY Id
	)
	-- Ramo 1: Osepe come sede diretta
	SELECT
		c.Id,
		Tipo = 'S',
		IdSede = s.IdAziendaInterna,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
		ImpiegabileServizi = CAST(0 AS BIT)
	FROM
		cteDedup c
		INNER JOIN dbo.tblSedi s ON c.Id = s.Id
	WHERE s.Lock = 0
	UNION ALL -- rami mutualmente esclusivi per tipo e JOIN

	-- Ramo 2: sotto-sedi dell'Osepe
	SELECT
		s.Id,
		Tipo = 'S',
		IdSede = s.IdAziendaInterna,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
		ImpiegabileServizi = CAST(0 AS BIT)
	FROM
		cteDedup c
		INNER JOIN dbo.tblSedi s ON c.Id = s.IdParent
	WHERE s.Lock = 0
	UNION ALL

	-- Ramo 3: oggetti dell'Osepe
	SELECT
		c.Id,
		Tipo = 'O',
		IdSede = s.IdSede,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.Nome,
		s.ImpiegabileServizi
	FROM
		cteDedup c
		INNER JOIN dbo.tblOggetti s ON c.Id = s.Id
	WHERE s.Lock = 0
	UNION ALL

	-- Ramo 4: persone dell'Osepe
	SELECT
		c.Id,
		Tipo = 'P',
		IdSede = s.IdSede,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.NomeCompleto,
		s.ImpiegabileServizi
	FROM
		cteDedup c
		INNER JOIN dbo.tblPersone s ON c.Id = s.Id
	WHERE s.Lock = 0);
GO

-- ===== ufnPersone_get_CondiviseByUtente_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnPersone_get_CondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- GROUP BY su s.Id per deduplicare: la stessa persona può apparire più volte
	-- se associata a più aree o se più sedi interne appartengono alla stessa area
	SELECT
		s.Id,
		s.IdSede,
		IdDominio = MIN(ui.IdDominio),
		Disabilitata = MIN(CAST(s.Disabilitata AS TINYINT)),
		IdArea = MIN(a.Id),
		Area = MIN(a.Nome)
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
		INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id = ai.IdSede
		INNER JOIN dbo.tblAree a ON ai.Id = a.Id
		INNER JOIN dbo.tblAreeOsepe ae ON a.Id = ae.Id
		INNER JOIN dbo.tblPersone s ON ae.IdOsepe = s.Id
	WHERE
		a.Lock = 0
		AND s.Lock = 0
	GROUP BY s.Id, s.IdSede
);
GO

-- ===== ufnPersone_get_NonCondiviseByUtente_List
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

-- ===== ufnSedi_get_AziendeEsterneCondiviseByUtente_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeEsterneCondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- La distinzione Admin/Utente è gestita da ufnSedi_get_AziendeInterneByUtente_List:
	-- Admin  → vede tutte le aziende interne del dominio
	-- Utente → vede solo le aziende interne direttamente associate
	-- In entrambi i casi vengono restituite le aziende esterne condivise
	-- collegate tramite le aree delle sedi interne accessibili.
	-- GROUP BY su s.Id per deduplicare: la stessa sede esterna può apparire
	-- più volte se associata a più aree o se più sedi interne appartengono
	-- alla stessa area.
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		IdDominio = MIN(ui.IdDominio),
		Disabilitata = MIN(CAST(s.Disabilitata AS TINYINT)),
		IdArea = MIN(a.Id),
		Area = MIN(a.Nome)
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
		INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id = ai.IdSede
		INNER JOIN dbo.tblAree a ON ai.Id = a.Id
		INNER JOIN dbo.tblAreeOsepe ae ON a.Id = ae.Id
		INNER JOIN dbo.tblSedi s ON ae.IdOsepe = s.Id
	WHERE
		a.Lock = 0
		AND s.Lock = 0
	GROUP BY s.Id, s.IdParent, s.IdAziendaInterna
);
GO

-- ===== ufnSedi_get_AziendeEsterneNonCondiviseByUtente_List
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

-- ===== ufnSedi_get_SediEsterneByUtente_List
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

-- ===== ufnOggetti_get_ByUtente_List
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

-- ===== ufnOsepe_get_NonCondiviseByUtente_List
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

-- ===== ufnPersone_get_ByUtente_List
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

-- ===== ufnSedi_get_SediByUtente_List
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

-- ===== ufnOsepe_get_ByUtente_List
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
