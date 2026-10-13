SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi magazzino > Azioni > Verifica importi: quali importi dell'azienda interna
-- corrente coinciderebbero con un DDT che avesse i valori indicati, e quale verrebbe applicato. La regola di
-- coincidenza e la classe dell'importo sono quelle della fatturazione (ufnImportiMagazzino_get_Coincidenti);
-- qui si restituiscono tutti gli importi che coincidono, non solo il primo.
--   @Data: data del DDT (decide la validità dei contratti); se manca, oggi.
--   @IdSedePartenza: sede interna da cui parte la merce. Destinatario: @IdDestinatarioParent è il soggetto,
--   @IdDestinatario dove arriva la merce; indicato solo il soggetto, la sede è il soggetto stesso; indicata
--   solo la sede, il soggetto si ricava. @IdEtichetta: un'etichetta del DDT (una sola). Un valore non
--   indicato vuol dire che il DDT non ha quel dato: non coincide con gli importi che lo indicano.
--   @IdArticolo oppure @IdMateriale (facoltativi): un articolo o un materiale del DDT. Non entrano nella
--   scelta dell'importo: servono a dire se l'importo ha una riga con il suo prezzo (Prezzo), e se manca
--   (SenzaRigaArticolo = 1: un DDT con quell'articolo non sarebbe fatturabile con quell'importo).
-- Righe nell'ordine di scelta. Esito: A applicato; B coincide ma non viene applicato (Motivo); S di un contratto
-- non valido alla data; X di un'offerta o di un contratto cancellato (mai applicato).
-- Conflitto = 1: stessa priorità e stesso tipo (di contratto o standard) dell'importo applicato, lui compreso:
-- tra questi la fatturazione sceglie senza un criterio.
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get_Verifica
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@IdSedePartenza CHAR(16) = NULL,
	@IdDestinatarioParent CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSedePartenza = NULLIF(NULLIF(LTRIM(RTRIM(@IdSedePartenza)), ''), REPLICATE('0', 16));
		SET @IdDestinatarioParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatarioParent)), ''), REPLICATE('0', 16));
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), REPLICATE('0', 16));
		SET @IdArticolo = NULLIF(NULLIF(LTRIM(RTRIM(@IdArticolo)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), REPLICATE('0', 16));
		SET @Data = ISNULL(@Data, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
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

		-- Destinatario: soggetto e sede, come sul DDT
		IF @IdDestinatario IS NULL
			SET @IdDestinatario = @IdDestinatarioParent;
		ELSE IF @IdDestinatarioParent IS NULL
			SELECT @IdDestinatarioParent = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdDestinatario;

		WITH c AS (
			SELECT
				k.IdImporto,
				k.IdPriorita,
				k.IdOffertaContratto,
				k.Standard,
				k.Classe
			FROM dbo.ufnImportiMagazzino_get_Coincidenti(@idAzienda, @Data, @IdSedePartenza, @IdDestinatarioParent, @IdDestinatario) k
			-- L'importo che indica un'etichetta coincide solo se è quella del DDT
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
			SenzaRigaArticolo = CAST(IIF((@IdArticolo IS NOT NULL OR @IdMateriale IS NOT NULL) AND pr.Id IS NULL, 1, 0) AS BIT),
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
				-- Riga a quantità dell'importo per l'articolo o il materiale indicato
				SELECT TOP (1) x.Id, x.Importo
				FROM
					dbo.tblImportiRighe x
					INNER JOIN dbo.tblImportiRigheMagazzino xm ON x.Id = xm.Id
				WHERE
					x.IdImporto = t.IdImporto
					AND x.IdTipo = 'MA'
					AND x.Importo IS NOT NULL
					AND ISNULL(x.MinimoFatturabile, 0) = 0
					AND (xm.IdArticolo = @IdArticolo OR xm.IdMateriale = @IdMateriale)
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
