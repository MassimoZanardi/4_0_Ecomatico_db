SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- "Vi.Vi.FIR - Vidima formulario unico" (Rifiuti/Formulari/Edit): dati per chiedere all'hub Vi.Vi.FIR un nuovo numero
-- sul blocco dell'azienda del registro (Vivifir > Aziende, uspViviFirAziende_upd_Verifica). Tutti i controlli sul
-- formulario si fanno qui, prima della vidimazione, che non è annullabile: dopo, uspRifiutiFormulari_upd_ViviFirNumero
-- salva il numero con i soli controlli di permesso e titolarità.
-- exec dbo.uspRifiutiFormulari_get_ViviFirVidimazione @Id='...', @IdSessione='...'
CREATE OR ALTER PROCEDURE dbo.uspRifiutiFormulari_get_ViviFirVidimazione
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
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF dbo.ufnModuli_get_IsAttivoBySessione('VVF', @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il modulo Vi.Vi.FIR non è attivo: il formulario unico non può essere vidimato';
			GOTO BRANCH_END;
		END

		-- Titolarità (stesso pattern di uspRifiutiFormulari_upd), operazione e azienda interna del registro
		DECLARE @idMovimento CHAR(16);
		DECLARE @isFormularioUnico BIT;
		DECLARE @viviFirVidimato BIT;
		DECLARE @formularioNumero VARCHAR(20);
		DECLARE @idAziendaInterna CHAR(16);
		SELECT
			@idMovimento = m.Id,
			@isFormularioUnico = ISNULL(o.IsFormularioUnico, 0),
			@viviFirVidimato = ISNULL(m.ViviFirVidimato, 0),
			@formularioNumero = m.FormularioNumero,
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
			SET @returnMessage = 'Su Vi.Vi.FIR si vidima solo il formulario unico degli spurghisti (art. 230, comma 5)';
			GOTO BRANCH_END;
		END
		IF @viviFirVidimato = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = CONCAT('Il formulario ha già il numero vidimato su Vi.Vi.FIR ', @formularioNumero);
			GOTO BRANCH_END;
		END

		DECLARE @idViviFir CHAR(16);
		DECLARE @idSoggetto INT;
		DECLARE @blocco VARCHAR(10);
		SELECT
			@idViviFir = c.IdViviFir,
			@idSoggetto = a.IdSoggetto,
			@blocco = a.Blocco
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
		IF @idSoggetto IS NULL OR @blocco IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda del registro non ha un blocco Vi.Vi.FIR per il formulario unico: eseguire Verifica Vi.Vi.FIR in Vivifir > Aziende';
			GOTO BRANCH_END;
		END

		SELECT
			IdViviFir = @idViviFir,
			IdSoggetto = @idSoggetto,
			Blocco = @blocco;

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
