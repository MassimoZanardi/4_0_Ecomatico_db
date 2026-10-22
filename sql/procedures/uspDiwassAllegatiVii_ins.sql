SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo Allegato VII (bozza, Lock = 2 finché non si salva) dell'azienda del contesto, che è chi organizza la
-- spedizione. Con @IdRegistrazione (Trasporto transfrontaliero = Allegato VII) lo compila dalla registrazione e dal
-- suo movimento: soggetti collegati a DIWASS (la sede o, se non collegata, la sua azienda), quantità in tonnellate o
-- m³, data, EER, operazione R, codice internazionale (ultimo usato dall'azienda per l'EER o il primo suggerito),
-- paesi e luogo di partenza. Restituisce Id e gli avvisi da mostrare (sedi sostituite o non collegate)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_ins]
	@IdSessione CHAR(16) = NULL,
	@IdRegistrazione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');

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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = IdAzienda,
			@idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda che organizza la spedizione';
			GOTO BRANCH_END;
		END

		-- Dati della registrazione e del suo movimento (solo dell'azienda del contesto e con Allegato VII)
		DECLARE @idMovimento CHAR(16);
		DECLARE @idProduttore CHAR(16);
		DECLARE @idDestinatario CHAR(16);
		DECLARE @quantita DECIMAL(18, 5);
		DECLARE @unitaQuantita CHAR(1);
		DECLARE @dataSpedizione DATE;
		DECLARE @idEer CHAR(6);
		DECLARE @descrizione VARCHAR(500);
		DECLARE @idAttivita CHAR(2);

		IF @IdRegistrazione IS NOT NULL
		BEGIN
			DECLARE @tipoTransfrontaliero CHAR(1);
			SELECT
				@idMovimento = m.Id,
				@tipoTransfrontaliero = r.IdTrasportoTransfrontalieroTipo,
				@idProduttore = m.IdSedeProduttoreDetentore,
				@idDestinatario = m.IdSedeDestinatario,
				@quantita = CASE m.IdUnitaMisura
					WHEN 'KG' THEN m.Quantita / 1000
					WHEN 'TN' THEN m.Quantita
					WHEN 'LT' THEN m.Quantita / 1000
					WHEN 'MC' THEN m.Quantita
				END,
				@unitaQuantita = CASE m.IdUnitaMisura
					WHEN 'LT' THEN 'M'
					WHEN 'MC' THEN 'M'
					ELSE 'T'
				END,
				@dataSpedizione = ISNULL(CAST(m.DataInizioTrasporto AS DATE), r.Data),
				@idEer = m.IdEer,
				@descrizione = ISNULL(m.EerDescrizione, e.Descrizione),
				@idAttivita = IIF(a.Codice LIKE 'R%', m.IdAttivita, NULL)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			WHERE
				r.Id = @IdRegistrazione
				AND r.Lock < 2
				AND s.IdAziendaInterna = @idAzienda;

			IF @idMovimento IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione non trovata nell''azienda del contesto';
				GOTO BRANCH_END;
			END
			IF ISNULL(@tipoTransfrontaliero, '') <> 'D'
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione non ha il trasporto transfrontaliero con Allegato VII';
				GOTO BRANCH_END;
			END
		END

		-- Una registrazione ha un solo Allegato VII non annullato: se c'è già, si apre quello
		DECLARE @esistente CHAR(16) = (
			SELECT TOP 1 Id
			FROM dbo.tblDiwassAllegatiVii
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND Lock = 0
				AND ISNULL(Stato, '') <> 'CANCELLED'
		);
		IF @esistente IS NOT NULL
		BEGIN
			SELECT
				Id = @esistente,
				Avvisi = N'La registrazione ha già un Allegato VII: è stato aperto quello';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @avvisi NVARCHAR(MAX) = N'';

		-- Soggetti da indicare: sede collegata a DIWASS o, se non collegata, la sua azienda
		DECLARE @soggetti TABLE (Ruolo CHAR(1), Pos TINYINT, IdSedeOrigine CHAR(16), Mezzo CHAR(1));
		IF @idMovimento IS NOT NULL
		BEGIN
			INSERT INTO @soggetti (Ruolo, Pos, IdSedeOrigine, Mezzo)
			VALUES ('P', 1, @idProduttore, NULL), ('D', 1, @idDestinatario, NULL), ('I', 1, @idDestinatario, NULL);

			INSERT INTO @soggetti (Ruolo, Pos, IdSedeOrigine, Mezzo)
			SELECT
				'T',
				t.Pos + 1,
				z.IdSede,
				CASE t.IdTipo
					WHEN 'T' THEN 'T'
					WHEN 'N' THEN 'S'
					ELSE 'R'
				END
			FROM
				dbo.tblRifiutiMovimentiTrasportatori t
				INNER JOIN dbo.tblRifiutiAutorizzazioni z ON t.IdAutorizzazione = z.Id
			WHERE
				t.Id = @idMovimento
				AND t.Pos BETWEEN 0 AND 2;
		END

		DECLARE @collegati TABLE (Ruolo CHAR(1), Pos TINYINT, IdSede CHAR(16), Sostituita BIT, IdSedeOrigine CHAR(16), Mezzo CHAR(1));
		INSERT INTO @collegati (Ruolo, Pos, IdSede, Sostituita, IdSedeOrigine, Mezzo)
		SELECT x.Ruolo, x.Pos, c.IdSede, c.Sostituita, x.IdSedeOrigine, x.Mezzo
		FROM
			@soggetti x
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_SedeCollegata(x.IdSedeOrigine) c
		WHERE x.IdSedeOrigine IS NOT NULL;

		-- Il produttore che coincide con chi organizza non si indica (arrangerIsProducer)
		DELETE @collegati
		WHERE
			Ruolo = 'P'
			AND IdSede = @idAzienda;

		SELECT @avvisi = @avvisi + CASE x.Ruolo
				WHEN 'P' THEN N'Produttore'
				WHEN 'D' THEN N'Destinatario'
				WHEN 'I' THEN N'Impianto'
				ELSE N'Trasportatore ' + CAST(x.Pos AS NVARCHAR(1))
			END + N': ' + s.NomeCompleto + IIF(x.IdSede IS NULL,
				N' non è collegato a DIWASS (Diwass > Operatori), indicarlo prima dell''invio. ',
				N' non è collegato a DIWASS, è indicata la sua azienda. ')
		FROM
			@collegati x
			INNER JOIN dbo.tblSedi s ON x.IdSedeOrigine = s.Id
		WHERE
			x.IdSede IS NULL
			OR x.Sostituita = 1;

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDiwassOperatori
		WHERE
			Id = @idAzienda
			AND Stato IN ('NEW', 'VALID')
		)
			SET @avvisi = @avvisi + N'L''azienda che organizza la spedizione non è collegata a DIWASS (Diwass > Operatori). ';

		-- Codice internazionale: ultimo usato dall'azienda per l'EER, altrimenti il primo suggerito
		DECLARE @listaCodice VARCHAR(10);
		DECLARE @codice NVARCHAR(20);
		SELECT
			@listaCodice = Lista,
			@codice = Codice
		FROM dbo.tblDiwassCodiciRifiutiUsati
		WHERE
			IdAziendaInterna = @idAzienda
			AND IdEer = @idEer;
		IF @codice IS NULL
			SELECT TOP 1
				@listaCodice = Lista,
				@codice = Codice
			FROM dbo.tblDiwassCodiciRifiutiEer
			WHERE IdEer = @idEer
			ORDER BY Pos;

		-- Paesi e luogo di partenza dalle sedi del produttore (o dell'azienda) e del destinatario
		DECLARE @idSedePartenza CHAR(16) = ISNULL(@idProduttore, @idAzienda);
		DECLARE @luogoPartenza VARCHAR(300) = (SELECT LEFT(IndirizzoCompleto, 300)
		FROM dbo.tblSedi
		WHERE Id = @idSedePartenza);
		DECLARE @idNazioneSpedizione CHAR(3) = (
			SELECT TOP 1 i.IdNazione
			FROM
				dbo.tblSediIndirizzi si
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			WHERE si.Id = @idSedePartenza);
		DECLARE @idNazioneDestinazione CHAR(3) = (
			SELECT TOP 1 i.IdNazione
			FROM
				dbo.tblSediIndirizzi si
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			WHERE si.Id = @idDestinatario);
		DECLARE @interim BIT = IIF(EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento
			WHERE
				Id = @idAttivita
				AND Codice IN ('R12', 'R13')
		), 1, 0);

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblDiwassAllegatiVii (
				Id, IdAziendaInterna, IdRegistrazione, TipoDestinazione, DataSpedizione, Quantita, UnitaQuantita,
				LuogoPartenza, IdEer, Descrizione, IdNazioneSpedizione, IdNazioneDestinazione, IdAttivita,
				ListaCodice, Codice, FirmaRuolo, Lock)
			SELECT
				@returnId, @idAzienda, @IdRegistrazione, 'R', @dataSpedizione, @quantita, ISNULL(@unitaQuantita, 'T'),
				@luogoPartenza, @idEer, LEFT(@descrizione, 500), @idNazioneSpedizione, @idNazioneDestinazione, @idAttivita,
				@listaCodice, @codice, f.Ruolo, 2
			FROM (SELECT x = 1) d
			LEFT JOIN dbo.tblDiwassFirmeRuoli f ON f.IdUtente = @idUtente AND f.IdAziendaInterna = @idAzienda;

			-- Chi organizza: l'azienda, con il contatto dell'utente che compila
			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail)
			SELECT
				@returnId,
				'O',
				1,
				@idAzienda,
			LEFT(LTRIM(RTRIM(ISNULL(u.Nome, '') + ' ' + ISNULL(u.Cognome, ''))), 100),
				c.Telefono,
				u.Email
			FROM
				dbo.tblUtenti u
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(@idAzienda) c
			WHERE u.Id = @idUtente;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato)
			SELECT
				@returnId,
				x.Ruolo,
				x.Pos,
				x.IdSede,
				c.Nome,
				c.Telefono,
				c.Email,
				x.Mezzo,
				IIF(x.Ruolo = 'I', @interim, NULL),
				IIF(x.Ruolo = 'I', 0, NULL)
			FROM
				@collegati x
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(x.IdSede) c
			WHERE x.IdSede IS NOT NULL;
		COMMIT TRANSACTION;

		SELECT
			Id = @returnId,
			Avvisi = NULLIF(LTRIM(RTRIM(@avvisi)), N'');

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
