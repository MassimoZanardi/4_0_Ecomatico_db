SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati per "Verifica Vi.Vi.FIR" di un'azienda interna (Vivifir > Aziende): la credenziale dell'hub associata e il codice
-- fiscale e la partita IVA dell'azienda, con cui l'app riconosce il soggetto tra quelli che la credenziale rappresenta
-- su Vi.Vi.FIR. Stessi controlli di uspViviFirAziende_upd: chi verifica salva anche l'esito
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_get_Verifica]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
			GOTO BRANCH_END;
		END
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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = e.IdDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idViviFir CHAR(16);
		SELECT @idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenzialiAziende a
			INNER JOIN dbo.tblViviFirCredenziali c ON a.IdCredenziale = c.Id
		WHERE
			a.IdAziendaInterna = @IdAziendaInterna
			AND c.Lock = 0;

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Associare e salvare prima una credenziale Vi.Vi.FIR';
			GOTO BRANCH_END;
		END

		SELECT
			IdViviFir = @idViviFir,
			s.CodiceFiscale,
			s.PartitaIva
		FROM dbo.tblSedi s
		WHERE s.Id = @IdAziendaInterna;

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
