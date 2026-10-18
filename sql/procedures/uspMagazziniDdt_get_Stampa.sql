SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stampa del DDT di un movimento: dati del documento con il layout di stampa dell'azienda del movimento
-- (ufnSediReport_get_Layout). Si stampa solo un DDT emesso e confermato: non la bozza (il numero si assegna alla
-- conferma) né il DDT ricevuto da un fornitore (sezionale R). Senza destinazione si stampa la sede del
-- destinatario (M7.6.1). Le righe sono in uspMagazziniDdt_get_Stampa_Righe
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get_Stampa
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il movimento è dell'azienda del contesto, come in uspMagazziniDdt_get
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock TINYINT, @sezionale CHAR(1);
		SELECT
			@lock = IIF(d.Lock > m.Lock, d.Lock, m.Lock),
			@sezionale = d.Sezionale
		FROM
			dbo.tblMagazziniDdt d
			INNER JOIN dbo.tblMagazziniMovimenti m ON d.IdMovimento = m.Id
		WHERE d.IdMovimento = @IdMovimento;

		IF @lock IS NULL OR @lock > 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il movimento non ha un DDT da stampare';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il DDT non è ancora confermato: salvare il movimento prima di stamparlo';
			GOTO BRANCH_END;
		END
		IF @sezionale = 'R'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il DDT ricevuto da un fornitore non si stampa';
			GOTO BRANCH_END;
		END

		SELECT
			d.Numero,
			d.Sezionale,
			d.Data,
			Causale = c.Nome,
			MittenteNome = sm.NomeCompleto,
			MittenteIndirizzo = sm.IndirizzoCompleto,
			MittenteCodiceFiscale = sm.CodiceFiscale,
			MittentePartitaIva = sm.PartitaIva,
			DestinatarioNome = sd.NomeCompleto,
			DestinatarioIndirizzo = sd.IndirizzoCompleto,
			DestinatarioCodiceFiscale = sd.CodiceFiscale,
			DestinatarioPartitaIva = sd.PartitaIva,
			DestinazioneNome = ISNULL(sz.NomeCompleto, sd.NomeCompleto),
			DestinazioneIndirizzo = IIF(sz.Id IS NULL, sd.IndirizzoCompleto, sz.IndirizzoCompleto),
			TrasportatoreNome = st.NomeCompleto,
			TrasportatoreIndirizzo = st.IndirizzoCompleto,
			d.DataInizioTrasporto,
			d.Peso,
			r.IdLayout,
			r.Intestazione,
			r.PiePagina,
			r.IntestazioneColore,
			r.IntestazioneFontSize,
			r.IntestazioneAllineamento,
			r.PiePaginaColore,
			r.PiePaginaFontSize,
			r.PiePaginaAllineamento,
			r.Logo
		FROM
			dbo.tblMagazziniDdt d
			INNER JOIN dbo.tblMagazziniMovimenti m ON d.IdMovimento = m.Id
			CROSS APPLY dbo.ufnSediReport_get_Layout(m.IdSede) r
			LEFT JOIN dbo.tblMagazziniCausali c ON d.IdCausale = c.Id
			LEFT JOIN dbo.tblSedi sm ON d.IdMittente = sm.Id
			LEFT JOIN dbo.tblSedi sd ON d.IdDestinatario = sd.Id
			LEFT JOIN dbo.tblSedi sz ON d.IdDestinazione = sz.Id
			LEFT JOIN dbo.tblSedi st ON d.IdTrasportatore = st.Id
		WHERE d.IdMovimento = @IdMovimento;

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
