SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "Vi.Vi.FIR - Stampa formulario unico" (Rifiuti/Formulari/Edit): controlli prima della stampa e credenziale dell'hub
-- dell'azienda del registro, con cui l'hub riscarica il PDF vidimato da Vi.Vi.FIR e ci scrive sopra i dati del
-- formulario letti da viewViviFirFormulari ([1_0_vivifir]..uspFormulario_get_Stampa).
-- exec dbo.uspRifiutiFormulari_get_ViviFirStampa @Id='...', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get_ViviFirStampa
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità (stesso pattern di uspRifiutiFormulari_get), operazione e azienda interna del registro
		DECLARE @idMovimento CHAR(16);
		DECLARE @isFormularioUnico BIT;
		DECLARE @viviFirVidimato BIT;
		DECLARE @idAziendaInterna CHAR(16);
		SELECT
			@idMovimento = m.Id,
			@isFormularioUnico = ISNULL(o.IsFormularioUnico, 0),
			@viviFirVidimato = ISNULL(m.ViviFirVidimato, 0),
			@idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il formulario non esiste';
			GOTO BRANCH_END;
		END
		IF @isFormularioUnico = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Su Vi.Vi.FIR si stampa solo il formulario unico degli spurghisti (art. 230, comma 5)';
			GOTO BRANCH_END;
		END
		IF @viviFirVidimato = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario unico non è ancora vidimato su Vi.Vi.FIR: vidimarlo prima di stamparlo';
			GOTO BRANCH_END;
		END

		DECLARE @idViviFir CHAR(16);
		SELECT @idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenzialiAziende a
			INNER JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
		WHERE
			a.IdAziendaInterna = @idAziendaInterna
			AND c.Lock = 0;

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda del registro non ha una credenziale Vi.Vi.FIR: associarla in Vivifir > Aziende';
			GOTO BRANCH_END;
		END

		SELECT IdViviFir = @idViviFir;

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
