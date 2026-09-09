/*
	Deploy produzione - 2026-09-09 - Trasmissione massiva formulari digitali RENTRI

	Contenuto di questo script (solo 4_0_ecomatico - il branch @App='40' aggiunto a
	uspFormulariDigitali_upd_DataTrasmissione nell'hub condiviso 1_0_rentri è un deploy separato, vedi
	tools/deploy_produzione_2026-09-09_trasmissione_massiva_formulari.sql nel repo 1_0_rentri):

	Motivazione: nuova azione "RENTRI - Trasmetti formulario" in Rifiuti/Registrazioni/Index - trasmette
	in blocco al RENTRI i formulari digitali dei rifiuti pericolosi già Accettato/RespintoAccettatoParzialmente
	e non ancora trasmessi, in un intervallo di numero/anno di registrazione indicato dall'utente.

	1) CREATE OR ALTER PROCEDURE dbo.uspRentriFormulari_get_TrasmissioneMassiva_List: nuova SP, elenca i
	   formulari candidati (EER pericoloso, stato Accettato/RespintoAccettatoParzialmente,
	   RentriFormularioDataTrasmissione IS NULL, nell'intervallo indicato) - riusata sia per il conteggio
	   di controllo sia per il loop di invio lato C#.

	Verificato su DB dev: deployata senza errori di compilazione, smoke test con sessione a basso
	privilegio (diniego pulito, nessun errore SQL), verifica funzionale con dati reali (elenco corretto,
	un formulario trasmesso con successo scompare da un'esecuzione successiva).

	Precondizione applicativa: il branch @App='40' di uspFormulariDigitali_upd_DataTrasmissione (repo
	1_0_rentri) deve essere deployato prima o contestualmente a questo script - senza di esso
	RentriFormularioDataTrasmissione non viene mai valorizzata e i formulari già trasmessi continuano a
	ricomparire nell'elenco.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-09_trasmissione_massiva_formulari.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRentriFormulari_get_TrasmissioneMassiva_List
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Elenco dei formulari digitali RENTRI trasmissibili in blocco (Rifiuti/Registrazioni/Index, azione
-- "RENTRI - Trasmetti formulario"): solo rifiuti pericolosi (tblRifiutiEer.Pericoloso = 1), già
-- Accettato/RespintoAccettatoParzialmente su RENTRI (stessi 2 stati di Constants.Rentri.FormularioStatiOk
-- lato C#) e non ancora trasmessi (RentriFormularioDataTrasmissione IS NULL, valorizzata dall'hub via
-- uspFormulariDigitali_upd_DataTrasmissione @App='40' dopo ogni trasmissione riuscita - lo stato da solo
-- non basta a escludere i già trasmessi, resta Accettato/RespintoAccettatoParzialmente anche dopo), filtrati
-- per intervallo di numero di registrazione nell'anno indicato. Riusata sia per il conteggio (COUNT sul
-- risultato) sia per l'invio (loop lato C# su Id/FormularioNumero).
-- exec dbo.uspRentriFormulari_get_TrasmissioneMassiva_List @IdSessione='...', @DalNumero=1, @AlNumero=999, @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFormulari_get_TrasmissioneMassiva_List]
	@IdSessione CHAR(16) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		SELECT
			f.Id,
			m.IdRegistro,
			FormularioNumero = m.FormularioNumero
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
			INNER JOIN dbo.tblRifiutiEer c ON m.IdEer = c.Id
		WHERE
			e.Id = @IdSessione
			AND f.Lock < 2
			AND c.Pericoloso = 1
			AND m.RentriFormularioStato IN ('Accettato', 'RespintoAccettatoParzialmente')
			AND m.RentriFormularioDataTrasmissione IS NULL
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
