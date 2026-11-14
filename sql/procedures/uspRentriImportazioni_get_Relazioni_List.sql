SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: relazioni carico/scarico proposte (ripartizione FIFO) o corrette dall'utente, una riga per
-- coppia padre/figlio, in ordine di padre (data e numero) e di figlio. Padre = la registrazione che associa (scarico
-- che preleva, Operazione S; carico K/M che deriva dallo scarico R, Operazione C); figlio = l'associata, letta da
-- RENTRI (area temporanea) o già presente in Ecomatico.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Relazioni_List]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
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

		-- Controlla il permesso sul record (titolarità) tramite il registro
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			l.PadreAnno,
			l.PadreProgressivo,
			PadreData = p.Data,
			PadreCausale = p.Causale,
			PadreQuantita = p.Quantita,
			PadreUnitaMisura = p.UnitaMisura,
			PadreAzione = p.Azione,
			PadreIsAnnullato = p.IsAnnullato,
			l.Operazione,
			l.FiglioAnno,
			l.FiglioProgressivo,
			FiglioData = ISNULL(f.Data, r.Data),
			FiglioCausale = ISNULL(f.Causale, o.Codice),
			FiglioQuantita = ISNULL(f.Quantita, e.Quantita),
			FiglioAzione = f.Azione,
			IsFiglioInEcomatico = CAST(IIF(f.Azione IS NULL OR f.Azione = 'P', IIF(l.IdRegistrazioneFiglio IS NULL, 0, 1), 0) AS BIT),
			l.Pos,
			l.DisponibilePrima,
			l.QuantitaProposta,
			l.Quantita,
			l.IsModificata,
			Figli = COUNT(*) OVER (PARTITION BY l.PadreAnno, l.PadreProgressivo)
		FROM
			dbo.tblRentriImportazioniRelazioni l
			INNER JOIN dbo.tblRentriImportazioniMovimenti p
				ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
			LEFT JOIN dbo.tblRentriImportazioniMovimenti f
				ON f.IdImportazione = l.IdImportazione AND f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON l.IdRegistrazioneFiglio = r.Id
			LEFT JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON v.IdOperazione = o.Id
			LEFT JOIN dbo.viewRifiutiRegistrazioniEffettive e ON r.Id = e.Id
		WHERE l.IdImportazione = @Id
		ORDER BY p.Data, l.PadreAnno, l.PadreProgressivo, ISNULL(f.Data, r.Data), l.FiglioAnno, l.FiglioProgressivo;

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
