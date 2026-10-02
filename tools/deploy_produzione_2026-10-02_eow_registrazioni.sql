/*
Deploy produzione 2026-10-02 - EoW > Registrazioni

Nuova pagina /eow/registrazioni sotto Lotti: registrazioni M con le allocazioni sui lotti
(una riga per allocazione, M non allocate con lotto vuoto), Q.tà da allocare, filtri Lotto,
Materiale, Allocazione e date di registrazione.
- uspEoWRegistrazioni_get_List (nuova)
- uspEoWRegistrazioni_get_LottiSelectList (nuova)
- menu: tblPagine EWR, tblMenu AH5 (Pos 1), Magazzini/Allocazioni/Giacenze scalate di una posizione
- uspEoWLotti_get_List (fix): nella ricerca di EoW > Lotti "(Nessuno)" e "(Selezionare)" di
  Magazzino/Materiale (codici a zeri) filtravano su un codice inesistente, con elenco sempre vuoto

Da deployare insieme all'app (pagina Eow/Registrazioni). Lo script del menu è idempotente.
*/

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWRegistrazioni_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Allocazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Le select dei filtri usano gli zeri come "nessuna selezione"
		SET @IdLotto = NULLIF(NULLIF(LTRIM(RTRIM(@IdLotto)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @Allocazione = NULLIF(LTRIM(RTRIM(@Allocazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Allocazione: NULL = tutte, D = con quantità ancora da allocare, A = allocate per intero
		IF @Allocazione IS NOT NULL AND @Allocazione NOT IN ('D', 'A')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Allocazione deve essere D (Da allocare) o A (Allocate)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul Lotto indicato
		IF @IdLotto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Una riga per ogni allocazione (registrazione M + lotto); una registrazione M senza
		-- allocazioni ha una sola riga senza lotto. Valori operativi (viewRifiutiRegistrazioniEffettive):
		-- le rettifiche non ricevono mai allocazioni e non compaiono
		;WITH reg AS (
			SELECT
				r.Id,
				RegistroNome = g.Nome,
				r.Numero,
				r.Data,
				MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
				QuantitaOperativa = vo.Quantita,
				IsAnnullata = ISNULL(vo.IsAnnullata, 0),
				QuantitaAllocataTotale = ISNULL(a.QuantitaAllocata, 0),
				NumeroAllocazioni = ISNULL(a.NumeroAllocazioni, 0)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
				OUTER APPLY (
					SELECT
						QuantitaAllocata = SUM(q.Quantita),
						NumeroAllocazioni = COUNT(*)
					FROM dbo.tblEoWLottiRifiutiRegistrazioni q
					WHERE q.IdRegistrazione = r.Id) a
			WHERE
				r.Lock < 2
				AND o.IsMateriale = 1
				AND ISNULL(vo.IsRettifica, 0) = 0
				AND g.IdSede = @idSede
				AND
					(
					@IdMateriale IS NULL
					OR r.IdMateriale = @IdMateriale
					)
				AND
					(
					@DallaData IS NULL
					OR r.Data >= @DallaData
					)
				AND
					(
					@AllaData IS NULL
					OR r.Data < DATEADD(DAY, 1, @AllaData)
					)
		)
		SELECT
			reg.Id,
			-- Stato della registrazione (uguale su ogni sua riga): 0 = allocata per intero, 1 = allocata
			-- in parte o non allocata, 2 = anomalia (allocata più della quantità operativa)
			StatoValore = CASE
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale < 0 THEN 2
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale > 0 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale < 0
					THEN 'Allocata più della quantità della registrazione: allocati ' + FORMAT(reg.QuantitaAllocataTotale, 'N2', 'it-IT')
						+ ' kg su ' + FORMAT(reg.QuantitaOperativa, 'N2', 'it-IT') + ' kg'
				WHEN reg.NumeroAllocazioni = 0
					THEN 'Non allocata: ' + FORMAT(reg.QuantitaOperativa, 'N2', 'it-IT') + ' kg da allocare'
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale > 0
					THEN 'Allocata in parte: allocati ' + FORMAT(reg.QuantitaAllocataTotale, 'N2', 'it-IT') + ' kg su '
						+ FORMAT(reg.QuantitaOperativa, 'N2', 'it-IT') + ' kg, '
						+ FORMAT(reg.QuantitaOperativa - reg.QuantitaAllocataTotale, 'N2', 'it-IT') + ' kg da allocare'
				ELSE 'Allocata per intero: ' + FORMAT(reg.QuantitaAllocataTotale, 'N2', 'it-IT') + ' kg'
			END,
			reg.RegistroNome,
			reg.Numero,
			reg.Data,
			reg.MaterialeNome,
			IdLotto = lr.IdLotto,
			LottoNome = l.Nome,
			QuantitaAllocata = lr.Quantita,
			QuantitaDaAllocare = reg.QuantitaOperativa - reg.QuantitaAllocataTotale,
			RowsCount = COUNT(*) OVER ()
		FROM
			reg
			LEFT JOIN dbo.tblEoWLottiRifiutiRegistrazioni lr ON reg.Id = lr.IdRegistrazione
			LEFT JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
		WHERE
			-- Una registrazione M senza allocazioni e senza quantità operativa (annullata o a zero)
			-- non ha nulla da allocare: non compare
			(
				reg.NumeroAllocazioni > 0
				OR (reg.IsAnnullata = 0 AND reg.QuantitaOperativa > 0)
			)
			AND
				(
				@IdLotto IS NULL
				OR lr.IdLotto = @IdLotto
				)
			AND
				(
				@Allocazione IS NULL
				OR
					(
					@Allocazione = 'D'
					AND reg.QuantitaOperativa - reg.QuantitaAllocataTotale > 0
					)
				OR
					(
					@Allocazione = 'A'
					AND reg.NumeroAllocazioni > 0
					AND reg.QuantitaOperativa - reg.QuantitaAllocataTotale <= 0
					)
				)
		ORDER BY reg.Data DESC, reg.Numero DESC, lr.Pos, l.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWRegistrazioni_get_LottiSelectList
	@IdSelected CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede). Contesto "tutte le
		-- sedi" (NULL o sedici zeri) = solo (Tutti)
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, @idSediciZeri)
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Filtro di ricerca: tutti i lotti della sede, anche chiusi o disabilitati (le registrazioni
		-- allocate restano consultabili)
		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Tutti)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				l.Id,
				[Text] = CAST(l.Nome AS VARCHAR(500)),
				Selected = CAST(IIF(l.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblEoWLotti l
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE
				l.Lock = 0
				AND l.IdSede = @idSede
		)
		SELECT Id, [Text], Selected
		FROM cte
		ORDER BY Pos, [Text]
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@DataAperturaDa DATE = NULL,
	@DataAperturaA DATE = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Le select della ricerca usano gli zeri come "nessuna selezione" ((Nessuno)/(Selezionare))
		SET @IdMagazzino = NULLIF(NULLIF(LTRIM(RTRIM(@IdMagazzino)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			l.Id,
			-- Stato: prima l'anomalia "Scaricato più del prodotto" (il magazzino tradizionale ha scaricato
			-- più di quanto il registro operativo alloca al lotto: il magazzino EoW prevale e non viene
			-- mai corretto in automatico), poi la capacità (solo con quantità massima impostata; il lotto EoW
			-- è una partita di produzione, gli scarichi non liberano capienza): 2 = anomalia o capacità
			-- superata, 1 = lotto pieno o capacità residua sotto il 30% della quantità massima, 0 = OK
			StatoValore = CASE
				WHEN s.Giacenza < 0 THEN 2
				WHEN l.QuantitaMax IS NULL THEN 0
				WHEN c.QuantitaAllocata > l.QuantitaMax THEN 2
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN s.Giacenza < 0
					THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(s.Prodotta, 'N2', 'it-IT') + ' kg, scaricati '
						+ FORMAT(s.Scaricata, 'N2', 'it-IT') + ' kg dal magazzino'
				WHEN l.QuantitaMax IS NULL THEN 'OK'
				WHEN c.QuantitaAllocata > l.QuantitaMax
					THEN 'Capacità superata di ' + FORMAT(c.QuantitaAllocata - l.QuantitaMax, 'N2', 'it-IT') + ' kg: allocati '
						+ FORMAT(c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su ' + FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				WHEN c.QuantitaAllocata = l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3
					THEN 'Capacità residua sotto il 30%: ' + FORMAT(l.QuantitaMax - c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su '
						+ FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				ELSE 'OK'
			END,
			NumeroRegistrazioni = ISNULL(q.NumeroRegistrazioni, 0),
			l.Nome,
			MaterialeNome = m.Nome,
			MagazzinoNome = g.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT
					QuantitaAllocata = SUM(r.Quantita),
					NumeroRegistrazioni = COUNT(DISTINCT r.IdRegistrazione)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
					CROSS APPLY (SELECT QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0)) c
					CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) s
		WHERE
			l.Lock = 0
			AND l.IdSede = @idSede
			AND
				(
				@IdMagazzino IS NULL
				OR l.IdMagazzino = @IdMagazzino
				)
			AND
				(
				@IdMateriale IS NULL
				OR l.IdMateriale = @IdMateriale
				)
			AND
				(
				@Aperto IS NULL
				OR
					(
					@Aperto = 1
					AND l.DataChiusura IS NULL
					)
				OR
					(
					@Aperto = 0
					AND l.DataChiusura IS NOT NULL
					)
				)
			AND
				(
				@Disabilitato IS NULL
				OR ISNULL(l.Disabilitato, 0) = @Disabilitato
				)
			AND
				(
				@DataAperturaDa IS NULL
				OR l.DataApertura >= @DataAperturaDa
				)
			AND
				(
				@DataAperturaA IS NULL
				OR l.DataApertura <= @DataAperturaA
				)
			AND
				(
				@Search IS NULL
				OR l.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY l.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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

SET NOCOUNT ON;

-- EoW > Registrazioni (/eow/registrazioni): elenco delle registrazioni M con le allocazioni sui lotti.
-- Stessa funzione EOW delle altre pagine del modulo (nessuna nuova riga in tblFunzioni/tblModuliFunzioni).
-- Posizione richiesta dall'utente: sotto Lotti.
-- Prima: Lotti(0), Magazzini(1), Allocazioni(2), Giacenze(3)
-- Dopo:  Lotti(0), Registrazioni(1), Magazzini(2), Allocazioni(3), Giacenze(4)

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'EWR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('EWR', 'EOW', 'Registrazioni', NULL, NULL);

UPDATE dbo.tblMenu
SET Pos = CASE Id WHEN 'AH2' THEN 2 WHEN 'AH3' THEN 3 WHEN 'AH4' THEN 4 END
WHERE Id IN ('AH2', 'AH3', 'AH4');

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AH5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AH5', 'AH0', NULL, 'EWR', 1);
GO

