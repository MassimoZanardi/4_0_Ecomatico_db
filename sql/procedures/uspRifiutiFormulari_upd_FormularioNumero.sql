SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "RENTRI - Crea formulario cartaceo" (Rifiuti/Formulari/Edit): salva sul movimento il numero appena
-- vidimato su RENTRI (hub POST /vidimazione-formulari/{app}/{id}). A differenza del formulario digitale
-- (uspFormulariDigitali_ins dell'hub, che scrive numero e stato), qui l'hub non conosce il formulario e
-- non scrive nulla su questo DB: RentriFormularioStato resta NULL (su RENTRI non esiste un FIR digitale) e
-- il movimento viene marcato con RentriFormularioCartaceo = 1, che blocca numero e nuove creazioni.
-- Chiamata DOPO la vidimazione, che non e' annullabile: per non perdere il numero i controlli sono
-- solo permesso, titolarita' e assenza del formulario digitale; quelli sul formulario li fa il
-- chiamante prima di vidimare (RentriFormularioService.CreaCartaceoAsync).
-- exec dbo.uspRifiutiFormulari_upd_FormularioNumero @Id='...', @FormularioNumero='ABCDE 000001 XY', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_upd_FormularioNumero
	@Id CHAR(16) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @aggiornati INT = 0;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @FormularioNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @FormularioNumero non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		-- Titolarità (stesso pattern di uspRifiutiFormulari_upd) e stato RENTRI del formulario
		DECLARE @idMovimento CHAR(16);
		DECLARE @formularioRentriStato VARCHAR(40);
		SELECT
			@idMovimento = m.Id,
			@formularioRentriStato = m.RentriFormularioStato
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il formulario non esiste';
			GOTO BRANCH_END;
		END
		IF @formularioRentriStato IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario digitale è già stato creato su RENTRI: il numero non può più essere modificato';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRifiutiMovimenti
		SET
			FormularioNumero = @FormularioNumero,
			RentriFormularioCartaceo = 1
		WHERE Id = @idMovimento;

		SET @aggiornati = @@ROWCOUNT;

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

	SELECT Aggiornati = @aggiornati;
END;
GO
