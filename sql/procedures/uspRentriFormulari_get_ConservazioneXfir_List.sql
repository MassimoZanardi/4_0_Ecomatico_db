SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Elenco dei movimenti RENTRI coinvolti nella conservazione sostitutiva xFIR (Rifiuti/Registrazioni/
-- Index, azione "RENTRI - Conservazione sostitutiva xFIR"): FIR digitali con stato Accettato/
-- RespintoAccettatoParzialmente (stessi 2 stati di Constants.Rentri.FormularioStatiOk lato C#, gia'
-- usati con lo stesso significato in uspRentriFormulari_get_TrasmissioneMassiva_List - "ha concluso il
-- suo ciclo di vita" per Accettato), filtrati per intervallo di numero di registrazione nell'anno
-- indicato. Nessun JOIN a tblRifiutiFormulari (a differenza di TrasmissioneMassiva_List): i campi
-- Rentri* vivono su tblRifiutiMovimenti proprio per coprire anche i movimenti IsIntegrazioneFir=1
-- senza un proprio formulario (vedi RentriFormularioStato spostato da tblRifiutiFormulari), un JOIN a
-- f li escluderebbe. Nessun filtro RentriFormularioDataCopia (non e' valorizzato per i movimenti
-- IsIntegrazioneFir=1 lato integrazione): lo stato Accettato/RespintoAccettatoParzialmente basta da
-- solo a indicare il FIR concluso. Nessun filtro sulla pericolosita' del rifiuto (a differenza di
-- uspRentriFormulari_get_TrasmissioneMassiva_List): la conservazione riguarda il documento digitale,
-- non l'obbligo di trasmissione dei soli pericolosi.
-- @EscludiGiaConservati: se 1 (default), esclude i formulari con RentriFormularioDataConservazione
-- gia' valorizzata. Riusata sia per il conteggio (COUNT sul risultato) sia per l'invio in
-- conservazione sia per il download del pacchetto xFIR (loop lato C# su Id/FormularioNumero - Id e'
-- l'Id del MOVIMENTO, non del formulario: usato poi da uspRifiutiMovimenti_upd_Conservazione).
-- TOP (101): il limite applicativo per singola tranche e' 100 (Constants.Rentri.ConservazioneXfirMaxTranche
-- lato C#) - la 101a riga, se presente, serve solo a segnalare che ce ne sono altri oltre ai 100
-- effettivamente lavorati (RentriFormularioService taglia sempre a 100), senza una seconda query di COUNT.
-- exec dbo.uspRentriFormulari_get_ConservazioneXfir_List @IdSessione='...', @DalNumero=1, @AlNumero=999, @Anno=2026, @EscludiGiaConservati=1
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFormulari_get_ConservazioneXfir_List]
	@IdSessione CHAR(16) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@EscludiGiaConservati BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @EscludiGiaConservati = ISNULL(@EscludiGiaConservati, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''intervallo di numero e l''anno';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (101)
			m.Id,
			m.IdRegistro,
			FormularioNumero = m.FormularioNumero
		FROM
			dbo.tblRifiutiMovimenti m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON r.IdMovimento = m.Id AND r.Lock < 2
		WHERE
			e.Id = @IdSessione
			AND m.RentriFormularioStato IN ('Accettato', 'RespintoAccettatoParzialmente')
			AND (@EscludiGiaConservati = 0 OR m.RentriFormularioDataConservazione IS NULL)
			AND r.Numero BETWEEN @DalNumero AND @AlNumero
			AND YEAR(r.[Data]) = @Anno
		ORDER BY r.Numero;

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

END
GO
