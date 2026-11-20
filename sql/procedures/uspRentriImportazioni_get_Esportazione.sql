SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta
-- in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file. Stesse righe e stesso ordine dell'elenco
-- (ufnRentriImportazioni_get_Elenco, come uspRentriImportazioni_get_List), tutte e senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Esportazione]
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (ISNULL(@MaxRighe, 2147483646) + 1)
			[Stato] = IIF(t.Stato = 'E', 'Eseguita', 'In preparazione'),
			[Registro] = t.RegistroNome,
			[Registrazioni lette] = CASE
				WHEN t.Modalita = 'F' AND t.AlNumero >= 999999 THEN CONCAT('Tutte fino all''ultima del ', t.AlAnno)
				WHEN t.Modalita = 'F' THEN CONCAT('Tutte fino al n. ', t.AlNumero, '/', t.AlAnno)
				WHEN t.AlNumero >= 999999 THEN CONCAT('Dal n. ', t.DalNumero, '/', t.DalAnno, ' fino all''ultima del ', t.AlAnno)
				ELSE CONCAT('Dal n. ', t.DalNumero, '/', t.DalAnno, ' al n. ', t.AlNumero, '/', t.AlAnno)
			END,
			[Fino al primo problema] = IIF(t.Stato = 'E', IIF(t.FinoAlPrimoProblema = 1, 'Sì', 'No'), NULL),
			[Preparata il] = t.DataCreazione,
			[Eseguita il] = t.DataEsecuzione,
			[Account] = t.UtenteAccount,
			[Registrazioni lette da RENTRI] = t.Movimenti,
			[Registrazioni importate] = t.Importate
		FROM dbo.ufnRentriImportazioni_get_Elenco(@IdSessione, @Search, @Stato, @DallaData, @AllaData) t
		ORDER BY t.Data DESC, t.Id;

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
