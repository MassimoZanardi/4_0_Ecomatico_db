SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Report: report del fatturato dell'azienda del contesto in un anno, dalle fatture clienti
-- (@Tipo = C) o fornitori (@Tipo = F), raggruppato per mese (@Raggruppamento = M), per cliente o fornitore (S)
-- o per conto (C). La stessa SP serve l'elenco a video e l'esportazione in Excel e in CSV: il nome di ogni
-- colonna è l'intestazione, nell'ordine in cui le colonne vanno mostrate (pagina comune dei report).
-- Contano le fatture attive (Lock = 0: né bozze né cancellate) con data di emissione nell'anno (per un
-- fornitore è la data del suo documento), escluse le pre-fatture (TD00); le note di credito (TD04) contano
-- con il segno meno. Senza @Anno vale l'anno in corso.
-- Per mese (sempre 12 righe) e per cliente o fornitore gli importi sono i totali delle fatture
-- (ufnFatture_get_Totali: il totale comprende il bollo). Per conto si sommano gli imponibili delle righe,
-- perché il conto sta sulla riga: niente IVA né totale, e le righe senza conto vanno in "(Senza conto)".
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che il limite è superato).
-- @Tipo = D, @Raggruppamento = N (P2.9, dal 2026-11-24): documenti dell'anno non ancora fatturati (registrazioni dei
-- rifiuti, DDT di magazzino e servizi eseguiti dei moduli attivi), dalla stessa funzione della procedura automatica
-- (ufnFattureGenera_get_Documenti, pre-fatture comprese), con il motivo per cui la procedura li lascerebbe fuori;
-- esclusi gli annullati e quelli indicati come non fatturabili. Senza il modulo Offerte e contratti nessuna riga.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Fatturato
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Raggruppamento CHAR(1) = NULL,
	@Anno INT = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Raggruppamento = UPPER(NULLIF(LTRIM(RTRIM(@Raggruppamento)), ''));
		SET @Anno = ISNULL(NULLIF(@Anno, 0), YEAR(GETDATE()));
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F', 'D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente), F (fornitore) o D (documenti da fatturare)';
			GOTO BRANCH_END;
		END
		IF @Raggruppamento IS NULL OR @Raggruppamento NOT IN ('M', 'S', 'C', 'N')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Raggruppamento deve essere M (mese), S (cliente o fornitore) o C (conto)';
			GOTO BRANCH_END;
		END
		IF @Anno < 1900 OR @Anno > 2100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare un anno compreso tra 1900 e 2100';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @dataDa DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @dataA DATE = DATEFROMPARTS(@Anno, 12, 31);

		-- Documenti non ancora fatturati (P2.9)
		IF @Tipo = 'D'
		BEGIN
			IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
			BEGIN
				SELECT TOP (0) Documento = CAST(NULL AS VARCHAR(200));
				GOTO BRANCH_END;
			END

			DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda FROM dbo.tblSessioni WHERE Id = @IdSessione);
			DECLARE @rifiuti BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0);
			DECLARE @magazzino BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0);
			DECLARE @servizi BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0);

			SELECT TOP (@MaxRighe + 1)
				Documento = CAST(CASE d.IdModulo
					WHEN 'MAG' THEN 'DDT' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)) + ISNULL('/' + dd.Sezionale, ''), '') + ISNULL(' - ' + sd.NomeCompleto, '')
					WHEN 'SRV' THEN 'Servizio' + ISNULL(' ' + tp.Nome, '') + ISNULL(' - ' + sd.NomeCompleto, '')
					ELSE 'Registrazione' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)), '')
						+ ISNULL(' - EER ' + e.Nome + IIF(e.Pericoloso = 1, '*', ''), '')
				END AS VARCHAR(200)),
				[Data] = CAST(d.[Data] AS DATE),
				Cliente = sc.NomeCompleto,
				Imponibile = CAST(d.Imponibile AS DECIMAL(18, 2)),
				[Pronto da fatturare] = d.Fatturabile,
				Motivo = CAST(CASE d.Esito
					WHEN 'P' THEN 'In pre-fattura del ' + ISNULL(CONVERT(VARCHAR(10), f.DataEmissione, 103), '')
					WHEN 'S' THEN 'Contratto non valido alla data: si applica l''importo standard'
					WHEN 'I' THEN IIF(d.IdImporto IS NOT NULL AND d.IdModulo IN ('MAG', 'SRV'),
						'L''importo "' + ISNULL(i.Nome, '') + '" non ha una riga per ' + IIF(d.IdModulo = 'SRV', 'tutte le risorse del servizio', 'tutti gli articoli o i materiali del DDT'),
						'Nessun importo coincide')
					WHEN 'C' THEN 'Cliente non determinato: ' + CASE d.IdModulo WHEN 'MAG' THEN 'il destinatario' WHEN 'SRV' THEN 'il richiedente' ELSE 'il produttore' END + ' non ha una scheda cliente'
					WHEN 'R' THEN 'L''importo non ha righe applicabili'
					WHEN 'V' THEN 'Aliquota IVA non indicata né sull''importo né sulla scheda del cliente'
				END AS VARCHAR(300))
			FROM
				dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @dataDa, @dataA, NULL, 1, @rifiuti, @magazzino, @servizi) d
				LEFT JOIN dbo.tblRifiutiEer e ON d.IdEer = e.Id
				LEFT JOIN dbo.tblMagazziniDdt dd ON d.IdModulo = 'MAG'
											  AND d.Id = dd.IdMovimento
				LEFT JOIN dbo.tblServizi sv ON d.IdModulo = 'SRV'
										 AND d.Id = sv.Id
				LEFT JOIN dbo.tblTipi tp ON sv.IdTipo = tp.Id
				LEFT JOIN dbo.tblSedi sd ON d.IdModulo IN ('MAG', 'SRV')
										 AND d.IdProduttore = sd.Id
				LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
				LEFT JOIN dbo.tblImporti i ON d.IdImporto = i.Id
				LEFT JOIN dbo.tblFatture f ON d.IdPreFattura = f.Id
			WHERE d.Esito NOT IN ('A', 'N')
			ORDER BY d.[Data], d.Numero, d.Id
			OPTION (RECOMPILE);

			GOTO BRANCH_END;
		END

		-- Fatture dell'anno, con il segno (meno per le note di credito) e i totali
		DECLARE @fatture TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Mese INT NOT NULL,
			Segno INT NOT NULL,
			Imponibile DECIMAL(18, 2) NOT NULL,
			Iva DECIMAL(18, 2) NOT NULL,
			Totale DECIMAL(18, 2) NOT NULL
		);

		INSERT @fatture (Id, IdClienteFornitore, Mese, Segno, Imponibile, Iva, Totale)
		SELECT
			f.Id,
			f.IdClienteFornitore,
			MONTH(f.DataEmissione),
			IIF(f.IdTipo = 'TD04', -1, 1),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Imponibile, 0),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Iva, 0),
			IIF(f.IdTipo = 'TD04', -1, 1) * ISNULL(t.Totale, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
		WHERE
			e.Id = @IdSessione
			AND f.Tipo = @Tipo
			AND f.Lock = 0
			AND f.DataEmissione >= @dataDa
			AND f.DataEmissione <= @dataA
			AND ISNULL(f.IdTipo, '') <> 'TD00';

		IF @Raggruppamento = 'M'
			SELECT
				[Mese] = n.Nome,
				[Documenti] = COUNT(f.Id),
				[Imponibile] = ISNULL(SUM(f.Imponibile), 0),
				[IVA] = ISNULL(SUM(f.Iva), 0),
				[Totale] = ISNULL(SUM(f.Totale), 0)
			FROM
				(VALUES (1, 'Gennaio'), (2, 'Febbraio'), (3, 'Marzo'), (4, 'Aprile'), (5, 'Maggio'), (6, 'Giugno'), (7, 'Luglio'), (8, 'Agosto'), (9, 'Settembre'), (10, 'Ottobre'), (11, 'Novembre'), (12, 'Dicembre')) n (Mese, Nome)
				LEFT JOIN @fatture f ON n.Mese = f.Mese
			-- Senza azienda nel contesto nessuna riga, come negli altri raggruppamenti
			WHERE EXISTS (SELECT 1 FROM dbo.tblSessioni e WHERE e.Id = @IdSessione AND NULLIF(e.IdAzienda, REPLICATE('0', 16)) IS NOT NULL)
			GROUP BY
				n.Mese,
				n.Nome
			ORDER BY n.Mese;
		ELSE IF @Raggruppamento = 'S' AND @Tipo = 'C'
			SELECT TOP (@MaxRighe + 1)
				[Cliente] = ISNULL(s.NomeCompleto, '(Senza cliente)'),
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Documenti] = COUNT(*),
				[Imponibile] = SUM(f.Imponibile),
				[IVA] = SUM(f.Iva),
				[Totale] = SUM(f.Totale)
			FROM
				@fatture f
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			GROUP BY
				s.Id,
				s.NomeCompleto,
				s.PartitaIva,
				s.CodiceFiscale
			ORDER BY
				SUM(f.Imponibile) DESC,
				s.NomeCompleto,
				s.Id;
		ELSE IF @Raggruppamento = 'S'
			SELECT TOP (@MaxRighe + 1)
				[Fornitore] = ISNULL(s.NomeCompleto, '(Senza fornitore)'),
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Documenti] = COUNT(*),
				[Imponibile] = SUM(f.Imponibile),
				[IVA] = SUM(f.Iva),
				[Totale] = SUM(f.Totale)
			FROM
				@fatture f
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			GROUP BY
				s.Id,
				s.NomeCompleto,
				s.PartitaIva,
				s.CodiceFiscale
			ORDER BY
				SUM(f.Imponibile) DESC,
				s.NomeCompleto,
				s.Id;
		ELSE
			SELECT TOP (@MaxRighe + 1)
				[Codice] = k.Codice,
				[Conto] = ISNULL(k.Nome, '(Senza conto)'),
				[Righe] = COUNT(*),
				[Imponibile] = SUM(f.Segno * CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2)))
			FROM
				@fatture f
				INNER JOIN dbo.tblFattureRighe r ON f.Id = r.IdFattura
				INNER JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				LEFT JOIN dbo.tblFattureConti k ON i.IdConto = k.Id
			GROUP BY
				k.Id,
				k.Codice,
				k.Nome
			ORDER BY
				IIF(k.Id IS NULL, 1, 0),
				k.Nome,
				k.Id;

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
