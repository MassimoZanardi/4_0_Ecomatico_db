SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@IdModello CHAR(16) = NULL,
	@IdCopia CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
		SET @IdCopia = NULLIF(LTRIM(RTRIM(@IdCopia)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRegistroFinale CHAR(16);
		SELECT @idRegistroFinale = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- @IdRegistro esplicito (Copia/incolla su un Registro diverso da quello corrente di sessione) sovrascrive il default
		IF @IdRegistro IS NOT NULL
			SET @idRegistroFinale = @IdRegistro;

		IF @idRegistroFinale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro nel quale inserire il nuovo formulario';
			GOTO BRANCH_END;
		END

		IF @IdRegistro IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul modello
		IF @IdModello IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @IdModello)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il modello deve generare un vero Formulario (FIR): se dichiara un documento di trasporto
		-- alternativo (es. Allegato VII/I-B per trasporto transfrontaliero), da questo modello non
		-- può essere creato un Formulario
		IF @IdModello IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiModelli m
			WHERE
				m.Id = @IdModello
				AND m.IdTrasportoTransfrontalieroTipo IS NOT NULL
				AND m.IdTrasportoTransfrontalieroTipo <> 'F')
		BEGIN
			SET @returnValue = -1;
			SELECT @returnMessage = 'Il modello utilizza "' + t.Nome + '" come documento di trasporto: non può essere usato per generare un formulario'
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiDocumentiTrasportiTipi t ON t.Id = m.IdTrasportoTransfrontalieroTipo
			WHERE m.Id = @IdModello;
			GOTO BRANCH_END;
		END

		-- Titolarità sul formulario sorgente (Copia/incolla)
		IF @IdCopia IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				r.Id = @IdCopia
				AND r.Lock < 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Lettura unica del modello (era ripetuta fino a 17 volte più sotto, una per ogni campo/EXISTS):
		-- valorizzata solo se @IdModello è specificato, riusata da tutti gli INSERT del ramo sottostante
		DECLARE
			@mIdOperazione CHAR(1),
			@mIdUnitaMisura CHAR(2),
			@mIdEer CHAR(6),
			@mIdStatoFisico CHAR(1),
			@mIdAttivita CHAR(2),
			@mIdProvenienza CHAR(1),
			@mUtenteNote VARCHAR(500),
			@mIdAutorizzazioneProduttoreDetentore CHAR(16),
			@mIdAutorizzazioneDestinatario CHAR(16),
			@mIdAutorizzazioneTrasportatore1 CHAR(16),
			@mIdAutorizzazioneTrasportatore2 CHAR(16),
			@mIdAutorizzazioneTrasportatore3 CHAR(16),
			@mIdTipoTrasporto1 CHAR(1),
			@mIdTipoTrasporto2 CHAR(1),
			@mIdTipoTrasporto3 CHAR(1),
			@mIdAutorizzazioneIntermediario1 CHAR(16),
			@mIdAutorizzazioneIntermediario2 CHAR(16),
			@mIdAutorizzazioneIntermediario3 CHAR(16),
			@mIdImballo CHAR(2),
			@mAllaRinfusa BIT,
			@mIdAdr CHAR(2),
			@mTrasportoAdr BIT,
			@mNumeroOnu VARCHAR(20),
			@mAdrNote VARCHAR(200),
			@mIdAnalisiTipo CHAR(1),
			@mAnalisiNumero VARCHAR(50),
			@mAnalisiData DATE,
			@mLuogoDiProduzione BIT,
			@mDetentore BIT,
			@mFormularioNote VARCHAR(500);

		IF @IdModello IS NOT NULL
			SELECT
				@mIdOperazione = IdOperazione,
				@mIdUnitaMisura = IdUnitaMisura,
				@mIdEer = IdEer,
				@mIdStatoFisico = IdStatoFisico,
				@mIdAttivita = IdAttivita,
				@mIdProvenienza = IdProvenienza,
				@mUtenteNote = UtenteNote,
				@mIdAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore,
				@mIdAutorizzazioneDestinatario = IdAutorizzazioneDestinatario,
				@mIdAutorizzazioneTrasportatore1 = IdAutorizzazioneTrasportatore1,
				@mIdAutorizzazioneTrasportatore2 = IdAutorizzazioneTrasportatore2,
				@mIdAutorizzazioneTrasportatore3 = IdAutorizzazioneTrasportatore3,
				@mIdTipoTrasporto1 = IdTipoTrasporto1,
				@mIdTipoTrasporto2 = IdTipoTrasporto2,
				@mIdTipoTrasporto3 = IdTipoTrasporto3,
				@mIdAutorizzazioneIntermediario1 = IdAutorizzazioneIntermediario1,
				@mIdAutorizzazioneIntermediario2 = IdAutorizzazioneIntermediario2,
				@mIdAutorizzazioneIntermediario3 = IdAutorizzazioneIntermediario3,
				@mIdImballo = IdImballo,
				@mAllaRinfusa = AllaRinfusa,
				@mIdAdr = IdAdr,
				@mTrasportoAdr = TrasportoAdr,
				@mNumeroOnu = NumeroOnu,
				@mAdrNote = AdrNote,
				@mIdAnalisiTipo = IdAnalisiTipo,
				@mAnalisiNumero = AnalisiNumero,
				@mAnalisiData = AnalisiData,
				@mLuogoDiProduzione = LuogoDiProduzione,
				@mDetentore = Detentore,
				@mFormularioNote = FormularioNote
			FROM dbo.tblRifiutiModelli
			WHERE Id = @IdModello;

		-- Lettura unica del formulario sorgente per "Copia/incolla": stesso schema del blocco Modello sopra,
		-- ma dalla coppia Formulario/Movimento esistente invece che da un Modello. Esclusi di proposito:
		-- DataEmissione (analogo di "Data di registrazione"), VerificatoInPartenza (stato legato
		-- all'esecuzione fisica del trasporto), ColliNumero, FormularioNumero (su tblRifiutiMovimenti,
		-- mai impostato da _ins), le tabelle TrasportiFerroviari/Marittimi/Terresti (dati di esecuzione
		-- del trasporto reale) e, per costruzione, qualunque riferimento a tblRifiutiRegistrazioni*:
		-- la Registrazione eventualmente associata al formulario sorgente non deve mai essere copiata.
		DECLARE
			@cIdMovimentoOrigine CHAR(16),
			@cIdOperazione CHAR(1),
			@cIdUnitaMisura CHAR(2),
			@cIdEer CHAR(6),
			@cEerDescrizione VARCHAR(200),
			@cIdStatoFisico CHAR(1),
			@cIdAttivita CHAR(2),
			@cIdProvenienza CHAR(1),
			@cNote VARCHAR(500),
			@cIdAutorizzazioneProduttoreDetentore CHAR(16),
			@cIdAutorizzazioneDestinatario CHAR(16),
			@cIdAutorizzazioneTrasportatore1 CHAR(16),
			@cIdAutorizzazioneTrasportatore2 CHAR(16),
			@cIdAutorizzazioneTrasportatore3 CHAR(16),
			@cIdTipoTrasporto1 CHAR(1),
			@cIdTipoTrasporto2 CHAR(1),
			@cIdTipoTrasporto3 CHAR(1),
			@cIdAutorizzazioneIntermediario1 CHAR(16),
			@cIdAutorizzazioneIntermediario2 CHAR(16),
			@cIdAutorizzazioneIntermediario3 CHAR(16),
			@cIdImballo CHAR(2),
			@cAllaRinfusa BIT,
			@cIdAdr CHAR(2),
			@cTrasportoAdr BIT,
			@cNumeroOnu VARCHAR(20),
			@cAdrNote VARCHAR(200),
			@cIdAnalisiTipo CHAR(1),
			@cAnalisiNumero VARCHAR(50),
			@cAnalisiData DATE,
			@cLuogoDiProduzione BIT,
			@cDetentore BIT,
			@cFormularioNote VARCHAR(500);

		IF @IdCopia IS NOT NULL
			SELECT
				@cIdMovimentoOrigine = m.Id,
				@cIdOperazione = m.IdOperazione,
				@cIdUnitaMisura = m.IdUnitaMisura,
				@cIdEer = m.IdEer,
				@cEerDescrizione = m.EerDescrizione,
				@cIdStatoFisico = m.IdStatoFisico,
				@cIdAttivita = m.IdAttivita,
				@cIdProvenienza = m.IdProvenienza,
				@cNote = m.Note,
				@cIdAutorizzazioneProduttoreDetentore = p.IdAutorizzazione,
				@cIdAutorizzazioneDestinatario = d.IdAutorizzazione,
				@cIdAutorizzazioneTrasportatore1 = t1.IdAutorizzazione,
				@cIdTipoTrasporto1 = t1.IdTipo,
				@cIdAutorizzazioneTrasportatore2 = t2.IdAutorizzazione,
				@cIdTipoTrasporto2 = t2.IdTipo,
				@cIdAutorizzazioneTrasportatore3 = t3.IdAutorizzazione,
				@cIdTipoTrasporto3 = t3.IdTipo,
				@cIdAutorizzazioneIntermediario1 = i1.IdAutorizzazione,
				@cIdAutorizzazioneIntermediario2 = i2.IdAutorizzazione,
				@cIdAutorizzazioneIntermediario3 = i3.IdAutorizzazione,
				@cIdImballo = r.IdImballo,
				@cAllaRinfusa = r.AllaRinfusa,
				@cIdAdr = r.IdAdr,
				@cTrasportoAdr = r.TrasportoAdr,
				@cNumeroOnu = r.NumeroOnu,
				@cAdrNote = r.AdrNote,
				@cIdAnalisiTipo = r.IdAnalisiTipo,
				@cAnalisiNumero = r.AnalisiNumero,
				@cAnalisiData = r.AnalisiData,
				@cLuogoDiProduzione = r.LuogoDiProduzione,
				@cDetentore = r.Detentore,
				@cFormularioNote = r.Note
			FROM
				dbo.tblRifiutiFormulari r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori p ON m.Id = p.Id AND p.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari d ON m.Id = d.Id AND d.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t1 ON m.Id = t1.Id AND t1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t2 ON m.Id = t2.Id AND t2.Pos = 1
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t3 ON m.Id = t3.Id AND t3.Pos = 2
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i1 ON m.Id = i1.Id AND i1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i2 ON m.Id = i2.Id AND i2.Pos = 1
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i3 ON m.Id = i3.Id AND i3.Pos = 2
			WHERE r.Id = @IdCopia;

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @idMovimento CHAR(16);
		-- Genera l'Id del movimento FUORI dalla transazione: usato in tutti i rami IF/ELSE IF
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		BEGIN TRANSACTION;

			IF @IdOperazione IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione)
				VALUES
					(@idMovimento, @idRegistroFinale, @IdOperazione);

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, Lock)
				VALUES
					(@returnId, @idMovimento, 2);
			END
			ELSE IF @IdModello IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, IdStatoFisico, IdAttivita, IdProvenienza, Note)
				VALUES
					(@idMovimento, @idRegistroFinale, @mIdOperazione, @mIdUnitaMisura, @mIdEer, @mIdStatoFisico, @mIdAttivita, @mIdProvenienza, @mUtenteNote);

				IF @mIdAutorizzazioneProduttoreDetentore IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneProduttoreDetentore, 0);

				IF @mIdAutorizzazioneDestinatario IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneDestinatario, 0);

				IF @mIdAutorizzazioneTrasportatore1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore1, @mIdTipoTrasporto1, 0);

				IF @mIdAutorizzazioneTrasportatore2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore2, @mIdTipoTrasporto2, 1);

				IF @mIdAutorizzazioneTrasportatore3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore3, @mIdTipoTrasporto3, 2);

				IF @mIdAutorizzazioneIntermediario1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneIntermediario1, 0);

				IF @mIdAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneIntermediario2, 1);

				IF @mIdAutorizzazioneIntermediario3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @mIdAutorizzazioneIntermediario3, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliClassiPericolo
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
					SELECT @idMovimento, IdClasse
					FROM dbo.tblRifiutiModelliClassiPericolo
					WHERE Id = @IdModello;

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, AllaRinfusa, IdAdr, TrasportoAdr, NumeroOnu, AdrNote, IdAnalisiTipo, AnalisiNumero, AnalisiData, LuogoDiProduzione, Detentore, Note, Lock)
				VALUES
					(@returnId, @idMovimento, @mIdImballo, @mAllaRinfusa, @mIdAdr, @mTrasportoAdr, @mNumeroOnu, @mAdrNote, @mIdAnalisiTipo, @mAnalisiNumero, @mAnalisiData, @mLuogoDiProduzione, @mDetentore, @mFormularioNote, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliEtichette
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
					SELECT @returnId, IdEtichetta
					FROM dbo.tblRifiutiModelliEtichette
					WHERE Id = @IdModello;
			END
			ELSE IF @IdCopia IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdProvenienza, Note)
				VALUES
					(@idMovimento, @idRegistroFinale, @cIdOperazione, @cIdUnitaMisura, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdAttivita, @cIdProvenienza, @cNote);

				IF @cIdAutorizzazioneProduttoreDetentore IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneProduttoreDetentore, 0);

				IF @cIdAutorizzazioneDestinatario IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneDestinatario, 0);

				IF @cIdAutorizzazioneTrasportatore1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore1, @cIdTipoTrasporto1, 0);

				IF @cIdAutorizzazioneTrasportatore2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore2, @cIdTipoTrasporto2, 1);

				IF @cIdAutorizzazioneTrasportatore3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore3, @cIdTipoTrasporto3, 2);

				IF @cIdAutorizzazioneIntermediario1 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneIntermediario1, 0);

				IF @cIdAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneIntermediario2, 1);

				IF @cIdAutorizzazioneIntermediario3 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @cIdAutorizzazioneIntermediario3, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiMovimentiClassiPericolo
				WHERE Id = @cIdMovimentoOrigine)
					INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
					SELECT @idMovimento, IdClasse
					FROM dbo.tblRifiutiMovimentiClassiPericolo
					WHERE Id = @cIdMovimentoOrigine;

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, AllaRinfusa, IdAdr, TrasportoAdr, NumeroOnu, AdrNote, IdAnalisiTipo, AnalisiNumero, AnalisiData, LuogoDiProduzione, Detentore, Note, Lock)
				VALUES
					(@returnId, @idMovimento, @cIdImballo, @cAllaRinfusa, @cIdAdr, @cTrasportoAdr, @cNumeroOnu, @cAdrNote, @cIdAnalisiTipo, @cAnalisiNumero, @cAnalisiData, @cLuogoDiProduzione, @cDetentore, @cFormularioNote, 2);

				-- Nessuna copia delle tabelle Trasporti Ferroviari/Marittimi/Terresti (dati di esecuzione del
				-- trasporto reale) né di tblRifiutiRegistrazioni*: la Registrazione eventualmente associata al
				-- formulario sorgente non viene mai creata/copiata.
				INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
				SELECT @returnId, IdEtichetta
				FROM dbo.tblRifiutiFormulariEtichette
				WHERE Id = @IdCopia;
			END
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Parametro per Operazione, Modello o Copia non disponibile';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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
