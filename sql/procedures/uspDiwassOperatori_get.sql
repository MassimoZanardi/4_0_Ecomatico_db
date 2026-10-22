SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda di Diwass > Operatori: dati della sede (per la ricerca su DIWASS), dell'azienda a cui appartiene e del
-- collegamento a DIWASS della sede e dell'azienda
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassOperatori_get]
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): sede del contesto o condivisa
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione)
			WHERE Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			s.PartitaIva,
			s.CodiceFiscale,
			Paese = n.Sigla,
			IsSedePrincipale = CAST(IIF(s.IdParent IS NULL, 1, 0) AS BIT),
			s.IdParent,
			AziendaNome = p.NomeCompleto,
			AziendaOperatorInternalId = po.OperatorInternalId,
			AziendaOperatoreNome = po.Nome,
			v.Condivisa,
			v.Area,
			o.OperatorInternalId,
			o.LinkedOperatorInternalId,
			OperatoreNome = o.Nome,
			OperatoreIndirizzo = o.Indirizzo,
			OperatorePaese = o.Paese,
			OperatoreIdentificativo = o.Identificativo,
			OperatoreStato = o.Stato,
			OperatoreDataVerifica = o.DataVerifica
		FROM
			dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v
			INNER JOIN dbo.tblSedi s ON v.Id = s.Id
			LEFT JOIN dbo.tblSedi p ON s.IdParent = p.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON s.Id = o.Id
			LEFT JOIN dbo.tblDiwassOperatori po ON s.IdParent = po.Id
			OUTER APPLY (
				SELECT TOP 1 z.Sigla
				FROM
					dbo.tblSediIndirizzi si
					INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
					INNER JOIN dbo.tblNazioni z ON i.IdNazione = z.Id
				WHERE si.Id = s.Id) n
		WHERE v.Id = @Id;

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
