/*
	Deploy produzione - 2026-09-04 - Elenco conservazioni precedenti (Rifiuti/Registrazioni)

	Nuova SP uspRentriRegistrazioni_get_ElencoConservazioni: storico delle conservazioni sostitutive
	già eseguite per un registro (letto da 1_0_rentri..tblRegistriConservazioni, tabella condivisa
	gia' esistente sull'hub), filtrato per anno, bloccate prima e piu' recenti prima. Alimenta il
	link "Precedenti" nella modale di conservazione sostitutiva di Rifiuti/Registrazioni/Index -
	stesso pattern gia' in produzione di uspRentriRegistrazioni_get_ElencoInvii su
	tblRegistriInvii. Nessuna tabella nuova, nessuna modifica a oggetti esistenti.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-04_elenco_conservazioni.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Storico delle conservazioni sostitutive già eseguite per il Registro indicato, filtrate per anno
-- (default anno corrente), bloccate prima e più recenti prima. tblRegistriConservazioni vive sul DB
-- hub 1_0_rentri (stesso pattern cross-db di uspRentriRegistrazioni_get_ElencoInvii su
-- tblRegistriInvii); IdUtente è l'Id applicativo di 4_0_ecomatico salvato dall'hub al momento
-- dell'invio in conservazione, risolto qui in Email tramite tblUtenti. Equivalente al branch
-- @App='31' (uspRentriRegistrazioni_get_ElencoConservazioni su viewRentriRegistrazioniConservazioni,
-- ispezionata live il 2026-09-04) - qui senza vista intermedia, query diretta come il resto del
-- modulo in questo schema.
-- exec dbo.uspRentriRegistrazioni_get_ElencoConservazioni @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_ElencoConservazioni]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Anno INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdRentri CHAR(16);
		SELECT @IdRentri = IdRentri FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		SET @Anno = ISNULL(@Anno, YEAR(GETDATE()));

		SELECT TOP (100)
			c.[Data],
			Utente = u.Email,
			c.DalNumero,
			c.AlNumero,
			c.Blocco,
			c.Conservazione
		FROM
			[1_0_rentri]..tblRegistriConservazioni c WITH (NOLOCK)
			LEFT OUTER JOIN dbo.tblUtenti u ON u.Id = c.IdUtente COLLATE DATABASE_DEFAULT
		WHERE
			c.IdRegistro = @IdRentri COLLATE DATABASE_DEFAULT
			AND c.Anno = @Anno
		ORDER BY
			c.Blocco DESC, c.[Data] DESC;

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

END
GO
