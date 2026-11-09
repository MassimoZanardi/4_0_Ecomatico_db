SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'Allegato VII, riquadro "Avanzamento della spedizione": una riga per passaggio previsto, nell'ordine del
-- documento (presa in carico di ogni trasportatore, ricezione del destinatario, ricezione e recupero completato di ogni
-- impianto), con la conferma letta da DIWASS se c'è (stesso operatore del soggetto). Passaggi, ricezione del
-- destinatario non prevista, soggetti dell'azienda e passaggi che l'azienda può confermare da
-- ufnDiwassAllegatiVii_get_Passaggi; per la finestra di conferma, contatto e mezzo proposti, nome di chi firma (utente
-- della sessione) e ruolo proposto (l'ultimo dell'utente per l'azienda, altrimenti quello del documento). Regole in
-- docs/regole/diwass.md D6, D7
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Avanzamento]
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

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione (lettura; per confermare serve la scrittura)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		DECLARE @firmaRuolo VARCHAR(100);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente,
			@firmaRuolo = a.FirmaRuolo
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @firmaNome VARCHAR(100) = (
			SELECT NULLIF(LTRIM(RTRIM(ISNULL(Nome, '') + ' ' + ISNULL(Cognome, ''))), '')
			FROM dbo.tblUtenti
			WHERE Id = @idUtente);
		SET @firmaRuolo = ISNULL((
			SELECT Ruolo
			FROM dbo.tblDiwassFirmeRuoli
			WHERE
				IdUtente = @idUtente
				AND IdAziendaInterna = @idAzienda
		), @firmaRuolo);

		SELECT
			p.Ordine,
			p.Tipo,
			p.Pos,
			Passaggio = CASE p.Tipo
				WHEN 'T' THEN N'Presa in carico'
				WHEN 'D' THEN N'Ricezione del destinatario'
				WHEN 'I' THEN N'Ricezione all''impianto'
				ELSE N'Recupero completato'
			END,
			p.SoggettoNome,
			p.OperatorInternalId,
			p.DellAzienda,
			p.Prevista,
			Confermabile = CAST(IIF(p.Confermabile = 1 AND @permesso >= 2, 1, 0) AS BIT),
			p.PerConto,
			PropostaMezzoTrasporto = p.MezzoTrasporto,
			PropostaContattoNome = p.ContattoNome,
			PropostaContattoTelefono = p.ContattoTelefono,
			PropostaContattoEmail = p.ContattoEmail,
			PropostaFirmaNome = @firmaNome,
			PropostaFirmaRuolo = @firmaRuolo,
			NumeroConferma = c.Numero,
			c.Data,
			c.MezzoTrasporto,
			c.Targhe,
			c.UnitaQuantita,
			c.QuantitaAccettata,
			c.QuantitaRespinta,
			c.MotivoRespingimento,
			c.QuantitaRiutilizzo,
			c.QuantitaRecupero,
			c.Descrizione,
			c.FirmaNome,
			c.FirmaRuolo,
			c.FirmaData
		FROM
			dbo.ufnDiwassAllegatiVii_get_Passaggi(@Id, @idAzienda) p
			OUTER APPLY (
				SELECT TOP 1 *
				FROM dbo.tblDiwassAllegatiViiConferme k
				WHERE
					k.Id = @Id
					AND k.Tipo = p.Tipo
					AND k.OperatorInternalId = p.OperatorInternalId
				ORDER BY k.Pos
			) c
		ORDER BY p.Ordine, p.Pos, IIF(p.Tipo = 'C', 1, 0);

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
