-- Deploy produzione 2026-10-01: sede sempre dal contesto nelle liste EoW/Magazzino, colonna Registro
-- nei Carichi EoW, Nome registro obbligatorio (7 stored procedure): repo DB da deployed-prod 425bc44 a 5e3076c.
-- - uspEoWGiacenze_get_List, uspEoWGiacenze_get_Carichi_List, uspEoWAllocazioni_get_List, uspEoWLotti_get_List,
--   uspMagazziniLotti_get_List, uspMagazziniGiacenze_get_List: senza parametro @IdSede, la sede si legge da
--   tblSessioni.IdSede (contesto). Contesto "tutte le sedi": nessuna riga, tranne MagazziniGiacenze e Carichi
-- - uspEoWGiacenze_get_List: rimosso SedeNome; uspEoWGiacenze_get_Carichi_List: aggiunto RegistroNome
-- - uspRifiutiRegistri_upd: @Nome obbligatorio
-- ATTENZIONE: da pubblicare INSIEME all'app (commit a8f6cc2): l'app precedente passa @IdSede, che queste SP
-- non accettano piu' (errore "too many arguments"); la nuova app con le SP vecchie mostrerebbe tutte le sedi.
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -I -b -i <questo file>
-- Poi: tools\verifica_crlf_accenti.sql su tutto il DB (deve restituire 0 righe).
-- ============================================================ uspRifiutiRegistri_upd
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistri_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@ControlloScadenzeAutorizzazioni BIT = 1,
	@ControlloTarghe BIT = 1,
	@ControlloConducenti BIT = 1,
	@ControlloPatenti BIT = 1,
	@ControlloAttivitaRs BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @ControlloScadenzeAutorizzazioni = ISNULL(@ControlloScadenzeAutorizzazioni, 1);
		SET @ControlloTarghe = ISNULL(@ControlloTarghe, 1);
		SET @ControlloConducenti = ISNULL(@ControlloConducenti, 1);
		SET @ControlloPatenti = ISNULL(@ControlloPatenti, 1);
		SET @ControlloAttivitaRs = ISNULL(@ControlloAttivitaRs, 1);

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
		IF @IdTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdTipo non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Nome obbligatorio: distingue il registro tra quelli della stessa sede interna
		-- (es. colonna Registro in EoW > Giacenze > Carichi)
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nome del registro non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del registro
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblRifiutiRegistri c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro record con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro registro con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se il registro contiene registrazioni o formulari
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdTipo <> @IdTipo
				AND EXISTS ( SELECT 1 FROM dbo.tblRifiutiMovimenti m LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento WHERE m.IdRegistro = @Id AND (r.Lock < 2 OR f.Lock < 2) )
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo ad un registro con registrazioni o formulari associati';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se il registro contiene modelli
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdTipo <> @IdTipo
				AND EXISTS ( SELECT 1 FROM dbo.tblRifiutiModelli WHERE IdRegistro = @Id AND Lock < 2 )
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo ad un registro con modelli associati';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblRifiutiRegistri
			SET
				Lock = 0,
				Nome = @Nome,
				IdTipo = @IdTipo,
				ControlloScadenzeAutorizzazioni = @ControlloScadenzeAutorizzazioni,
				ControlloTarghe = @ControlloTarghe,
				ControlloConducenti = @ControlloConducenti,
				ControlloPatenti = @ControlloPatenti,
				ControlloAttivitaRs = @ControlloAttivitaRs
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registro non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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
-- ============================================================ uspEoWGiacenze_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
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

		-- Giacenza (coerente con Rifiuti/Giacenze): Quantita = quanto c'è oggi nel lotto, cioè le
		-- quote di registrazioni M attive (Lock < 2: una registrazione eliminata mantiene le sue
		-- quote per un eventuale ripristino, ma non conta più) meno gli scarichi dei movimenti di
		-- magazzino confermati; solo le righe con giacenza diversa da 0: una giacenza negativa è
		-- l'anomalia "Scaricato più del prodotto" (il magazzino EoW deriva dal registro operativo e
		-- prevale sul magazzino tradizionale, non viene mai corretto in automatico). GiacenzaGiorni = giorni dalla
		-- prima registrazione M del lotto. La capacità residua resta riferita alla produzione
		-- (QuantitaMax - quantità attribuita): il lotto EoW è una partita di produzione, gli
		-- scarichi non liberano capienza.
		IF @Vista = 'L'
		BEGIN
			SELECT
				l.Id,
				-- 2 = anomalia (scaricato più del prodotto), 1 = lotto pieno (la produzione attribuita ha
				-- raggiunto la quantità massima), 0 = OK
				StatoValore = CASE
					WHEN ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) < 0 THEN 2
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAttribuita, 0) >= l.QuantitaMax THEN 1
					ELSE 0
				END,
				StatoDescrizione = CASE
					WHEN ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) < 0
						THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(ISNULL(q.QuantitaAttribuita, 0), 'N2', 'it-IT') + ' kg, scaricati '
							+ FORMAT(ISNULL(sc.Scaricata, 0), 'N2', 'it-IT') + ' kg dal magazzino'
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAttribuita, 0) >= l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
					ELSE 'OK'
				END,
				l.Nome,
				MaterialeNome = m.Nome,
				l.QuantitaMax,
				QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
				Quantita = ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAttribuita, 0) END,
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWLotti l
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
				LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				OUTER APPLY (
					SELECT
						QuantitaAttribuita = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLottiRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						r.IdLotto = l.Id
						AND rr.Lock < 2
				) q
						OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblMagazziniMovimentiRigheEoWLotti rs
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						rs.IdLotto = l.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
						) sc
			WHERE
				l.Lock = 0
				AND l.IdSede = @idSede
				AND
					(
					@Search IS NULL
					OR l.Nome LIKE '%' + @Search + '%'
					)
				AND ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) <> 0
			ORDER BY l.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END
		ELSE
		BEGIN
			SELECT
				g.Id,
				-- 2 = almeno un lotto del magazzino in anomalia (nella somma un lotto negativo resterebbe
				-- nascosto dagli altri)
				StatoValore = IIF(ISNULL(an.LottiAnomali, 0) > 0, 2, 0),
				StatoDescrizione = IIF(ISNULL(an.LottiAnomali, 0) > 0,
					'Scaricato più del prodotto in ' + CAST(an.LottiAnomali AS VARCHAR(10)) + IIF(an.LottiAnomali = 1, ' lotto', ' lotti'),
					'OK'),
				g.Nome,
				MaterialeNome = CAST(NULL AS VARCHAR(100)),
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
				Quantita = ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWMagazzini g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				OUTER APPLY (
					SELECT
						QuantitaAttribuita = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni r ON r.IdLotto = l.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rr.Lock < 2
				) q
						OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoWLotti rs ON rs.IdLotto = l.Id
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
						) sc
						OUTER APPLY (
					SELECT LottiAnomali = COUNT(*)
					FROM
						dbo.tblEoWLotti l
						CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) sl
					WHERE
						l.IdMagazzino = g.Id
						AND l.Lock = 0
						AND sl.Giacenza < 0
						) an
			WHERE
				g.Lock = 0
				AND g.IdSede = @idSede
				AND
					(
					@Search IS NULL
					OR g.Nome LIKE '%' + @Search + '%'
					)
				AND
					(
					ISNULL(q.QuantitaAttribuita, 0) - ISNULL(sc.Scaricata, 0) <> 0
					OR ISNULL(an.LottiAnomali, 0) > 0
					)
			ORDER BY g.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
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
-- ============================================================ uspEoWGiacenze_get_Carichi_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Carichi_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza @Id: tutti i carichi EoW delle sedi interne della sessione (filtrati per
		-- la sede del contesto della sessione, se impostata); con @Id: i carichi del lotto (@Vista = L)
		-- o del magazzino EoW (@Vista = M) indicato
		IF @Id IS NOT NULL AND ISNULL(@Vista, '') NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
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
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = tutte le sedi interne
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Titolarità sul Lotto/Magazzino indicato
		IF @Id IS NOT NULL AND @Vista = 'L' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND @Vista = 'M' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini g INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione AS Id,
			-- Registro della registrazione: la sede interna può averne più di uno
			RegistroNome = g.Nome,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			LottoNome = l.Nome,
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAttribuita = lr.Quantita,
			-- Residuo attuale del lotto EoW della quota (gli scarichi di magazzino prelevano dal
			-- lotto, non dalla singola registrazione): quote di registrazioni attive meno gli
			-- scarichi dei movimenti di magazzino confermati
			ResiduoLotto = ISNULL(pl.Prodotta, 0) - ISNULL(sl.Scaricata, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
			OUTER APPLY (
				SELECT Prodotta = SUM(qp.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni qp
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON qp.IdRegistrazione = rp.Id
				WHERE
					qp.IdLotto = l.Id
					AND rp.Lock < 2
			) pl
			OUTER APPLY (
				SELECT Scaricata = SUM(rs.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rs
					INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
					INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
				WHERE
					rs.IdLotto = l.Id
					AND rg.Lock = 0
					AND ms.Lock = 0
			) sl
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			r.Lock < 2
			AND (
				(@Id IS NULL AND (@idSede IS NULL OR l.IdSede = @idSede))
				OR (@Vista = 'L' AND l.Id = @Id)
				OR (@Vista = 'M' AND l.IdMagazzino = @Id)
			)
			AND (@Search IS NULL OR r.Numero = TRY_CAST(@Search AS INT) OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Data DESC, r.Numero DESC
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
-- ============================================================ uspEoWAllocazioni_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
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
			a.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			a.Nome,
			TipoNome = t.Nome,
			MaterialeNome = mat.MaterialeNome,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWAllocazioni a
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON a.IdSede = i.Id
			LEFT JOIN dbo.tblEoWAllocazioniTipi t ON a.IdAllocazioneTipo = t.Id
			-- Il materiale non è un campo proprio dell'allocazione: si ricava dai lotti già collegati
			OUTER APPLY (
				SELECT TOP 1 IdMateriale = l.IdMateriale, MaterialeNome = m.Nome
				FROM
					dbo.tblEoWLottiAllocazioni la
					INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
					LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				WHERE la.IdAllocazione = a.Id
			) mat
		WHERE
			a.Lock = 0
			AND a.IdSede = @idSede
			AND (@IdMateriale IS NULL OR mat.IdMateriale = @IdMateriale)
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%')
		ORDER BY a.Nome
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
-- ============================================================ uspEoWLotti_get_List
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
		SET @IdMagazzino = NULLIF(LTRIM(RTRIM(@IdMagazzino)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
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
			-- più di quanto il registro operativo attribuisce al lotto: il magazzino EoW prevale e non viene
			-- mai corretto in automatico), poi la capacità (solo con quantità massima impostata; il lotto EoW
			-- è una partita di produzione, gli scarichi non liberano capienza): 2 = anomalia o capacità
			-- superata, 1 = lotto pieno o capacità residua sotto il 30% della quantità massima, 0 = OK
			StatoValore = CASE
				WHEN s.Giacenza < 0 THEN 2
				WHEN l.QuantitaMax IS NULL THEN 0
				WHEN c.QuantitaAttribuita > l.QuantitaMax THEN 2
				WHEN l.QuantitaMax - c.QuantitaAttribuita < l.QuantitaMax * 0.3 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN s.Giacenza < 0
					THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(s.Prodotta, 'N2', 'it-IT') + ' kg, scaricati '
						+ FORMAT(s.Scaricata, 'N2', 'it-IT') + ' kg dal magazzino'
				WHEN l.QuantitaMax IS NULL THEN 'OK'
				WHEN c.QuantitaAttribuita > l.QuantitaMax
					THEN 'Capacità superata di ' + FORMAT(c.QuantitaAttribuita - l.QuantitaMax, 'N2', 'it-IT') + ' kg: attribuiti '
						+ FORMAT(c.QuantitaAttribuita, 'N2', 'it-IT') + ' kg su ' + FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				WHEN c.QuantitaAttribuita = l.QuantitaMax THEN 'Lotto pieno: capacità esaurita'
				WHEN l.QuantitaMax - c.QuantitaAttribuita < l.QuantitaMax * 0.3
					THEN 'Capacità residua sotto il 30%: ' + FORMAT(l.QuantitaMax - c.QuantitaAttribuita, 'N2', 'it-IT') + ' kg su '
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
			QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAttribuita, 0) END,
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
					QuantitaAttribuita = SUM(r.Quantita),
					NumeroRegistrazioni = COUNT(DISTINCT r.IdRegistrazione)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
					CROSS APPLY (SELECT QuantitaAttribuita = ISNULL(q.QuantitaAttribuita, 0)) c
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
-- ============================================================ uspMagazziniLotti_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
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
			StatoValore = 0,
			StatoDescrizione = 'OK',
			l.Nome,
			ArticoloNome = art.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			Disponibilita = ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0),
			Disabilitato = ISNULL(l.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
			-- Caricato: righe di carico confermate del lotto (le righe di scarico Manuale hanno anch'esse IdLotto: filtro sull'operazione); Scaricato: relazioni di scarichi
			-- confermati su quelle righe di carico (tblMagazziniMovimentiRigheRelazioni)
			OUTER APPLY (
				SELECT
					Caricato = (
						SELECT SUM(rc.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRighe rc
							INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						WHERE
							rc.IdLotto = l.Id
							AND mc.IdOperazione = 'C'
							AND rc.Lock = 0
							AND mc.Lock = 0
					),
					Scaricato = (
						SELECT SUM(rel.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
							INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rc.IdLotto = l.Id
							AND rp.Lock = 0
							AND mp.Lock = 0
					)
			) q
		WHERE
			l.Lock = 0
			AND l.IdSede = @idSede
			AND (@IdArticolo IS NULL OR l.IdArticolo = @IdArticolo)
			AND (@Aperto IS NULL OR (@Aperto = 1 AND l.DataChiusura IS NULL) OR (@Aperto = 0 AND l.DataChiusura IS NOT NULL))
			AND (@Disabilitato IS NULL OR ISNULL(l.Disabilitato, 0) = @Disabilitato)
			AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
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
-- ============================================================ uspMagazziniGiacenze_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_List
	@IdSessione CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = tutte le sedi interne
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Giacenza per Articolo + Sede, aggregata su tutti i lotti: mai memorizzata,
		-- sempre calcolata dalle righe di carico confermate meno le relazioni degli scarichi
		-- confermati su quelle righe (Movimento.Lock = 0)
		SELECT
			art.Id AS IdArticolo,
			ArticoloNome = art.Nome,
			g.IdSede,
			SedeNome = s.Nome,
			UnitaMisuraNome = u.Nome,
			IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			Disponibilita = ISNULL(SUM(g.Quantita), 0)
		FROM
			(
				SELECT
					rc.IdArticolo,
					rc.IdSede,
					rc.Quantita
				FROM
					dbo.tblMagazziniMovimentiRighe rc
					INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
				WHERE
					mc.IdOperazione = 'C'
					AND rc.Lock = 0
					AND mc.Lock = 0

				UNION ALL

				SELECT
					rc.IdArticolo,
					rc.IdSede,
					-rel.Quantita
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rp.Lock = 0
					AND mp.Lock = 0
			) g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			INNER JOIN dbo.tblMagazziniArticoli art ON g.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
		WHERE
			(@idSede IS NULL OR g.IdSede = @idSede)
			AND (@IdArticolo IS NULL OR g.IdArticolo = @IdArticolo)
		GROUP BY art.Id, art.Nome, art.IdUnitaMisura, g.IdSede, s.Nome, u.Nome
		HAVING ISNULL(SUM(g.Quantita), 0) <> 0
		ORDER BY art.Nome, s.Nome
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
