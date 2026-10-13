SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione di un documento (blocco "Cliente a cui fatturare", comune alle schede di registrazioni dei
-- rifiuti, DDT di magazzino e servizi): cliente indicato sul documento, spunta "Non fatturabile", fattura in
-- cui è finito e l'anteprima di ciò che la generazione automatica userebbe ("Verifica importo e cliente":
-- cliente, importo, contratto, totale e avvisi). Le righe dell'anteprima: uspFattureDocumenti_get_Righe.
-- @IdModulo: RIF registrazione dei rifiuti, MAG movimento di magazzino con il suo DDT (SRV non ancora gestito:
-- nessuna riga). Per il DDT il confronto è per riga: importo, priorità e contratto si vedono solo se sono gli
-- stessi per tutte le righe.
-- Sempre una riga al massimo; nessuna riga (e nessun errore) se il blocco non va mostrato: modulo Offerte e
-- contratti non attivo sul dominio, documento non accessibile, operazione non fatturabile, rettifica. Così la
-- scheda del documento non dipende da questo modulo.
--   Modificabile: permesso di modifica sul documento, documento confermato e non ancora fatturato.
--   Fatturabile: la generazione automatica lo fatturerebbe (nessun avviso bloccante).
--   Avvisi: testi separati da '|'.
-- L'azienda è quella del documento (per i rifiuti, del registro), non quella del contesto della sessione.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Solo registrazioni dei rifiuti, con il modulo Offerte e contratti attivo sul dominio e almeno la
		-- lettura delle registrazioni
		DECLARE @permesso TINYINT = dbo.ufnFunzioni_get_PermessoBySessione('RRG', @IdSessione);
		IF ISNULL(@IdModulo, '') = 'RIF'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND @permesso >= 1
		BEGIN
			SELECT
				a.Id,
				IdModulo = CAST('RIF' AS CHAR(3)),
				Modificabile = CAST(IIF(@permesso >= 2 AND a.Lock = 0 AND a.IdFattura IS NULL, 1, 0) AS BIT),
				IdClienteIndicato = a.IdClienteIndicato,
				ClienteIndicato = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
				a.NonFatturabile,
				a.IdFattura,
				Fattura = IIF(a.IdFattura IS NULL, NULL, IIF(f.IdTipo = 'TD00', 'Pre-fattura', 'Fattura'))
					+ ISNULL(' ' + CAST(f.Numero AS VARCHAR(10)) + ISNULL('/' + f.Sezionale, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103), ''),
				-- Anteprima
				a.IdClienteFornitore,
				Cliente = sc.NomeCompleto + ISNULL(' ' + sc.IndirizzoCompleto, ''),
				a.ClienteOrigine,
				ClienteOrigineDescrizione = CASE a.ClienteOrigine
					WHEN 'D' THEN 'indicato sulla registrazione'
					WHEN 'C' THEN 'dal contratto dell''importo'
					WHEN 'P' THEN 'produttore del rifiuto (importo standard)'
				END,
				a.IdImporto,
				Importo = i.Nome,
				Priorita = p.Nome,
				Contratto = CASE
					WHEN a.IdImporto IS NULL THEN NULL
					WHEN a.IdOffertaContratto IS NULL THEN 'Nessuno (importo standard)'
					ELSE 'Contratto' + ISNULL(' ' + so.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				END,
				Totale = t.Totale,
				Fatturabile = CAST(IIF(
					a.Lock = 0 AND a.IsAnnullata = 0 AND a.NonFatturabile = 0 AND a.IdFattura IS NULL
					AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0, 1, 0) AS BIT),
				Avvisi = CAST(STUFF(
					IIF(a.Lock <> 0, '|La registrazione non è ancora salvata: salvarla prima di fatturarla', '')
					+ IIF(a.IdFattura IS NOT NULL, '|La registrazione è già stata fatturata', '')
					+ IIF(a.NonFatturabile = 1, '|La registrazione è indicata come non fatturabile', '')
					+ IIF(a.IsAnnullata = 1, '|La registrazione è annullata: non viene fatturata', '')
					+ IIF(a.IdImporto IS NULL, '|Nessun importo coincide con la registrazione: non viene fatturata', '')
					+ IIF(a.IdImportoScartato IS NOT NULL, '|L''importo "' + ISNULL(isc.Nome, '') + '" coincide con la registrazione, ma il suo contratto non è valido alla data della registrazione'
						+ IIF(a.IdImporto IS NOT NULL AND a.IdOffertaContratto IS NULL, ': è stato applicato l''importo standard', ''), '')
					+ IIF(a.IdClienteFornitore IS NULL, '|Cliente non determinato: il produttore non ha una scheda cliente. Indicare il cliente sulla registrazione', '')
					+ IIF(a.IdClienteFornitore IS NOT NULL AND ISNULL(t.SenzaIva, 0) > 0, '|Aliquota IVA non indicata né sulle righe dell''importo né sulla scheda del cliente', '')
					+ IIF(a.IdImporto IS NOT NULL AND ISNULL(t.Righe, 0) = 0, '|L''importo non ha righe applicabili a questa registrazione', '')
					+ IIF(a.IdImporto IS NOT NULL AND q.RigheQuantita > 0 AND ISNULL(t.RigheQuantita, 0) = 0, '|L''importo non ha righe per l''unità di misura della registrazione (' + ISNULL(a.IdUnitaMisura, 'non indicata') + ')', '')
					, 1, 1, '') AS VARCHAR(2000))
			FROM
				dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
				LEFT JOIN dbo.tblClientiFornitori ci ON a.IdClienteIndicato = ci.Id
				LEFT JOIN dbo.tblSedi si ON ci.IdSede = si.Id
				LEFT JOIN dbo.tblClientiFornitori cc ON a.IdClienteFornitore = cc.Id
				LEFT JOIN dbo.tblSedi sc ON cc.IdSede = sc.Id
				LEFT JOIN dbo.tblFatture f ON a.IdFattura = f.Id
				LEFT JOIN dbo.tblImporti i ON a.IdImporto = i.Id
				LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
				LEFT JOIN dbo.tblImporti isc ON a.IdImportoScartato = isc.Id
				LEFT JOIN dbo.tblOfferteContratti oc ON a.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori co ON oc.IdClienteFornitore = co.Id
				LEFT JOIN dbo.tblSedi so ON co.IdSede = so.Id
				OUTER APPLY (
					-- Righe che entrano in fattura: totale, numero, e quante sono a quantità (KG, T, L)
					SELECT
						Totale = SUM(ISNULL(g.Imponibile, 0)),
						Righe = COUNT(*),
						SenzaIva = SUM(IIF(g.SolaDescrizione = 0 AND g.IdAliquotaIva IS NULL, 1, 0)),
						RigheQuantita = SUM(IIF(g.SolaDescrizione = 0 AND g.MinimoFatturabile = 0 AND g.IdTipo <> 'RM', 1, 0))
					FROM dbo.ufnImportiRifiuti_get_ApplicazioneRighe(@Id) g
				) t
				OUTER APPLY (
					-- Righe a quantità dell'importo, comprese quelle che non valgono per l'unità della registrazione
					SELECT RigheQuantita = COUNT(*)
					FROM dbo.tblImportiRighe g
					WHERE
						g.IdImporto = a.IdImporto
						AND g.Importo IS NOT NULL
						AND ISNULL(g.MinimoFatturabile, 0) = 0
						AND g.IdTipo <> 'RM'
				) q
			WHERE
				a.IsFatturabile = 1
				AND a.IsRettifica = 0
			OPTION (RECOMPILE);
		END

		-- DDT di magazzino (Id = movimento), con il modulo Offerte e contratti attivo sul dominio e almeno la
		-- lettura dei movimenti. L'importo è uno solo per DDT e deve avere una riga per ogni suo articolo o materiale
		DECLARE @permessoMag TINYINT = dbo.ufnFunzioni_get_PermessoBySessione('MAG', @IdSessione);
		IF ISNULL(@IdModulo, '') = 'MAG'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND @permessoMag >= 1
		BEGIN
			SELECT
				a.Id,
				IdModulo = CAST('MAG' AS CHAR(3)),
				Modificabile = CAST(IIF(@permessoMag >= 2 AND a.Lock = 0 AND a.IdFattura IS NULL, 1, 0) AS BIT),
				IdClienteIndicato = a.IdClienteIndicato,
				ClienteIndicato = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
				a.NonFatturabile,
				a.IdFattura,
				Fattura = IIF(a.IdFattura IS NULL, NULL, IIF(f.IdTipo = 'TD00', 'Pre-fattura', 'Fattura'))
					+ ISNULL(' ' + CAST(f.Numero AS VARCHAR(10)) + ISNULL('/' + f.Sezionale, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103), ''),
				-- Anteprima
				a.IdClienteFornitore,
				Cliente = sc.NomeCompleto + ISNULL(' ' + sc.IndirizzoCompleto, ''),
				a.ClienteOrigine,
				ClienteOrigineDescrizione = CASE a.ClienteOrigine
					WHEN 'D' THEN 'indicato sul DDT'
					WHEN 'C' THEN 'dal contratto dell''importo'
					WHEN 'P' THEN 'destinatario del DDT (importo standard)'
				END,
				a.IdImporto,
				Importo = i.Nome,
				Priorita = p.Nome,
				Contratto = CASE
					WHEN a.IdImporto IS NULL THEN NULL
					WHEN a.IdOffertaContratto IS NULL THEN 'Nessuno (importo standard)'
					ELSE 'Contratto' + ISNULL(' ' + so.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				END,
				Totale = t.Totale,
				Fatturabile = CAST(IIF(
					a.Lock = 0 AND a.NonFatturabile = 0 AND a.IdFattura IS NULL
					AND a.Righe > 0 AND a.IdImporto IS NOT NULL AND a.RigheSenzaImporto = 0
					AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0, 1, 0) AS BIT),
				Avvisi = CAST(STUFF(
					IIF(a.Lock <> 0, '|Il DDT non è ancora salvato: salvarlo prima di fatturarlo', '')
					+ IIF(a.IdFattura IS NOT NULL, '|Il DDT è già stato fatturato', '')
					+ IIF(a.NonFatturabile = 1, '|Il DDT è indicato come non fatturabile', '')
					+ IIF(a.Righe = 0, '|Il DDT non ha righe di articoli o di materiali: non viene fatturato', '')
					+ IIF(a.Righe > 0 AND a.IdImporto IS NULL, '|Nessun importo coincide con il DDT: non viene fatturato', '')
					+ IIF(a.IdImporto IS NOT NULL AND a.RigheSenzaImporto > 0, '|L''importo "' + ISNULL(i.Nome, '') + '" non ha una riga per ' + ISNULL(n.Voci, '')
						+ ': il DDT non viene fatturato', '')
					+ IIF(a.IdImportoScartato IS NOT NULL, '|L''importo "' + ISNULL(isc.Nome, '') + '" coincide con il DDT, ma il suo contratto non è valido alla data del DDT'
						+ IIF(a.IdImporto IS NOT NULL AND a.IdOffertaContratto IS NULL, ': è stato applicato l''importo standard', ''), '')
					+ IIF(a.IdClienteFornitore IS NULL, '|Cliente non determinato: il destinatario non ha una scheda cliente. Indicare il cliente sul DDT', '')
					+ IIF(a.IdClienteFornitore IS NOT NULL AND ISNULL(t.SenzaIva, 0) > 0, '|Aliquota IVA non indicata né sulle righe dell''importo né sulla scheda del cliente', '')
					, 1, 1, '') AS VARCHAR(2000))
			FROM
				dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
				LEFT JOIN dbo.tblClientiFornitori ci ON a.IdClienteIndicato = ci.Id
				LEFT JOIN dbo.tblSedi si ON ci.IdSede = si.Id
				LEFT JOIN dbo.tblClientiFornitori cc ON a.IdClienteFornitore = cc.Id
				LEFT JOIN dbo.tblSedi sc ON cc.IdSede = sc.Id
				LEFT JOIN dbo.tblFatture f ON a.IdFattura = f.Id
				LEFT JOIN dbo.tblImporti i ON a.IdImporto = i.Id
				LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
				LEFT JOIN dbo.tblImporti isc ON a.IdImportoScartato = isc.Id
				LEFT JOIN dbo.tblOfferteContratti oc ON a.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori co ON oc.IdClienteFornitore = co.Id
				LEFT JOIN dbo.tblSedi so ON co.IdSede = so.Id
				OUTER APPLY (
					-- Righe che entrano in fattura
					SELECT
						Totale = SUM(ISNULL(g.Imponibile, 0)),
						Righe = COUNT(*),
						SenzaIva = SUM(IIF(g.SolaDescrizione = 0 AND g.IdAliquotaIva IS NULL, 1, 0))
					FROM dbo.ufnImportiMagazzino_get_RigheFattura(@Id, a.IdClienteFornitore) g
				) t
				OUTER APPLY (
					-- Articoli e materiali del DDT che l'importo applicato non prezza, per l'avviso
					SELECT Voci = STRING_AGG(CAST('"' + ISNULL(r.Voce, '') + '"' AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY ISNULL(r.Pos, 0), r.IdRiga)
					FROM dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, NULL, NULL, NULL, 0) r
					WHERE r.IdRigaImporto IS NULL
				) n
			WHERE a.IsFatturabile = 1
			OPTION (RECOMPILE);
		END

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
