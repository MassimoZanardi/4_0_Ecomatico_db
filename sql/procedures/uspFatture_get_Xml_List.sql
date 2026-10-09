SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati per il file XML della fattura elettronica delle fatture clienti dell'intervallo (ufnFatture_get_XmlIntervallo).
-- @Elenco sceglie che cosa restituire, sempre per le stesse fatture:
--   T testate: fattura, azienda che emette (Ced*, con i dati fiscali) e cliente (Ces*), fattura di riferimento
--     della nota di credito, banca dell'azienda, totali. Al massimo 101 righe: la 101a dice a chi chiama che
--     l'intervallo supera il limite di 100 fatture per generazione.
--   R righe, in ordine di posizione; A rate, in ordine di scadenza.
-- Con @Id si lavora su quella sola fattura (generazione dalla scheda o con allegati): intervallo e anno non servono.
-- I controlli sui dati mancanti e la composizione del file sono nell'applicazione (FatturaXmlService).
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Xml_List
	@IdSessione CHAR(16) = NULL,
	@Elenco CHAR(1) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@Sezionale CHAR(1) = NULL,
	@EscludiGenerate BIT = 0,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Elenco = UPPER(NULLIF(LTRIM(RTRIM(@Elenco)), ''));
		SET @Sezionale = UPPER(NULLIF(LTRIM(RTRIM(@Sezionale)), ''));
		SET @EscludiGenerate = ISNULL(@EscludiGenerate, 0);
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Elenco IS NULL OR @Elenco NOT IN ('T', 'R', 'A')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Elenco deve essere T (testate), R (righe) o A (rate)';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND (@Anno IS NULL OR @Anno < 1900 OR @Anno > 9998)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''anno delle fatture';
			GOTO BRANCH_END;
		END
		IF @DalNumero > @AlNumero
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero iniziale non può essere maggiore di quello finale';
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

		IF @Elenco = 'T'
			SELECT TOP (101)
				f.Id,
				f.Numero,
				f.Sezionale,
				f.DataEmissione,
				f.IdTipo,
				f.IdValuta,
				f.IdModalita,
				f.Causale,
				Bollo = ISNULL(f.Bollo, 0),
				SplitPayment = ISNULL(f.SplitPayment, 0),
				f.Ordine,
				f.DataOrdine,
				f.CodiceCig,
				f.CodiceCup,
				f.DataXml,
				RiferimentoNumero = rf.Numero,
				RiferimentoSezionale = rf.Sezionale,
				RiferimentoData = rf.DataEmissione,
				BancaNome = b.Nome,
				BancaIban = b.Iban,
				BancaBic = b.Bic,
				t.Imponibile,
				t.Iva,
				t.Ritenuta,
				t.Totale,
				t.NettoAPagare,
				CedIdTipo = a.IdTipo,
				CedNome = a.Nome,
				CedCognome = a.Cognome,
				CedPartitaIva = a.PartitaIva,
				CedCodiceFiscale = a.CodiceFiscale,
				CedIndirizzo = ai.Indirizzo,
				CedNumeroCivico = ai.NumeroCivico,
				CedCap = ai.CAP,
				CedComune = ac.Nome,
				CedProvincia = ap.Sigla,
				CedNazione = an.Sigla,
				d.IdRegimeFiscale,
				ReaUfficio = dp.Sigla,
				d.NumeroRea,
				d.CapitaleSociale,
				d.SocioUnico,
				d.StatoLiquidazione,
				d.IdRitenutaTipo,
				d.IdRitenutaCausale,
				f.IdClienteFornitore,
				CesIdTipo = s.IdTipo,
				CesNome = s.Nome,
				CesCognome = s.Cognome,
				CesNomeCompleto = s.NomeCompleto,
				CesPartitaIva = s.PartitaIva,
				CesCodiceFiscale = s.CodiceFiscale,
				CesIndirizzo = si.Indirizzo,
				CesNumeroCivico = si.NumeroCivico,
				CesCap = si.CAP,
				CesComune = sc.Nome,
				CesProvincia = sp.Sigla,
				CesNazione = sn.Sigla,
				c.CodiceDestinatario,
				c.PecDestinatario
			FROM
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate, @Id) x
				INNER JOIN dbo.tblFatture f ON x.Id = f.Id
				INNER JOIN dbo.tblSedi a ON f.IdSede = a.Id
				LEFT JOIN dbo.tblSediIndirizzi asi ON a.Id = asi.Id
				LEFT JOIN dbo.tblIndirizzi ai ON asi.IdIndirizzo = ai.Id
				LEFT JOIN dbo.tblComuni ac ON ai.IdComune = ac.Id
				LEFT JOIN dbo.tblProvince ap ON ac.IdProvincia = ap.Id
				LEFT JOIN dbo.tblNazioni an ON ai.IdNazione = an.Id
				LEFT JOIN dbo.tblFattureDatiFiscali d ON a.Id = d.Id
				LEFT JOIN dbo.tblProvince dp ON d.IdProvinciaRea = dp.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblSediIndirizzi ssi ON s.Id = ssi.Id
				LEFT JOIN dbo.tblIndirizzi si ON ssi.IdIndirizzo = si.Id
				LEFT JOIN dbo.tblComuni sc ON si.IdComune = sc.Id
				LEFT JOIN dbo.tblProvince sp ON sc.IdProvincia = sp.Id
				LEFT JOIN dbo.tblNazioni sn ON si.IdNazione = sn.Id
				LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
			ORDER BY
				f.Numero,
				f.Sezionale,
				f.Id;
		ELSE IF @Elenco = 'R'
			SELECT
				r.IdFattura,
				r.Pos,
				r.Descrizione,
				ConImporti = CAST(IIF(i.Id IS NULL, 0, 1) AS BIT),
				i.Quantita,
				i.Importo,
				UnitaMisuraCodice = u.Codice,
				i.IdAliquotaIva,
				AliquotaValore = v.Valore,
				v.IdNatura,
				NaturaNome = n.Nome,
				v.RiferimentoNormativo,
				RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0),
				Imponibile = CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2))
			FROM
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate, @Id) x
				INNER JOIN dbo.tblFattureRighe r ON x.Id = r.IdFattura
				LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				LEFT JOIN dbo.tblUnitaMisura u ON i.IdUnitaMisura = u.Id
				LEFT JOIN dbo.tblAliquoteIva v ON i.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblAliquoteIvaNatura n ON v.IdNatura = n.Id
			ORDER BY
				r.IdFattura,
				r.Pos,
				r.Id;
		ELSE
			SELECT
				r.IdFattura,
				r.DataScadenza,
				Importo = CAST(ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) AS DECIMAL(18, 2))
			FROM
				dbo.ufnFatture_get_XmlIntervallo(@IdSessione, @DalNumero, @AlNumero, @Anno, @Sezionale, @EscludiGenerate, @Id) x
				INNER JOIN dbo.tblFattureRate r ON x.Id = r.IdFattura
			ORDER BY
				r.IdFattura,
				r.DataScadenza,
				r.Id;

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
