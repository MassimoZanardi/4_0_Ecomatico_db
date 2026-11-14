SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: movimenti dell'anteprima, in ordine di anno e numero, con l'azione prevista e le anomalie
-- di ciascuno (la più grave determina il Livello: E bloccante, W avviso, I informazione).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Movimenti_List]
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
			m.Anno,
			m.Progressivo,
			m.Identificativo,
			m.Data,
			m.DataTrasmissione,
			m.Tipo,
			TipoNome =
				CASE m.Tipo
					WHEN 'R' THEN CONCAT('Rettifica della n. ', m.RettificaProgressivo, '/', m.RettificaAnno)
					WHEN 'A' THEN CONCAT('Annullamento della n. ', m.RettificaProgressivo, '/', m.RettificaAnno)
					ELSE NULL
				END,
			m.Causale,
			m.IdOperazione,
			OperazioneNome = o.Nome,
			m.Eer,
			m.StatoFisico,
			m.Quantita,
			m.UnitaMisura,
			m.IsAnnullato,
			m.IsRettificato,
			m.IsIntervallo,
			m.Azione,
			Livello = CASE x.Ordine WHEN 1 THEN 'E' WHEN 2 THEN 'W' WHEN 3 THEN 'I' ELSE NULL END,
			Anomalie = x.Anomalie
		FROM
			dbo.tblRentriImportazioniMovimenti m
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			OUTER APPLY (
				SELECT
					Ordine = MIN(CASE y.Livello WHEN 'E' THEN 1 WHEN 'W' THEN 2 ELSE 3 END),
					Anomalie = STRING_AGG(CAST(y.Messaggio AS NVARCHAR(MAX)), N' - ') WITHIN GROUP (ORDER BY y.Id)
				FROM dbo.tblRentriImportazioniAnomalie y
				WHERE y.IdImportazione = m.IdImportazione AND y.Anno = m.Anno AND y.Progressivo = m.Progressivo
			) x
		WHERE m.IdImportazione = @Id
		ORDER BY m.Anno, m.Progressivo;

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
