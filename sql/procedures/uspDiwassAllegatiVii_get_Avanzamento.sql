SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'Allegato VII, riquadro "Avanzamento della spedizione": una riga per passaggio previsto, nell'ordine del
-- documento (presa in carico di ogni trasportatore, ricezione del destinatario, ricezione e recupero completato di ogni
-- impianto), con la conferma letta da DIWASS se c'è (stesso operatore del soggetto). La ricezione del destinatario non è
-- prevista se il destinatario è anche l'impianto (Reg. di esecuzione UE 2025/1290 art. 17.2). DellAzienda = il
-- soggetto è un'azienda del contesto (sede interna collegata allo stesso operatore). Regole in docs/regole/diwass.md D6
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Avanzamento]
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

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16) = (
			SELECT a.IdAziendaInterna
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione
		);
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Soggetti con l'operatore DIWASS (della sede in anagrafica o letto da DIWASS)
		DECLARE @soggetti TABLE (
			Ruolo CHAR(1),
			Pos TINYINT,
			OperatorInternalId BIGINT,
			Nome NVARCHAR(250),
			DellAzienda BIT
		);
		INSERT INTO @soggetti (Ruolo, Pos, OperatorInternalId, Nome, DellAzienda)
		SELECT
			x.Ruolo,
			x.Pos,
			ISNULL(o.OperatorInternalId, x.OperatorInternalId),
			ISNULL(s.NomeCompleto, x.Nome),
			IIF(EXISTS (
				SELECT 1
				FROM
					dbo.tblDiwassOperatori oa
					INNER JOIN dbo.tblSedi sa ON oa.Id = sa.Id
				WHERE
					oa.OperatorInternalId = ISNULL(o.OperatorInternalId, x.OperatorInternalId)
					AND sa.InternaEsterna = 'I'
					AND sa.IdAziendaInterna = @idAzienda
			), 1, 0)
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			LEFT JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
		WHERE
			x.Id = @Id
			AND x.Ruolo IN ('T', 'D', 'I');

		DECLARE @destinatarioImpianto BIT = IIF(EXISTS (
			SELECT 1
			FROM
				@soggetti d
				INNER JOIN @soggetti i ON d.OperatorInternalId = i.OperatorInternalId
			WHERE
				d.Ruolo = 'D'
				AND i.Ruolo = 'I'
		), 1, 0);

		SELECT
			p.Ordine,
			p.Tipo,
			p.Pos,
			Passaggio = CASE p.Tipo
				WHEN 'T' THEN N'Presa in carico'
				WHEN 'D' THEN N'Ricezione del destinatario'
				WHEN 'I' THEN N'Ricezione all''impianto'
				ELSE N'Recupero completato'
			END,
			SoggettoNome = p.Nome,
			p.DellAzienda,
			Prevista = CAST(IIF(p.Tipo = 'D' AND @destinatarioImpianto = 1, 0, 1) AS BIT),
			NumeroConferma = c.Numero,
			c.Data,
			c.MezzoTrasporto,
			c.Targhe,
			c.UnitaQuantita,
			c.QuantitaAccettata,
			c.QuantitaRespinta,
			c.MotivoRespingimento,
			c.QuantitaRiutilizzo,
			c.QuantitaRecupero,
			c.Descrizione,
			c.FirmaNome,
			c.FirmaRuolo,
			c.FirmaData
		FROM (
			SELECT
				Ordine = CASE s.Ruolo WHEN 'T' THEN 0 WHEN 'D' THEN 1 ELSE 2 END,
				Tipo = t.Tipo,
				s.Pos,
				s.OperatorInternalId,
				s.Nome,
				s.DellAzienda
			FROM
				@soggetti s
				CROSS APPLY (
					SELECT Tipo = s.Ruolo
					WHERE s.Ruolo IN ('T', 'D', 'I')
					UNION ALL
					SELECT Tipo = 'C'
					WHERE s.Ruolo = 'I'
				) t
		) p
		OUTER APPLY (
			SELECT TOP 1 *
			FROM dbo.tblDiwassAllegatiViiConferme k
			WHERE
				k.Id = @Id
				AND k.Tipo = p.Tipo
				AND k.OperatorInternalId = p.OperatorInternalId
			ORDER BY k.Pos
		) c
		ORDER BY p.Ordine, p.Pos, IIF(p.Tipo = 'C', 1, 0);

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
