SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- "Verifica importo e cliente": righe di fattura che la generazione automatica creerebbe per il documento, con
-- l'importo che gli viene applicato (rifiuti, DDT di magazzino o servizi). Stessi controlli di accesso di
-- uspFattureDocumenti_get: senza accesso, o per un modulo non gestito, nessuna riga e nessun errore.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Righe
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
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

		IF ISNULL(@IdModulo, '') = 'RIF'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND dbo.ufnFunzioni_get_PermessoBySessione('RRG', @IdSessione) >= 1
		BEGIN
			SELECT
				g.Id,
				g.Pos,
				g.Descrizione,
				g.SolaDescrizione,
				g.MinimoFatturabile,
				g.Quantita,
				UnitaMisura = g.IdUnitaMisura,
				g.Importo,
				g.Imponibile,
				AliquotaIvaNome = v.Nome,
				ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome
			FROM
				dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
				CROSS APPLY dbo.ufnImportiRifiuti_get_ApplicazioneRighe(a.Id) g
				LEFT JOIN dbo.tblAliquoteIva v ON g.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblFattureConti c ON g.IdConto = c.Id
			WHERE
				a.IsFatturabile = 1
				AND a.IsRettifica = 0
			ORDER BY ISNULL(g.Pos, 0), g.Id
			OPTION (RECOMPILE);
		END


		-- DDT di magazzino: le righe dell'importo applicato, prima quelle a quantità nell'ordine del DDT, poi le altre
		IF ISNULL(@IdModulo, '') = 'MAG'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND dbo.ufnFunzioni_get_PermessoBySessione('MAG', @IdSessione) >= 1
		BEGIN
			SELECT
				g.Id,
				Pos = CAST(ROW_NUMBER() OVER (ORDER BY g.Gruppo, g.PosDdt, g.IdRigaDdt, ISNULL(g.Pos, 0), g.Id) AS INT),
				g.Descrizione,
				g.SolaDescrizione,
				g.MinimoFatturabile,
				g.Quantita,
				UnitaMisura = g.IdUnitaMisura,
				g.Importo,
				g.Imponibile,
				AliquotaIvaNome = v.Nome,
				ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome
			FROM
				dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
				CROSS APPLY dbo.ufnImportiMagazzino_get_RigheFattura(a.Id, a.IdClienteFornitore) g
				LEFT JOIN dbo.tblAliquoteIva v ON g.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblFattureConti c ON g.IdConto = c.Id
			WHERE a.IsFatturabile = 1
			ORDER BY g.Gruppo, g.PosDdt, g.IdRigaDdt, ISNULL(g.Pos, 0), g.Id
			OPTION (RECOMPILE);
		END

		-- Servizi: le righe dell'importo applicato, prima quelle delle risorse, poi quelle una volta per servizio
		IF ISNULL(@IdModulo, '') = 'SRV'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND dbo.ufnFunzioni_get_PermessoBySessione('SRV', @IdSessione) >= 1
		BEGIN
			SELECT
				g.Id,
				Pos = CAST(ROW_NUMBER() OVER (ORDER BY g.Gruppo, g.PosServizio, ISNULL(g.Pos, 0), g.Id) AS INT),
				g.Descrizione,
				g.SolaDescrizione,
				g.MinimoFatturabile,
				g.Quantita,
				UnitaMisura = g.IdUnitaMisura,
				g.Importo,
				g.Imponibile,
				AliquotaIvaNome = v.Nome,
				ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome
			FROM
				dbo.ufnImportiServizi_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeInterna = x.Id
				CROSS APPLY dbo.ufnImportiServizi_get_RigheFattura(a.Id, a.IdClienteFornitore) g
				LEFT JOIN dbo.tblAliquoteIva v ON g.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblFattureConti c ON g.IdConto = c.Id
			WHERE a.IsFatturabile = 1
			ORDER BY g.Gruppo, g.PosServizio, ISNULL(g.Pos, 0), g.Id
			OPTION (RECOMPILE);
		END

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
