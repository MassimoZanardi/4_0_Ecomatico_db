SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda di un importo di magazzino dell'azienda interna corrente della sessione (attivo o in bozza).
-- Contratto: descrizione del contratto o dell'offerta a cui l'importo è associato, NULL se è un importo standard.
-- ContrattoScaduto = 1: è associato a un contratto la cui validità è finita prima di oggi (avviso nella scheda).
CREATE OR ALTER PROCEDURE dbo.uspImportiMagazzino_get
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

		-- Controlla il permesso sulla funzione e che il modulo Magazzino sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
				INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			WHERE
				i.Id = @Id
				AND e.Id = @IdSessione
				AND i.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			i.Id,
			i.IdSede,
			i.Nome,
			i.IdPriorita,
			i.Lock,
			r.IdSedePartenza,
			r.IdDestinatarioParent,
			r.IdDestinatario,
			r.IdEtichetta,
			Contratto = c.Contratto,
			c.IdOffertaContratto,
			ContrattoTipo = c.Tipo,
			ContrattoDataFine = c.DataFine,
			-- Contratto (non offerta) confermato la cui validità è finita prima di oggi: la scheda lo segnala
			ContrattoScaduto = CAST(IIF(c.Tipo = 'C' AND c.Lock = 0 AND c.DataFine < CAST(GETDATE() AS DATE), 1, 0) AS BIT)
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiMagazzino r ON i.Id = r.Id
			OUTER APPLY (
				SELECT TOP (1)
					IdOffertaContratto = oc.Id,
					oc.Tipo,
					oc.DataFine,
					oc.Lock,
					Contratto = IIF(oc.Tipo = 'O', 'Offerta', 'Contratto')
						+ ISNULL(' ' + cs.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				FROM
					dbo.tblOfferteContrattiImporti ci
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
					LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
					LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
				WHERE
					ci.IdImporto = i.Id
					AND oc.Lock <= 2
			) c
		WHERE i.Id = @Id;

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
