SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture clienti dai documenti fatturabili (per ora le registrazioni dei rifiuti),
-- con gli importi del modulo Offerte e contratti (regole O5 e O6 di docs/regole/offerte-contratti.md).
--   @Id (con @IdModulo = 'RIF'): un solo documento ("Genera la fattura" dalla scheda); l'azienda è quella del
--        documento. Se il documento non è fatturabile la SP lo rifiuta.
--   Senza @Id: i documenti dell'azienda interna corrente della sessione con data tra @DataDa e @DataA,
--        eventualmente riconducibili al solo cliente @IdClienteFornitore (Fatture clienti > Nuovo > Tramite
--        procedura automatica). @Rifiuti = 0: le registrazioni dei rifiuti non sono state scelte.
-- Entrano solo i documenti fatturabili, raggruppati come li mostra la verifica (ufnFattureGenera_get_Documenti).
-- Una fattura per cliente; secondo il raggruppamento della scheda del cliente (tblClientiFornitori.
-- IdRaggruppamento) una per sede del produttore (S) o una per contratto (T): solo in quest'ultimo caso la
-- fattura riporta ordine, data dell'ordine, CIG e CUP del contratto.
-- Fattura: tipo TD01 (TD00, pre-fattura senza numero, con @PreFattura = 1), stato Generata, attiva; data di
-- emissione e di registrazione @DataEmissione (oggi se non indicata); condizioni di pagamento, banca, IBAN,
-- valuta e split payment dalla scheda del cliente; numero successivo dell'anno senza sezionale, assegnato con
-- lo stesso blocco di uspFatture_upd. Righe: quelle dell'importo applicato a ogni documento, nell'ordine dei
-- documenti (data, numero); ritenuta d'acconto della scheda del cliente. Rate: uspFattureRate_ins_Genera.
-- Pre-fatture (@IncludiPreFatture = 1): i documenti già in una pre-fattura rientrano e la pre-fattura viene
-- convertita PER INTERO: le sue righe (non ricalcolate dagli importi, con aliquota, conto e ritenuta che hanno)
-- vanno nella fattura del suo cliente insieme agli altri documenti, al posto del suo primo documento, e tutti i
-- suoi documenti, anche quelli fuori dal periodo, passano alla nuova fattura. Con @RimuoviPreFatture = 1 la
-- pre-fattura viene poi cancellata (Lock 4), altrimenti resta in elenco senza più documenti collegati.
-- Ogni documento resta legato alla fattura (tblFattureDocumenti, con importo e contratto applicati) e non
-- viene fatturato due volte: un documento fatturato nel frattempo da un'altra sessione fa saltare la sua fattura.
-- Una transazione per fattura. Restituisce Fatture, Documenti e IdFattura (l'ultima generata).
CREATE OR ALTER PROCEDURE dbo.uspFatture_ins_Genera
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@DataEmissione DATE = NULL,
	@PreFattura BIT = 0,
	@Rifiuti BIT = 1,
	@IncludiPreFatture BIT = 0,
	@RimuoviPreFatture BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(NULLIF(LTRIM(RTRIM(@Id)), ''), REPLICATE('0', 16));
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @DataEmissione = ISNULL(@DataEmissione, CAST(GETDATE() AS DATE));
		SET @PreFattura = ISNULL(@PreFattura, 0);
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @RimuoviPreFatture = ISNULL(@RimuoviPreFatture, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND (@DataDa IS NULL OR @DataA IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END
		-- Convertire le pre-fatture in altre pre-fatture non ha senso
		IF @PreFattura = 1 AND @IncludiPreFatture = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per includere le pre-fatture togliere la spunta "Genera come pre-fatture"';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari per generare le fatture';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		IF @Id IS NULL
		BEGIN
			SELECT @idAzienda = IdAzienda
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;

			IF @idAzienda IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''azienda';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Un solo documento: sempre i rifiuti, senza pre-fatture
			SET @Rifiuti = 1;
			SET @IncludiPreFatture = 0;
		END

		-- Documenti da fatturare, con il raggruppamento della scheda del cliente
		DECLARE @doc TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			[Data] DATE NULL,
			Numero INT NULL,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdImporto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdOffertaContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdPreFattura CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			-- Primo documento della sua pre-fattura: porta le righe della pre-fattura e decide il gruppo
			PrimoDellaPreFattura BIT NOT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Fatturabile BIT NOT NULL
		);
		INSERT @doc (Id, [Data], Numero, IdAzienda, IdImporto, IdOffertaContratto, IdClienteFornitore, IdPreFattura, PrimoDellaPreFattura, GruppoSede, GruppoContratto, Fatturabile)
		SELECT
			d.Id,
			d.[Data],
			d.Numero,
			d.IdAzienda,
			d.IdImporto,
			d.IdOffertaContratto,
			ISNULL(d.IdClienteFornitore, REPLICATE('0', 16)),
			d.IdPreFattura,
			d.PrimoDellaPreFattura,
			d.GruppoSede,
			d.GruppoContratto,
			d.Fatturabile
		FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
		WHERE
			@Rifiuti = 1
			AND (@Id IS NOT NULL OR d.Fatturabile = 1)
		OPTION (RECOMPILE);

		IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @doc WHERE Fatturabile = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il documento non è fatturabile: usare "Verifica importo e cliente" per vedere il motivo';
			GOTO BRANCH_END;
		END

		-- Righe di fattura di ogni documento, calcolate ora una volta per tutte: quelle dell'importo applicato
		-- oppure, per il primo documento di una pre-fattura, le righe della pre-fattura così come sono
		DECLARE @righe TABLE (
			N INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			IdDocumento CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdRiga CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(1000) NULL,
			SolaDescrizione BIT NOT NULL,
			Quantita DECIMAL(18, 4) NULL,
			IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			Importo DECIMAL(18, 4) NULL,
			IdAliquotaIva CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdConto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			-- NULL: la ritenuta è quella della scheda del cliente
			RitenutaAcconto INT NULL
		);
		INSERT @righe (IdDocumento, Descrizione, SolaDescrizione, Quantita, IdUnitaMisura, Importo, IdAliquotaIva, IdConto, RitenutaAcconto)
		SELECT
			t.IdDocumento,
			t.Descrizione,
			t.SolaDescrizione,
			t.Quantita,
			t.IdUnitaMisura,
			t.Importo,
			t.IdAliquotaIva,
			t.IdConto,
			t.RitenutaAcconto
		FROM
			(
				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = ISNULL(g.Pos, 0),
					Ordine = g.Id,
					g.Descrizione,
					g.SolaDescrizione,
					g.Quantita,
					g.IdUnitaMisura,
					g.Importo,
					g.IdAliquotaIva,
					g.IdConto,
					RitenutaAcconto = CAST(NULL AS INT)
				FROM
					@doc d
					CROSS APPLY dbo.ufnImportiRifiuti_get_RigheImporto(d.Id, d.IdImporto, d.IdClienteFornitore) g
				WHERE
					d.Fatturabile = 1
					AND d.IdPreFattura IS NULL

				UNION ALL

				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = ISNULL(r.Pos, 0),
					Ordine = r.Id,
					r.Descrizione,
					SolaDescrizione = CAST(IIF(i.Id IS NULL, 1, 0) AS BIT),
					i.Quantita,
					i.IdUnitaMisura,
					i.Importo,
					i.IdAliquotaIva,
					i.IdConto,
					RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0)
				FROM
					@doc d
					INNER JOIN dbo.tblFattureRighe r ON d.IdPreFattura = r.IdFattura
					LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				WHERE
					d.Fatturabile = 1
					AND d.PrimoDellaPreFattura = 1
			) t
		ORDER BY t.[Data], t.Numero, t.IdDocumento, t.Pos, t.Ordine;

		-- Una fattura per ogni gruppo: cliente e, secondo il raggruppamento, sede del produttore o contratto
		DECLARE @gruppi TABLE (
			N INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);
		INSERT @gruppi (IdAzienda, IdClienteFornitore, GruppoSede, GruppoContratto)
		SELECT
			t.IdAzienda,
			t.IdClienteFornitore,
			t.GruppoSede,
			t.GruppoContratto
		FROM
			(
				SELECT DISTINCT IdAzienda, IdClienteFornitore, GruppoSede, GruppoContratto
				FROM @doc
				WHERE Fatturabile = 1
			) t
			LEFT JOIN dbo.tblClientiFornitori c ON t.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		ORDER BY s.NomeCompleto, t.IdClienteFornitore, t.GruppoSede, t.GruppoContratto;

		DECLARE @fatture INT = 0;
		DECLARE @documenti INT = 0;
		DECLARE @idUltima CHAR(16) = NULL;
		DECLARE @n INT = 1;
		DECLARE @gruppiTotale INT = (SELECT COUNT(*) FROM @gruppi);
		DECLARE @gAzienda CHAR(16), @gCliente CHAR(16), @gSede CHAR(16), @gContratto CHAR(16);
		DECLARE @idFattura CHAR(16), @idRiga CHAR(16), @r INT, @numero INT;
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@DataEmissione), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @gDoc TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		DECLARE @gPre TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

		WHILE @n <= @gruppiTotale
		BEGIN
			SELECT
				@gAzienda = IdAzienda,
				@gCliente = IdClienteFornitore,
				@gSede = GruppoSede,
				@gContratto = GruppoContratto
			FROM @gruppi
			WHERE N = @n;

			DELETE @gDoc;
			INSERT @gDoc (Id)
			SELECT Id
			FROM @doc
			WHERE
				Fatturabile = 1
				AND IdAzienda = @gAzienda
				AND IdClienteFornitore = @gCliente
				AND ISNULL(GruppoSede, '') = ISNULL(@gSede, '')
				AND ISNULL(GruppoContratto, '') = ISNULL(@gContratto, '');

			-- Pre-fatture del gruppo, da convertire
			DELETE @gPre;
			INSERT @gPre (Id)
			SELECT DISTINCT IdPreFattura
			FROM @doc
			WHERE
				Id IN (SELECT Id FROM @gDoc)
				AND IdPreFattura IS NOT NULL;

			-- Id della fattura e delle sue righe: uspId_get FUORI dalla transazione
			SET @idFattura = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idFattura OUTPUT;

			SET @r = (SELECT MIN(N) FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
			WHILE @r IS NOT NULL
			BEGIN
				SET @idRiga = NULL;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRiga OUTPUT;
				UPDATE @righe SET IdRiga = @idRiga WHERE N = @r;
				SET @r = (SELECT MIN(N) FROM @righe WHERE N > @r AND IdDocumento IN (SELECT Id FROM @gDoc));
			END

			BEGIN TRANSACTION;
				-- Un documento fatturato nel frattempo da un'altra sessione (in una fattura che non è una delle
				-- pre-fatture da convertire), o una pre-fattura nel frattempo cancellata o diventata fattura:
				-- questa fattura non si genera
				IF EXISTS (
						SELECT 1
						FROM
							dbo.tblFattureDocumenti fd WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
						WHERE
							fd.Id IN (SELECT Id FROM @gDoc)
							AND f.Lock IN (0, 2)
							AND f.Id NOT IN (SELECT Id FROM @gPre)
					)
					OR EXISTS (
						SELECT 1
						FROM
							@gPre p
							LEFT JOIN dbo.tblFatture f WITH (UPDLOCK, HOLDLOCK) ON p.Id = f.Id
																			  AND f.Lock IN (0, 2)
																			  AND f.IdTipo = 'TD00'
						WHERE f.Id IS NULL
					)
				BEGIN
					ROLLBACK TRANSACTION;

					-- Gli Id presi per la fattura e per le sue righe non servono più
					DELETE dbo.tblIdLog
					WHERE Id = @idFattura OR Id IN (SELECT IdRiga FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
					DELETE dbo.tblId
					WHERE Id = @idFattura OR Id IN (SELECT IdRiga FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
				END
				ELSE
				BEGIN
					-- Numero: successivo al più alto tra le fatture cliente attive dell'azienda nell'anno della data
					-- di emissione, senza sezionale (stessa lettura con blocco di uspFatture_upd). La pre-fattura
					-- non ha numero
					SET @numero = NULL;
					IF @PreFattura = 0
						SELECT @numero = ISNULL(MAX(Numero), 0) + 1
						FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
						WHERE
							IdSede = @gAzienda
							AND Tipo = 'C'
							AND Lock = 0
							AND ISNULL(Sezionale, '') = ''
							AND DataEmissione >= @annoInizio
							AND DataEmissione < @annoFine;

					INSERT dbo.tblFatture (
						Id, IdSede, IdClienteFornitore, IdTipo, IdStato, IdModalita, IdRata, IdRataInizio, IdValuta, IdBancaCassa,
						Tipo, Numero, DataRegistrazione, DataEmissione, Iban, RataGiorniInizio, Ordine, DataOrdine,
						SplitPayment, Bollo, CodiceCig, CodiceCup, SolaLettura, Lock)
					SELECT
						@idFattura, @gAzienda, c.Id, IIF(@PreFattura = 1, 'TD00', 'TD01'), 'G', c.IdModalita, c.IdRata, ISNULL(c.IdRataInizio, 'DF'), ISNULL(c.IdValuta, 'EUR'), c.IdBancaCassa,
						'C', @numero, @DataEmissione, @DataEmissione, c.Iban, ISNULL(c.RataGiorniInizio, 0), oc.Ordine, oc.DataOrdine,
						ISNULL(c.SplitPayment, 0), 0, oc.CodiceCig, oc.CodiceCup, 0, 0
					FROM
						dbo.tblClientiFornitori c
						LEFT JOIN dbo.tblOfferteContratti oc ON oc.Id = @gContratto
					WHERE c.Id = @gCliente;

					INSERT dbo.tblFattureRighe (Id, IdFattura, Descrizione, Pos)
					SELECT
						g.IdRiga,
						@idFattura,
						g.Descrizione,
						ROW_NUMBER() OVER (ORDER BY g.N)
					FROM @righe g
					WHERE g.IdDocumento IN (SELECT Id FROM @gDoc);

					INSERT dbo.tblFattureRigheImporti (Id, IdAliquotaIva, IdConto, IdUnitaMisura, Quantita, Importo, RitenutaAcconto)
					SELECT
						g.IdRiga,
						g.IdAliquotaIva,
						g.IdConto,
						g.IdUnitaMisura,
						g.Quantita,
						g.Importo,
						ISNULL(g.RitenutaAcconto, ISNULL(c.RitenutaAcconto, 0))
					FROM
						@righe g
						INNER JOIN dbo.tblClientiFornitori c ON c.Id = @gCliente
					WHERE
						g.IdDocumento IN (SELECT Id FROM @gDoc)
						AND g.SolaDescrizione = 0;

					-- Pre-fatture convertite: tutti i loro documenti, anche quelli fuori dal periodo, passano alla
					-- nuova fattura (le righe della pre-fattura non si possono dividere per documento); importo e
					-- contratto applicati restano quelli già registrati
					UPDATE dbo.tblFattureDocumenti
					SET IdFattura = @idFattura
					WHERE IdFattura IN (SELECT Id FROM @gPre);

					IF @RimuoviPreFatture = 1
						UPDATE dbo.tblFatture
						SET Lock = 4
						WHERE Id IN (SELECT Id FROM @gPre);

					-- Legame degli altri documenti con la fattura, con l'importo e il contratto applicati; cliente
					-- indicato e spunta restano quelli già presenti
					UPDATE fd
					SET
						IdFattura = @idFattura,
						IdImporto = d.IdImporto,
						IdOffertaContratto = d.IdOffertaContratto
					FROM
						dbo.tblFattureDocumenti fd
						INNER JOIN @doc d ON fd.Id = d.Id
					WHERE
						d.Id IN (SELECT Id FROM @gDoc)
						AND d.IdPreFattura IS NULL;

					INSERT dbo.tblFattureDocumenti (Id, IdModulo, IdFattura, IdImporto, IdOffertaContratto, NonFatturabile)
					SELECT d.Id, 'RIF', @idFattura, d.IdImporto, d.IdOffertaContratto, 0
					FROM @doc d
					WHERE
						d.Id IN (SELECT Id FROM @gDoc)
						AND NOT EXISTS (SELECT 1 FROM dbo.tblFattureDocumenti x WHERE x.Id = d.Id);

					COMMIT TRANSACTION;

					SET @fatture += 1;
					SET @documenti += (SELECT COUNT(*) FROM @gDoc);
					SET @idUltima = @idFattura;

					-- Rate dalle condizioni di pagamento della fattura. Una fattura senza importo da pagare non
					-- ha rate: quell'errore applicativo non ferma la generazione
					BEGIN TRY
						EXEC dbo.uspFattureRate_ins_Genera @IdFattura = @idFattura, @IdSessione = @IdSessione, @Interno = 1;
					END TRY
					BEGIN CATCH
						IF ERROR_NUMBER() <> 50001
							THROW;
					END CATCH
				END

			SET @n += 1;
		END

		SELECT
			Fatture = @fatture,
			Documenti = @documenti,
			IdFattura = @idUltima;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
