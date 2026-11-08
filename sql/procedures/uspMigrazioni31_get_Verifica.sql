SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1: verifica preliminare, in sola lettura (nessuna scrittura ne' sulla 3.1 ne' sulla 4.0).
-- Perimetro, abbinamenti e anomalie sono calcolati da uspMigrazioni31_get_Perimetro, la stessa SP che usa
-- uspMigrazioni31_ins prima di scrivere: la verifica mostra esattamente cio' che la migrazione controllera'.
-- Le tabelle temporanee create qui sono quelle che uspMigrazioni31_get_Perimetro si aspetta (stessa struttura anche in
-- uspMigrazioni31_ins).
-- Restituisce quattro result set:
-- 1) riepilogo per registro (registrazioni importabili per gruppo A-D, escluse, inviate e non inviate al RENTRI);
-- 2) abbinamento delle aziende interne 3.1 (del perimetro e altre usate nelle registrazioni) a quelle del dominio 4.0
--    per codice fiscale o partita IVA;
-- 3) abbinamento dei soggetti ai soggetti 4.0 dell'azienda proprietaria, per codice fiscale o partita IVA;
-- 4) anomalie (Livello E = blocca la migrazione, W = record scartato o dato perso, I = informazione).
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_get_Verifica
	@IdDominioDa VARCHAR(50) = NULL,
	@IdSedeInternaDa VARCHAR(50) = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @dataRentri DATE = '20250213';

		CREATE TABLE #aziende (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
		);

		CREATE TABLE #registri (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdTipo CHAR(3) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #registrazioni (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdMovimento UNIQUEIDENTIFIER NULL,
			IdRegistro CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdCausale CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			Operazione31 CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			[Data] DATE NULL,
			Numero INT NULL,
			Lock TINYINT NULL,
			Inviata BIT NOT NULL,
			Importabile BIT NOT NULL,
			Gruppo CHAR(1) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #abbinamenti (
			IdAzienda31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Mappata BIT NOT NULL,
			Abbinamenti INT NOT NULL,
			IdAzienda40 CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #autorizzazioni (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
		);

		CREATE TABLE #sedi (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Radice31 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			InternaEsterna CHAR(1) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #soggetti (
			IdSoggetto31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdProprietario31 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			ProprietarioCambiato BIT NOT NULL,
			Mappato BIT NOT NULL,
			Abbinamenti INT NOT NULL,
			IdSoggetto40 CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #anomalie (
			Livello CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL,
			Controllo VARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL,
			Tabella VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			IdOrigine VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Dettaglio NVARCHAR(500) COLLATE DATABASE_DEFAULT NULL
		);

		EXEC dbo.uspMigrazioni31_get_Perimetro
			@IdDominioDa = @IdDominioDa,
			@IdSedeInternaDa = @IdSedeInternaDa,
			@IdDominioA = @IdDominioA;

		-- 1) Riepilogo per registro
		SELECT
			Azienda = az.Nome,
			Sede = sd.Nome,
			IdRegistro = g.Id,
			Registro = rg.Nome,
			Tipo = g.IdTipo,
			Importabili = SUM(IIF(r.Importabile = 1, 1, 0)),
			Dal2025 = SUM(IIF(r.Gruppo = 'A', 1, 0)),
			CarichiPrecedenti = SUM(IIF(r.Gruppo = 'B', 1, 0)),
			ScarichiPrecedenti = SUM(IIF(r.Gruppo = 'C', 1, 0)),
			TrattamentiPrecedenti = SUM(IIF(r.Gruppo = 'D', 1, 0)),
			PrecedentiNonNecessarie = SUM(IIF(r.Importabile = 0 AND ISNULL(r.Lock, 0) = 0, 1, 0)),
			BozzeOCancellate = SUM(IIF(ISNULL(r.Lock, 0) <> 0, 1, 0)),
			DataMin = MIN(IIF(r.Importabile = 1, r.[Data], NULL)),
			DataMax = MAX(IIF(r.Importabile = 1, r.[Data], NULL)),
			InviateRentri = SUM(IIF(r.Importabile = 1 AND r.Inviata = 1, 1, 0)),
			NonInviatePrimaRentri = SUM(IIF(r.Importabile = 1 AND r.Inviata = 0 AND r.[Data] < @dataRentri, 1, 0)),
			NonInviateDopoRentri = SUM(IIF(r.Importabile = 1 AND r.Inviata = 0 AND r.[Data] >= @dataRentri, 1, 0))
		FROM
			#registri g
			INNER JOIN dbo.syn31RifiutiRegistri rg ON g.Id = rg.IDRegistro COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.syn31Sedi sd ON g.IdSede = sd.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.syn31Sedi az ON g.IdAzienda = az.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN #registrazioni r ON g.Id = r.IdRegistro
		GROUP BY az.Nome, sd.Nome, g.Id, rg.Nome, g.IdTipo
		ORDER BY az.Nome, sd.Nome, rg.Nome;

		-- 2) Abbinamento delle aziende interne
		SELECT
			IdAzienda31 = b.IdAzienda31,
			Azienda31 = s.Nome,
			CodiceFiscale = s.CodiceFiscale,
			PartitaIva = s.PartitaIva,
			b.Abbinamenti,
			b.IdAzienda40,
			Azienda40 = x.Nome,
			Esito = CASE
				WHEN b.Mappata = 1 THEN 'Gia'' migrata'
				WHEN b.Abbinamenti = 0 THEN 'Da creare'
				WHEN b.Abbinamenti = 1 THEN 'Abbinata'
				ELSE 'Ambigua'
			END
		FROM
			#abbinamenti b
			INNER JOIN dbo.syn31Sedi s ON b.IdAzienda31 = s.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblSedi x ON b.IdAzienda40 = x.Id
		ORDER BY s.Nome;

		-- 3) Abbinamento dei soggetti
		SELECT
			IdSoggetto31 = g.IdSoggetto31,
			Soggetto31 = COALESCE(s.Cognome + ' ' + s.Nome, s.Nome),
			CodiceFiscale = s.CodiceFiscale,
			PartitaIva = s.PartitaIva,
			Proprietario31 = p.Nome,
			g.Abbinamenti,
			g.IdSoggetto40,
			Soggetto40 = x.NomeCompleto,
			Esito = CASE
				WHEN g.Mappato = 1 THEN 'Gia'' migrato'
				WHEN g.Abbinamenti = 0 THEN 'Da creare'
				WHEN g.Abbinamenti = 1 THEN 'Abbinato'
				ELSE 'Ambiguo'
			END
		FROM
			#soggetti g
			INNER JOIN dbo.syn31Sedi s ON g.IdSoggetto31 = s.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.syn31Sedi p ON g.IdProprietario31 = p.IDSede COLLATE DATABASE_DEFAULT
			LEFT JOIN dbo.tblSedi x ON g.IdSoggetto40 = x.Id
		ORDER BY p.Nome, s.Nome;

		-- 4) Anomalie
		SELECT Livello, Controllo, Tabella, IdOrigine, Dettaglio
		FROM #anomalie
		ORDER BY
			CASE Livello
				WHEN 'E' THEN 1
				WHEN 'W' THEN 2
				ELSE 3
			END,
			Controllo,
			Tabella,
			IdOrigine;
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
