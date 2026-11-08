SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 6b: rettifiche RENTRI (correzioni e annullamenti). SP interna di
-- uspMigrazioni31_ins, eseguita dentro la sua transazione dopo le relazioni (fase 6a); legge #registrazioni e scrive nel
-- #log del chiamante.
-- Verso: nella 3.1 tblRentriRegistrazioniRettifiche.IDRegistrazione = rettifica e IDRettifica = originale; in 4.0
-- Id = originale e IdRettifica = rettifica. Le registrazioni di rettifica sono gia' migrate (fase 5) con i propri valori,
-- quelli inviati al RENTRI; l'originale resta con i valori originali (registrazioni-rettifiche.md, R3.2/R4.3).
-- Valori operativi della riga 4.0 (giacenze, residui, relazioni: viewRifiutiRegistrazioniEffettive): come alla
-- conferma nell'app, con ufnRifiutiRegistrazioni_get_RettificaOperativa (uspRifiutiRegistrazioni_upd_Rettifica e
-- _upd_Annullamento). Le rettifiche si elaborano in ordine cronologico (data e numero della rettifica): la funzione
-- considera come precedenti solo le righe gia' scritte, cioe' le rettifiche confermate prima.
-- - correzione operativa: valori della rettifica; non operativa: tutti i valori operativi precedenti (tutto o niente);
-- - annullamento operativo: quantita' 0 (esce da giacenze e relazioni); non operativo: valori precedenti.
-- I valori corretti che la 3.1 scrive sull'originale (QuantitaRettifica, IdCerRettifica, IdStatoFisicoRettifica) non
-- servono: in 4.0 i valori corretti sono quelli della registrazione di rettifica.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Rettifiche
	@IdMigrazione INT = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @IdMigrazione IS NULL OR @IdDominioA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdMigrazione e @IdDominioA sono obbligatori';
			GOTO BRANCH_END;
		END

		DECLARE @idOriginale CHAR(16);
		DECLARE @idRettifica CHAR(16);
		DECLARE @annullata BIT;
		DECLARE @descrizione VARCHAR(100);
		DECLARE @operativa BIT;
		DECLARE @creati INT = 0;

		DECLARE cr CURSOR LOCAL FAST_FORWARD FOR
			SELECT
				mo.IdDestinazione,
				mx.IdDestinazione,
				ISNULL(t.Annullata, 0),
				CONCAT(IIF(ISNULL(t.Annullata, 0) = 1, 'Annullamento ', 'Correzione '), x.Numero, '/', YEAR(x.[Data]), ' della ', o.Numero, '/', YEAR(o.[Data]))
			FROM
				dbo.syn31RentriRegistrazioniRettifiche t
				INNER JOIN #registrazioni o ON t.IDRettifica = o.Id COLLATE DATABASE_DEFAULT
				INNER JOIN #registrazioni x ON t.IDRegistrazione = x.Id COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.tblMigrazioniId mo ON mo.Versione = '31'
					AND mo.IdDominioA = @IdDominioA
					AND mo.Tabella = 'tblRifiutiRegistrazioni'
					AND mo.IdOrigine = o.Id
				INNER JOIN dbo.tblMigrazioniId mx ON mx.Versione = '31'
					AND mx.IdDominioA = @IdDominioA
					AND mx.Tabella = 'tblRifiutiRegistrazioni'
					AND mx.IdOrigine = x.Id
			WHERE
				o.Importabile = 1
				AND x.Importabile = 1
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche e WHERE e.Id = mo.IdDestinazione AND e.IdRettifica = mx.IdDestinazione)
			ORDER BY x.[Data], x.Numero, x.Id;

		OPEN cr;
		FETCH cr INTO @idOriginale, @idRettifica, @annullata, @descrizione;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			INSERT INTO dbo.tblRentriRegistrazioniRettifiche (Id, IdRettifica, Annullata)
			VALUES (@idOriginale, @idRettifica, @annullata);

			SET @operativa = NULL;

			IF @annullata = 1
			BEGIN
				SELECT @operativa = o.IsOperativa
				FROM dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(@idRettifica, NULL, NULL, NULL, NULL) o;

				UPDATE t
				SET
					t.IdEer = o.IdEer,
					t.EerDescrizione = o.EerDescrizione,
					t.IdStatoFisico = o.IdStatoFisico,
					t.IdUnitaMisura = o.IdUnitaMisura,
					t.Quantita = IIF(o.IsOperativa = 1, 0, o.Quantita)
				FROM
					dbo.tblRentriRegistrazioniRettifiche t
					CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, NULL, NULL, NULL, NULL) o
				WHERE t.IdRettifica = @idRettifica;
			END
			ELSE
			BEGIN
				SELECT @operativa = o.IsOperativa
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(r.Id, m.IdEer, m.IdStatoFisico, m.IdUnitaMisura, m.Quantita) o
				WHERE r.Id = @idRettifica;

				UPDATE t
				SET
					t.IdEer = IIF(o.IsOperativa = 1, m.IdEer, o.IdEer),
					t.EerDescrizione = IIF(o.IsOperativa = 1, m.EerDescrizione, o.EerDescrizione),
					t.IdStatoFisico = IIF(o.IsOperativa = 1, m.IdStatoFisico, o.IdStatoFisico),
					t.IdUnitaMisura = IIF(o.IsOperativa = 1, m.IdUnitaMisura, o.IdUnitaMisura),
					t.Quantita = IIF(o.IsOperativa = 1, m.Quantita, o.Quantita)
				FROM
					dbo.tblRentriRegistrazioniRettifiche t
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON t.IdRettifica = r.Id
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, m.IdEer, m.IdStatoFisico, m.IdUnitaMisura, m.Quantita) o
				WHERE t.IdRettifica = @idRettifica;
			END

			SET @creati += 1;

			INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
			VALUES ('Rettifiche', 'I', 'tblRentriRegistrazioniRettifiche', @idRettifica,
				CONCAT(@descrizione, IIF(ISNULL(@operativa, 0) = 1,
					IIF(@annullata = 1, ': operativo, esce da giacenze e relazioni', ': operativa, vale anche per le giacenze'),
					IIF(@annullata = 1, ': non operativo (registrazione gia'' consumata o con carichi derivati), resta in giacenza', ': non operativa (incoerente con le relazioni), la giacenza tiene i valori precedenti'))));

			FETCH cr INTO @idOriginale, @idRettifica, @annullata, @descrizione;
		END

		CLOSE cr;
		DEALLOCATE cr;

		IF @creati > 0
			INSERT INTO #log (Fase, Livello, Tabella, Righe, Messaggio)
			VALUES ('Rettifiche', 'I', 'tblRentriRegistrazioniRettifiche', @creati, CONCAT('Migrate ', @creati, ' rettifiche'));
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
