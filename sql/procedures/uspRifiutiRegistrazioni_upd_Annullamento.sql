SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica di ANNULLAMENTO (@Id, collegata a un
-- originale via tblRentriRegistrazioniRettifiche.IdRettifica/Annullata=1 - vedi
-- uspRifiutiRegistrazioni_upd_Rettifica per la sotto-tipologia di correzione, stessa tabella di
-- tracking). A differenza della correzione, un annullamento non ha ALCUN campo modificabile
-- dall'utente eccetto le note (RegistrazioneNote, obbligatorie: riportano il motivo dell'annullamento
-- e diventano "annotazioni" nel payload RENTRI - vedi viewRentriRegistrazioni.RettificaIsAnnullata,
-- l'hub 1_0_RentriApi traduce la riga in un "AnnullamentoMovimento" che trasmette solo il riferimento
-- alla registrazione annullata + data + annotazioni, nessun altro campo rifiuto). Numero/Data di
-- registrazione restano quelli calcolati automaticamente (nessuna UI li espone in modifica) ma vengono
-- comunque passati a uspRifiutiRegistrazioni_upd per la sua validazione standard. Tutti gli altri campi
-- vengono riletti invariati dalla riga stessa (snapshot copiato dall'originale al momento dell'INSERT,
-- mai più toccato) e passati pari pari a uspRifiutiRegistrazioni_upd. A differenza della correzione, un
-- annullamento non propaga MAI nulla sull'originale (che infatti non viene nemmeno letto qui, se non
-- per verificare il collegamento).
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Annullamento]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo (stesso pattern di
		-- uspRifiutiRegistrazioni_upd_Rettifica)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE
			IdRettifica = @Id
			AND Annullata = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è un annullamento';
			GOTO BRANCH_END;
		END

		SET @RegistrazioneNote = NULLIF(LTRIM(RTRIM(@RegistrazioneNote)), '');

		-- Punto 5 della specifica: unico dato editabile dall'utente, obbligatorio (riporta il motivo
		-- dell'annullamento, diventa "annotazioni" nel payload RENTRI)
		IF @RegistrazioneNote IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
			GOTO BRANCH_END;
		END

		-- Rilettura pass-through di tutti i campi non modificabili qui (snapshot copiato dall'originale
		-- all'INSERT): stessa forma di uspRifiutiRegistrazioni_get, così uspRifiutiRegistrazioni_upd non
		-- vede alcuna differenza rispetto ai valori già presenti e non rifiuta/altera nulla oltre a
		-- Numero/Data/Note.
		DECLARE
			@idMovimento CHAR(16), @idEer CHAR(6), @idProvenienza CHAR(1), @eerDescrizione VARCHAR(200),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idUnitaMisura CHAR(2), @quantita DECIMAL(18, 2),
			@dataInizioTrasporto SMALLDATETIME, @idDocumentoTrasportoTipo CHAR(1), @formularioNumero VARCHAR(20),
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneTrasportatore2 CHAR(16), @idAutorizzazioneTrasportatore3 CHAR(16),
			@idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16), @idAutorizzazioneIntermediario3 CHAR(16),
			@utenteNote VARCHAR(500),
			@isVeicoloFuoriUso BIT, @veicoloFuoriUsoNumero VARCHAR(50), @veicoloFuoriUsoData DATE,
			@idRaee CHAR(1),
			@idEsito CHAR(1), @quantitaVerificata DECIMAL(18, 2), @isQuantitaVerificata BIT, @dataFineTrasporto SMALLDATETIME,
			@idCausaleRespingimento CHAR(1), @causaleRespingimentoAltro VARCHAR(100), @idUnitaMisuraQuantitaRespinta CHAR(2), @quantitaRespinta DECIMAL(18, 2),
			@idMateriale CHAR(2), @materialeDescrizione VARCHAR(200),
			@idAttivitaProvenienza CHAR(1);

		SELECT
			@idMovimento = m.Id,
			@idEer = m.IdEer,
			@idProvenienza = m.IdProvenienza,
			@eerDescrizione = m.EerDescrizione,
			@idStatoFisico = m.IdStatoFisico,
			@idAttivitaRs = m.IdAttivita,
			@idUnitaMisura = m.IdUnitaMisura,
			@quantita = m.Quantita,
			@dataInizioTrasporto = m.DataInizioTrasporto,
			@idDocumentoTrasportoTipo = r.IdTrasportoTransfrontalieroTipo,
			@formularioNumero = m.FormularioNumero,
			@utenteNote = m.Note,
			@isVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),
			@veicoloFuoriUsoNumero = r.VeicoloFuoriUsoNumero,
			@veicoloFuoriUsoData = r.VeicoloFuoriUsoData,
			@idRaee = r.IdRaee,
			@idEsito = r.IdEsito,
			@quantitaVerificata = r.QuantitaVerificata,
			@dataFineTrasporto = r.DataFineTrasporto,
			@idCausaleRespingimento = r.IdCausaleRespingimento,
			@causaleRespingimentoAltro = r.CausaleRespingimentoAltro,
			@idUnitaMisuraQuantitaRespinta = r.IdUnitaMisuraQuantitaRespinta,
			@quantitaRespinta = r.QuantitaRespinta,
			@idMateriale = r.IdMateriale,
			@materialeDescrizione = r.MaterialeDescrizione,
			@idAttivitaProvenienza = r.IdAttivitaProvenienza
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @Id;

		SELECT @idAutorizzazioneProduttoreDetentore = IdAutorizzazione FROM dbo.tblRifiutiMovimentiProduttori WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneDestinatario = IdAutorizzazione FROM dbo.tblRifiutiMovimentiDestinatari WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore1 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiTrasportatori WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore2 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiTrasportatori WHERE Id = @idMovimento AND Pos = 1;
		SELECT @idAutorizzazioneTrasportatore3 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiTrasportatori WHERE Id = @idMovimento AND Pos = 2;
		SELECT @idAutorizzazioneIntermediario1 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiIntermediari WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneIntermediario2 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiIntermediari WHERE Id = @idMovimento AND Pos = 1;
		SELECT @idAutorizzazioneIntermediario3 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiIntermediari WHERE Id = @idMovimento AND Pos = 2;

		DECLARE @classiPericolo VARCHAR(50) = (
			SELECT STRING_AGG(c.Codice, ';')
			FROM
				dbo.tblRifiutiMovimentiClassiPericolo mc
				INNER JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
			WHERE mc.Id = @idMovimento
		);

		DECLARE @idEtichette VARCHAR(50) = (
			SELECT STRING_AGG(IdEtichetta, ';')
			FROM dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id
		);

		EXEC dbo.uspRifiutiRegistrazioni_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@IdEer = @idEer,
			@IdProvenienza = @idProvenienza,
			@EerDescrizione = @eerDescrizione,
			@IdStatoFisico = @idStatoFisico,
			@ClassiPericolo = @classiPericolo,
			@IdAttivitaRs = @idAttivitaRs,
			@RegistrazioneData = @RegistrazioneData,
			@RegistrazioneNumero = @RegistrazioneNumero,
			@IdUnitaMisura = @idUnitaMisura,
			@Quantita = @quantita,
			@DataInizioTrasporto = @dataInizioTrasporto,
			@IdDocumentoTrasportoTipo = @idDocumentoTrasportoTipo,
			@FormularioNumero = @formularioNumero,
			@IdAutorizzazioneProduttoreDetentore = @idAutorizzazioneProduttoreDetentore,
			@IdAutorizzazioneDestinatario = @idAutorizzazioneDestinatario,
			@IdAutorizzazioneTrasportatore1 = @idAutorizzazioneTrasportatore1,
			@IdAutorizzazioneTrasportatore2 = @idAutorizzazioneTrasportatore2,
			@IdAutorizzazioneTrasportatore3 = @idAutorizzazioneTrasportatore3,
			@IdAutorizzazioneIntermediario1 = @idAutorizzazioneIntermediario1,
			@IdAutorizzazioneIntermediario2 = @idAutorizzazioneIntermediario2,
			@IdAutorizzazioneIntermediario3 = @idAutorizzazioneIntermediario3,
			@RegistrazioneNote = @RegistrazioneNote,
			@UtenteNote = @utenteNote,
			@IdEtichette = @idEtichette,
			@IsVeicoloFuoriUso = @isVeicoloFuoriUso,
			@VeicoloFuoriUsoNumero = @veicoloFuoriUsoNumero,
			@VeicoloFuoriUsoData = @veicoloFuoriUsoData,
			@IdRaee = @idRaee,
			@IdEsito = @idEsito,
			@QuantitaVerificata = @quantitaVerificata,
			@DataFineTrasporto = @dataFineTrasporto,
			@IdCausaleRespingimento = @idCausaleRespingimento,
			@CausaleRespingimentoAltro = @causaleRespingimentoAltro,
			@IdUnitaMisuraQuantitaRespinta = @idUnitaMisuraQuantitaRespinta,
			@QuantitaRespinta = @quantitaRespinta,
			@IdMateriale = @idMateriale,
			@MaterialeDescrizione = @materialeDescrizione,
			@IdAttivitaProvenienza = @idAttivitaProvenienza,
			@RegistrazioneAuto = @RegistrazioneAuto,
			@RinumeraRegistro = @RinumeraRegistro,
			-- Sempre 1, come per la rettifica di correzione: un annullamento non partecipa mai al grafo
			-- carichi/scarichi, non è un parametro esposto al chiamante
			@NessunaRegistrazioneAssociata = 1;

		SELECT @returnValue AS ReturnValue;

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
