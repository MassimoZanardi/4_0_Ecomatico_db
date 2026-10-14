SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi servizi > Azioni > Verifica importi: quali importi dell'azienda interna corrente
-- coinciderebbero con un servizio che avesse i valori indicati, e quale verrebbe applicato. La regola di
-- coincidenza e la classe dell'importo sono quelle della fatturazione (ufnImportiServizi_get_Coincidenti); qui si
-- restituiscono tutti gli importi che coincidono, non solo il primo.
--   @Data: data del servizio (decide la validità dei contratti); se manca, oggi.
--   @IdTipo: tipo del servizio. Richiedente: @IdRichiedenteParent è il soggetto, @IdRichiedente la sede
--   richiedente; indicato solo il soggetto, la sede è il soggetto stesso; indicata solo la sede, il soggetto si
--   ricava. @IdSedeInterna: sede interna del calendario del servizio. @IdEtichetta: un'etichetta del servizio
--   (una sola). Un valore non indicato vuol dire che il servizio non ha quel dato: non coincide con gli importi
--   che lo indicano.
--   @IdOsepe (facoltativo): una risorsa del servizio. Non entra nella scelta dell'importo: serve a dire se
--   l'importo ha una riga con il suo prezzo (Prezzo), e se manca (SenzaRigaArticolo = 1: un servizio con quella
--   risorsa non sarebbe fatturabile con quell'importo; la colonna ha il nome della verifica di magazzino).
-- Righe nell'ordine di scelta. Esito: A applicato; B coincide ma non viene applicato (Motivo); S di un contratto
-- non valido alla data; X di un'offerta o di un contratto cancellato (mai applicato).
-- Conflitto = 1: stessa priorità e stesso tipo (di contratto o standard) dell'importo applicato, lui compreso:
-- tra questi la fatturazione sceglie senza un criterio.
CREATE OR ALTER PROCEDURE dbo.uspImportiServizi_get_Verifica
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@IdTipo CHAR(16) = NULL,
	@IdRichiedenteParent CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@IdSedeInterna CHAR(16) = NULL,
	@IdOsepe CHAR(16) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 16));
		SET @IdRichiedenteParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdRichiedenteParent)), ''), REPLICATE('0', 16));
		SET @IdRichiedente = NULLIF(NULLIF(LTRIM(RTRIM(@IdRichiedente)), ''), REPLICATE('0', 16));
		SET @IdSedeInterna = NULLIF(NULLIF(LTRIM(RTRIM(@IdSedeInterna)), ''), REPLICATE('0', 16));
		SET @IdOsepe = NULLIF(NULLIF(LTRIM(RTRIM(@IdOsepe)), ''), REPLICATE('0', 16));
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), REPLICATE('0', 16));
		SET @Data = ISNULL(@Data, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Servizi sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli importi sono quelli dell'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Richiedente: soggetto e sede, come sul servizio
		IF @IdRichiedente IS NULL
			SET @IdRichiedente = @IdRichiedenteParent;
		ELSE IF @IdRichiedenteParent IS NULL
			SELECT @IdRichiedenteParent = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdRichiedente;

		WITH c AS (
			SELECT
				k.IdImporto,
				k.IdPriorita,
				k.IdOffertaContratto,
				k.Standard,
				k.Classe
			FROM dbo.ufnImportiServizi_get_Coincidenti(@idAzienda, @Data, @IdTipo, @IdRichiedenteParent, @IdRichiedente, @IdSedeInterna) k
			-- L'importo che indica un'etichetta coincide solo se è quella del servizio
			WHERE
				k.IdEtichetta IS NULL
				OR k.IdEtichetta = @IdEtichetta
		),
		o AS (
			SELECT
				c.IdImporto,
				c.IdPriorita,
				c.IdOffertaContratto,
				c.Standard,
				c.Classe,
				N = ROW_NUMBER() OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto),
				-- Priorità e tipo del primo della classe: per i candidati, quelli dell'importo applicato
				PrimoPriorita = FIRST_VALUE(c.IdPriorita) OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto),
				PrimoStandard = FIRST_VALUE(c.Standard) OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto)
			FROM c
		),
		t AS (
			SELECT
				o.IdImporto,
				o.IdPriorita,
				o.IdOffertaContratto,
				o.Standard,
				o.Classe,
				o.N,
				Pari = CAST(IIF(o.Classe = 'V' AND ISNULL(o.IdPriorita, -1) = ISNULL(o.PrimoPriorita, -1) AND o.Standard = o.PrimoStandard, 1, 0) AS BIT),
				PrioritaPiuBassa = CAST(IIF(ISNULL(o.IdPriorita, -1) < ISNULL(o.PrimoPriorita, -1), 1, 0) AS BIT)
			FROM o
		)
		SELECT
			Id = t.IdImporto,
			i.Nome,
			Priorita = p.Nome,
			t.Standard,
			Cliente = cs.NomeCompleto,
			ContrattoTipo = oc.Tipo,
			ContrattoDataInizio = oc.DataInizio,
			ContrattoDataFine = oc.DataFine,
			Righe = (SELECT COUNT(*) FROM dbo.tblImportiRighe g WHERE g.IdImporto = t.IdImporto),
			Prezzo = pr.Importo,
			SenzaRigaArticolo = CAST(IIF(@IdOsepe IS NOT NULL AND pr.Id IS NULL, 1, 0) AS BIT),
			Esito = CAST(CASE
				WHEN t.Classe = 'V' AND t.N = 1 THEN 'A'
				WHEN t.Classe = 'V' THEN 'B'
				ELSE t.Classe
			END AS CHAR(1)),
			Conflitto = CAST(IIF(t.Pari = 1 AND SUM(CAST(t.Pari AS INT)) OVER () > 1, 1, 0) AS BIT),
			Motivo = CAST(CASE
				WHEN t.Classe = 'V' AND t.N = 1 THEN 'Importo applicato'
				WHEN t.Classe = 'V' AND t.PrioritaPiuBassa = 1 THEN 'Priorità più bassa dell''importo applicato'
				WHEN t.Classe = 'V' AND t.Pari = 1 THEN 'Stessa priorità e stesso tipo dell''importo applicato'
				WHEN t.Classe = 'V' THEN 'A parità di priorità prevale l''importo di un contratto'
				WHEN t.Classe = 'S' THEN 'Contratto non valido alla data: dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103) + ' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103)
				WHEN oc.Tipo = 'O' THEN 'Importo di un''offerta: non viene applicato'
				ELSE 'Contratto cancellato o senza validità: non viene applicato'
			END AS VARCHAR(100))
		FROM
			t
			INNER JOIN dbo.tblImporti i ON t.IdImporto = i.Id
			LEFT JOIN dbo.tblImportiPriorita p ON t.IdPriorita = p.Id
			LEFT JOIN dbo.tblOfferteContratti oc ON t.IdOffertaContratto = oc.Id
			LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
			LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
			OUTER APPLY (
				-- Riga a quantità dell'importo per la risorsa indicata
				SELECT TOP (1) x.Id, x.Importo
				FROM
					dbo.tblImportiRighe x
					INNER JOIN dbo.tblImportiRigheServizi xs ON x.Id = xs.Id
				WHERE
					x.IdImporto = t.IdImporto
					AND x.IdTipo = 'SU'
					AND x.Importo IS NOT NULL
					AND ISNULL(x.MinimoFatturabile, 0) = 0
					AND xs.IdOsepe = @IdOsepe
				ORDER BY ISNULL(x.Pos, 0), x.Id
			) pr
		ORDER BY
			CASE t.Classe WHEN 'V' THEN 0 WHEN 'S' THEN 1 ELSE 2 END,
			t.N
		OPTION (RECOMPILE);

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
