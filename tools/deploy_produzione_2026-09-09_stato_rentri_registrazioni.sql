/*
	Deploy produzione - 2026-09-09 - Pannello "RENTRI - Stato" in Rifiuti/Registrazioni/Edit

	Contenuto di questo script (solo 4_0_ecomatico, nessuna modifica all'hub condiviso 1_0_rentri, che
	viene solo interrogato in lettura via cross-database):

	Motivazione: nuovo pulsante "RENTRI - Stato" nel menu Azioni di Rifiuti/Registrazioni/Edit, pannello
	di sola lettura con 8 stati/date RENTRI (data trasmissione al RENTRI, data invio in conservazione,
	stato formulario, data accettazione [non tracciata, mostrata come "Non disponibile"], data
	caricamento copia formulario, data presa visione copia formulario, data esito, data trasmissione
	copia). Caricato via AJAX solo all'apertura del pannello, SP dedicata (non estende
	uspRifiutiRegistrazioni_get, su richiesta esplicita dell'utente).

	1) CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_StatoRentri: nuova SP. La colonna "data
	   invio in conservazione" e' risolta con un JOIN cross-database su [1_0_rentri]..tblRegistriConservazioni
	   (intervallo Numero/Anno del Registro, prendendo sempre la riga con Conservazione = 1 piu' recente,
	   dato che la stessa registrazione puo' essere stata portata in conservazione piu' volte). Le altre 5
	   colonne sono lette direttamente da tblRifiutiRegistrazioni/tblRifiutiMovimenti (nessuna nuova colonna
	   di tabella: tutte gia' esistenti, RentriFormularioDataTrasmissione non era mai stata letta da nessuna
	   SP applicativa finora).

	Verificato su DB dev: SP deployata senza errori di compilazione, smoke test con sessione reale su un
	movimento esistente (colonne presenti, NULL atteso dove non c'e' dato - in particolare la conservazione,
	mai completata end-to-end in dev/prod), diniego corretto su un Id inesistente/non posseduto.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-09_stato_rentri_registrazioni.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRifiutiRegistrazioni_get_StatoRentri (nuova SP)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Pannello "RENTRI - Stato" (Rifiuti/Registrazioni/Edit): 6 stati/date RENTRI in sola lettura, letti solo
-- all'apertura del pannello (SP dedicata, non parte di uspRifiutiRegistrazioni_get usata dal caricamento
-- pagina, su richiesta esplicita dell'utente). RentriDataInvioConservazione e' risolta con un JOIN
-- cross-database sull'hub 1_0_rentri: la stessa registrazione puo' essere stata portata in conservazione
-- piu' volte, si prende sempre la data piu' recente con Conservazione = 1 (TOP 1 ... ORDER BY Data DESC).
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_StatoRentri]
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			RentriData = r.RentriData,
			RentriFormularioStato = m.RentriFormularioStato,
			RentriFormularioDataCopia = m.RentriFormularioDataCopia,
			RentriFormularioDataPresaVisione = m.RentriFormularioDataPresaVisione,
			DataEsito = r.DataFineTrasporto,
			RentriFormularioDataTrasmissione = m.RentriFormularioDataTrasmissione,
			RentriDataInvioConservazione = cons.Data
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRentriRegistri rr ON rr.Id = m.IdRegistro
			OUTER APPLY (
				SELECT TOP 1 c.Data
				FROM [1_0_rentri]..tblRegistriConservazioni c
				WHERE
					c.IdRegistro = rr.IdRentri COLLATE DATABASE_DEFAULT
					AND c.Anno = YEAR(r.[Data])
					AND r.Numero BETWEEN c.DalNumero AND c.AlNumero
					AND c.Conservazione = 1
				ORDER BY c.Data DESC
			) cons
		WHERE r.Id = @Id;

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
