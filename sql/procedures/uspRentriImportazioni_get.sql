SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: testata e riepilogo dell'importazione (anteprima). Con @Id NULL restituisce l'importazione
-- in preparazione del registro @IdRegistro, se c'è (ripresa del lavoro dopo aver lasciato la pagina).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
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

		IF @Id IS NULL
			SELECT TOP 1 @Id = Id
			FROM dbo.tblRentriImportazioni
			WHERE IdRegistro = @IdRegistro AND Stato = 'P'
			ORDER BY DataCreazione DESC;

		-- Controlla il permesso sul record (titolarità) tramite il registro; nessuna importazione = nessuna riga
		SELECT
			m.Id,
			m.IdRegistro,
			RegistroNome = g.Nome,
			m.Modalita,
			m.DalAnno,
			m.DalNumero,
			m.AlAnno,
			m.AlNumero,
			m.Stato,
			m.FinoAlPrimoProblema,
			m.DataCreazione,
			m.DataAnalisi,
			m.DataEsecuzione,
			UtenteNome = LTRIM(RTRIM(CONCAT(u.Nome, ' ', u.Cognome))),
			Movimenti = s.Movimenti,
			DaImportare = s.DaImportare,
			GiaPresenti = s.GiaPresenti,
			Escluse = s.Escluse,
			FuoriIntervallo = s.FuoriIntervallo,
			Rettifiche = s.Rettifiche,
			Annullamenti = s.Annullamenti,
			Errori = a.Errori,
			Avvisi = a.Avvisi,
			Relazioni = (SELECT COUNT(*) FROM dbo.tblRentriImportazioniRelazioni z WHERE z.IdImportazione = m.Id),
			RelazioniModificate = (SELECT COUNT(DISTINCT CONCAT(z.PadreAnno, '/', z.PadreProgressivo)) FROM dbo.tblRentriImportazioniRelazioni z WHERE z.IdImportazione = m.Id AND z.IsModificata = 1)
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			LEFT JOIN dbo.tblUtenti u ON m.IdUtente = u.Id
			CROSS APPLY (
				SELECT
					Movimenti = COUNT(*),
					DaImportare = ISNULL(SUM(IIF(x.Azione = 'I', 1, 0)), 0),
					GiaPresenti = ISNULL(SUM(IIF(x.Azione = 'P', 1, 0)), 0),
					Escluse = ISNULL(SUM(IIF(x.Azione = 'X', 1, 0)), 0),
					FuoriIntervallo = ISNULL(SUM(IIF(x.IsIntervallo = 0, 1, 0)), 0),
					Rettifiche = ISNULL(SUM(IIF(x.Tipo = 'R', 1, 0)), 0),
					Annullamenti = ISNULL(SUM(IIF(x.Tipo = 'A', 1, 0)), 0)
				FROM dbo.tblRentriImportazioniMovimenti x
				WHERE x.IdImportazione = m.Id
			) s
			CROSS APPLY (
				SELECT
					Errori = ISNULL(SUM(IIF(y.Livello = 'E', 1, 0)), 0),
					Avvisi = ISNULL(SUM(IIF(y.Livello = 'W', 1, 0)), 0)
				FROM dbo.tblRentriImportazioniAnomalie y
				WHERE y.IdImportazione = m.Id
			) a
		WHERE m.Id = @Id;

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
