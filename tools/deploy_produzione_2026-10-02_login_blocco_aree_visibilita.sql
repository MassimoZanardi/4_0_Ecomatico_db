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
