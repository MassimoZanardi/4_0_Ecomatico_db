SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@IdModello CHAR(16) = NULL
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

		DECLARE @idRegistro CHAR(16);
		SELECT @idRegistro = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro nel quale inserire il nuovo formulario';
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

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @idMovimento CHAR(16);
		-- Genera l'Id del movimento FUORI dalla transazione: usato in entrambi i rami IF/ELSE IF
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		BEGIN TRANSACTION;

			IF @IdOperazione IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione)
				VALUES
					(@idMovimento, @idRegistro, @IdOperazione);

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
					(@idMovimento, @idRegistro, @mIdOperazione, @mIdUnitaMisura, @mIdEer, @mIdStatoFisico, @mIdAttivita, @mIdProvenienza, @mUtenteNote);

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
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Parametro per Operazione o Modello non disponibile';
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
