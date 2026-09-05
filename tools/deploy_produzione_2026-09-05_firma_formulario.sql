/*
	Deploy produzione - 2026-09-05 - Firma formulario digitale RENTRI (firma di partenza), Fase 1

	Contenuto di questo script (solo 4_0_ecomatico - nessuna modifica al DB 1_0_rentri: l'hub calcolo-hash/
	acquisizione-firma/credentials-info aggiunto in 1_0_RentriApi per questa fase e' puramente applicativo,
	non richiede nuove SP condivise):

	1) CREATE OR ALTER PROCEDURE dbo.uspRentriRegistri_get_IdCredenziale: risolve la credenziale di firma
	   remota primaria (tblRentriCredenzialiSedi WHERE Pos=0) collegata alla Sede di un Registro, dato
	   l'IdSessione dell'utente loggato. Usata da RentriFormularioService per determinare con quale
	   credenziale firmare un formulario dalla pagina Rifiuti/Formulari/Edit (stesso schema gia' in uso per
	   la "firma di prova" in Rentri/FirmaRemota, dove pero' la Credenziale viene scelta esplicitamente
	   dall'Amministratore invece che risolta dal Registro in contesto).

	   NOTA: questa SP era gia' inclusa nel bundle tools/deploy_produzione_2026-09-04_firma_remota_operatore.sql
	   (segnato come gia' applicato in produzione a suo tempo), ma non risultava presente sul DB dev - non e'
	   chiaro se il deploy di allora sia stato effettivamente completato in produzione. CREATE OR ALTER e'
	   comunque idempotente: rieseguirlo non ha effetti collaterali se l'oggetto esiste gia' identico.

	Verificato su DB dev: creata da zero (non esisteva), risoluzione IdCredenziale confermata su un Registro
	di test con credenziale primaria collegata.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-05_firma_formulario.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRentriRegistri_get_IdCredenziale
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get_IdCredenziale]
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdSede CHAR(16);
		SELECT @IdSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCredenziale CHAR(16);
		SELECT @IdCredenziale = IdCredenziale
		FROM dbo.tblRentriCredenzialiSedi
		WHERE IdSede = @IdSede AND Pos = 0;

		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
			GOTO BRANCH_END;
		END

		SELECT rtn = @IdCredenziale;

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
