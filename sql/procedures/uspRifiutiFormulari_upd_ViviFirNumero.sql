SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "Vi.Vi.FIR - Vidima formulario unico" (Rifiuti/Formulari/Edit): salva sul movimento il numero appena vidimato su
-- Vi.Vi.FIR (hub 1_0_ViviFirApi, POST /formulari/vidima) e lo marca con ViviFirVidimato = 1, che blocca il numero e non
-- fa più proporre la vidimazione. Come uspRifiutiFormulari_upd_FormularioNumero per il cartaceo RENTRI, l'hub non
-- conosce il formulario e il numero lo scrive l'app. Chiamata DOPO la vidimazione, che non è annullabile: per non
-- perdere il numero i controlli sono solo permesso e titolarità; quelli sul formulario li fa
-- uspRifiutiFormulari_get_ViviFirVidimazione prima di vidimare.
-- exec dbo.uspRifiutiFormulari_upd_ViviFirNumero @Id='...', @FormularioNumero='ZTKB 000004 M', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_upd_ViviFirNumero
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

		-- Titolarità (stesso pattern di uspRifiutiFormulari_upd)
		DECLARE @idMovimento CHAR(16);
		SELECT @idMovimento = m.Id
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

		UPDATE dbo.tblRifiutiMovimenti
		SET
			FormularioNumero = @FormularioNumero,
			ViviFirVidimato = 1
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
