SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Righe di un importo (rifiuti, magazzino o servizi) dell'azienda interna corrente della sessione, nell'ordine
-- in cui finiranno in fattura. Una riga senza importo è di sola descrizione.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_get_List
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo deve appartenere all'azienda interna corrente della sessione e il suo modulo (quello dei
		-- documenti a cui si applica) deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @IdImporto
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.IdImporto,
			g.IdTipo,
			Tipo = t.Nome,
			g.Importo,
			MinimoFatturabile = ISNULL(g.MinimoFatturabile, 0),
			d.IdAliquotaIva,
			AliquotaIvaNome = a.Nome,
			d.IdConto,
			ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome,
			d.Descrizione,
			g.Pos,
			-- Solo per gli importi di magazzino: articolo o materiale EoW della riga a quantità
			x.IdArticolo,
			x.IdMateriale,
			-- Solo per gli importi dei servizi: risorsa (persona o oggetto) della riga a quantità
			xs.IdOsepe,
			Voce = COALESCE(ar.Nome + ISNULL(' (' + ar.Codice + ')', ''), 'EoW: ' + ma.Nome, pe.NomeCompleto, og.Nome)
		FROM
			dbo.tblImportiRighe g
			LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
			LEFT JOIN dbo.tblImportiRigheMagazzino x ON g.Id = x.Id
			LEFT JOIN dbo.tblMagazziniArticoli ar ON x.IdArticolo = ar.Id
			LEFT JOIN dbo.tblRifiutiMateriali ma ON x.IdMateriale = ma.Id
			LEFT JOIN dbo.tblImportiRigheServizi xs ON g.Id = xs.Id
			LEFT JOIN dbo.tblPersone pe ON xs.IdOsepe = pe.Id
			LEFT JOIN dbo.tblOggetti og ON xs.IdOsepe = og.Id
			LEFT JOIN dbo.tblImportiRigheTipi t ON g.IdTipo = t.Id
			LEFT JOIN dbo.tblAliquoteIva a ON d.IdAliquotaIva = a.Id
			LEFT JOIN dbo.tblFattureConti c ON d.IdConto = c.Id
		WHERE g.IdImporto = @IdImporto
		ORDER BY ISNULL(g.Pos, 0), g.Id;

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
