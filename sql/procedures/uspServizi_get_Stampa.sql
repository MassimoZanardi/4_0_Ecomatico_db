SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stampa del servizio (Rapporto di intervento): dati del servizio con il layout di stampa dell'azienda della sede del
-- calendario (ufnSediReport_get_Layout). Si stampa con la funzione SRV (Servizi, dalle pagine del calendario)
-- oppure, con la sola SRA (Servizi assegnati), solo un servizio assegnato all'utente della sessione. Si stampa il
-- servizio salvato, non la bozza né la serie ricorrente (si stampa l'occorrenza modificata, come per l'esecuzione).
-- "Eseguito da" sono gli utenti assegnati. Proprietà del tipo e persone e oggetti collegati sono in
-- uspServizi_get_Stampa_Proprieta e uspServizi_get_Stampa_Collegati
CREATE OR ALTER PROCEDURE dbo.uspServizi_get_Stampa
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @assegnato BIT;
		DECLARE @lock TINYINT;
		DECLARE @idEvento CHAR(16);

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

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		-- Servizio assegnato all'utente della sessione: con la sola SRA si stampano solo questi
		SET @assegnato = IIF(EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventiUtenti u ON s.IdEvento = u.Id
				INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente
			WHERE
				s.Id = @Id
				AND ss.Id = @IdSessione
		), 1, 0);

		-- Calendario di una sede accessibile e permesso SRV, oppure SRA sul servizio assegnato
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		   OR NOT (@permessoSrv >= 1 OR (@permessoSra >= 1 AND @assegnato = 1))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			@lock = e.Lock,
			@idEvento = e.Id
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE s.Id = @Id;

		IF @lock > 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Servizio non trovato o già eliminato';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio non è ancora salvato: salvarlo prima di stamparlo';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM dbo.tblRicorrenze
		WHERE Id = @idEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio ricorrente non si stampa: per stampare un''occorrenza, modificare la sola occorrenza';
			GOTO BRANCH_END;
		END

		SELECT
			Tipo = t.Nome,
			e.[Data],
			e.InGiornata,
			s.DataRichiesta,
			Stato = st.Nome,
			s.Descrizione,
			RichiedenteNome = sr.NomeCompleto,
			RichiedenteIndirizzo = sr.IndirizzoCompleto,
			RichiedenteCodiceFiscale = sr.CodiceFiscale,
			RichiedentePartitaIva = sr.PartitaIva,
			-- Nome e cognome dell'utente, oppure l'email se non li ha (come nella finestra Assegna)
			EseguitoDa = (
				SELECT STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY n.Nome)
				FROM
					dbo.tblEventiUtenti eu
					INNER JOIN dbo.tblUtenti ut ON eu.IdUtente = ut.Id
					CROSS APPLY (SELECT Nome = ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(ut.Nome, '') + ' ' + ISNULL(ut.Cognome, ''))), ''), ut.Email)) n
				WHERE eu.Id = e.Id),
			FirmaRichiedente = (
				SELECT f.Firma
				FROM
					dbo.tblEventiFirme ef
					INNER JOIN dbo.tblFirme f ON ef.IdFirma = f.Id
				WHERE
					ef.Id = e.Id
					AND ef.IdTipo = 'R'
			),
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
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			CROSS APPLY dbo.ufnSediReport_get_Layout(ISNULL(sc.IdParent, sc.Id)) r
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblEventiStati st ON e.IdStato = st.Id
			LEFT JOIN dbo.tblSedi sr ON s.IdRichiedente = sr.Id
		WHERE s.Id = @Id;

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
