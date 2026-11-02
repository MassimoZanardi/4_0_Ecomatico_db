SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stampa di una fattura cliente: dati del documento, totali (ufnFatture_get_Totali) e layout di stampa
-- dell'azienda della fattura (ufnSediReport_get_Layout). Si stampano solo le fatture clienti salvate, anche la
-- pre-fattura (senza numero); non la bozza né una fattura fornitore. Righe, riepilogo IVA e rate sono in
-- uspFatture_get_Stampa_Righe, _Iva e _Rate.
-- Il cliente è sempre la sua sede legale; l'indirizzo di spedizione (Spedizione*) è, in ordine: l'amministratore
-- del cliente nell'azienda della fattura con l'incarico in corso alla data di emissione (sua sede amministrativa,
-- altrimenti sua sede legale), la sede amministrativa del cliente; se non c'è nessuno dei due resta NULL
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Stampa
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @tipo CHAR(1), @lock TINYINT;
		SELECT
			@tipo = f.Tipo,
			@lock = f.Lock
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock <= 2;

		IF @lock IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @tipo <> 'C'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si stampano solo le fatture clienti';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura non è ancora salvata: salvarla prima di stamparla';
			GOTO BRANCH_END;
		END

		SELECT
			f.IdTipo,
			TipoNome = tp.Nome,
			f.Numero,
			f.Sezionale,
			f.DataEmissione,
			ClienteNome = s.NomeCompleto,
			ClienteIndirizzo = s.IndirizzoCompleto,
			ClienteCodiceFiscale = s.CodiceFiscale,
			ClientePartitaIva = s.PartitaIva,
			SpedizioneNome = sp.Nome,
			SpedizioneIndirizzo = sp.Indirizzo,
			c.CodiceDestinatario,
			c.PecDestinatario,
			ModalitaNome = mo.Nome,
			RataNome = ra.Nome,
			RataInizioNome = ri.Nome,
			RataGiorniInizio = NULLIF(f.RataGiorniInizio, 0),
			BancaNome = b.Nome,
			BancaIban = b.Iban,
			f.Iban,
			f.Ordine,
			f.DataOrdine,
			f.CodiceCig,
			f.CodiceCup,
			f.Causale,
			RiferimentoTipoNome = rtp.Nome,
			RiferimentoNumero = rf.Numero,
			RiferimentoSezionale = rf.Sezionale,
			RiferimentoDataEmissione = rf.DataEmissione,
			SplitPayment = ISNULL(f.SplitPayment, 0),
			Valuta = f.IdValuta,
			t.Imponibile,
			t.Iva,
			t.Ritenuta,
			t.Bollo,
			t.Totale,
			t.NettoAPagare,
			r.IdLayout,
			r.Intestazione,
			r.PiePagina,
			r.IntestazioneColore,
			r.IntestazioneFontSize,
			r.IntestazioneAllineamento,
			r.PiePaginaColore,
			r.PiePaginaFontSize,
			r.PiePaginaAllineamento,
			r.Logo
		FROM
			dbo.tblFatture f
			CROSS APPLY dbo.ufnSediReport_get_Layout(f.IdSede) r
			OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
			LEFT JOIN dbo.tblFattureTipi tp ON f.IdTipo = tp.Id
			LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			LEFT JOIN dbo.tblPagamentiModalita mo ON f.IdModalita = mo.Id
			LEFT JOIN dbo.tblPagamentiRate ra ON f.IdRata = ra.Id
			LEFT JOIN dbo.tblPagamentiRateInizi ri ON f.IdRataInizio = ri.Id
			LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
			LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
			LEFT JOIN dbo.tblFattureTipi rtp ON rf.IdTipo = rtp.Id
			OUTER APPLY (
				SELECT TOP (1)
					x.Nome,
					x.Indirizzo
				FROM
					(
						-- 1. Amministratore del cliente (scheda attiva dell'azienda della fattura, incarico in corso)
						SELECT
							Ordine = 1,
							Nome = ams.NomeCompleto,
							Indirizzo = ISNULL(ama.IndirizzoCompleto, ams.IndirizzoCompleto)
						FROM
							dbo.tblAmministratoriSedi ax
							INNER JOIN dbo.tblAmministratori am ON ax.Id = am.Id
							INNER JOIN dbo.tblSedi ams ON am.IdSede = ams.Id
							OUTER APPLY (
								SELECT TOP (1)
									sa.IndirizzoCompleto
								FROM
									dbo.tblSedi sa
								WHERE
									sa.IdParent = ams.Id
									AND sa.IdTipo = 'A'
									AND sa.Lock < 2
									AND ISNULL(sa.Disabilitata, 0) = 0
									AND sa.IndirizzoCompleto IS NOT NULL
							) ama
						WHERE
							ax.IdSede = s.Id
							AND am.IdAziendaInterna = f.IdSede
							AND am.Lock = 0
							AND (ax.DataInizio IS NULL OR ax.DataInizio <= ISNULL(f.DataEmissione, CAST(GETDATE() AS DATE)))
							AND (ax.DataFine IS NULL OR ax.DataFine >= ISNULL(f.DataEmissione, CAST(GETDATE() AS DATE)))
						UNION ALL
						-- 2. Sede amministrativa del cliente
						SELECT
							Ordine = 2,
							Nome = s.NomeCompleto,
							Indirizzo = sa.IndirizzoCompleto
						FROM
							dbo.tblSedi sa
						WHERE
							sa.IdParent = s.Id
							AND sa.IdTipo = 'A'
							AND sa.Lock < 2
							AND ISNULL(sa.Disabilitata, 0) = 0
							AND sa.IndirizzoCompleto IS NOT NULL
					) x
				ORDER BY
					x.Ordine
			) sp
		WHERE f.Id = @Id;

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
