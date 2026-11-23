SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_get_Bacheca_List]
	@IdSessione CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL
AS
-- Servizi > Assegnati, vista Bacheca (S7.6): i servizi del calendario del contesto assegnati all'utente della sessione
-- nel giorno @Data, annullati esclusi, piu' quelli rimasti indietro, qualunque sia il giorno guardato: da eseguire con
-- la data di un giorno passato (riquadro Scaduti) e in esecuzione dei giorni passati (colonna In esecuzione).
-- Colonna: S scaduti, D da eseguire, I in esecuzione, E eseguiti. Come uspServiziAssegnati_get_List mostra i servizi
-- singoli e le occorrenze modificate (ufnEventi_get_Assegnati_List), mai le occorrenze generate di una serie
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

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
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Data non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 1 > @permessoSrv AND 1 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		DECLARE @idCal CHAR(16);

		SELECT @idUtente = IdUtente, @idCal = IdCalendario
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id) SELECT @idCal
		WHERE @idCal IS NOT NULL;

		-- Il giorno guardato e l'inizio di oggi: prima di oggi i servizi da eseguire o in esecuzione sono rimasti indietro
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@Data AS DATE) AS SMALLDATETIME);
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, DATEADD(DAY, 1, @inizio));
		DECLARE @oggi SMALLDATETIME = CAST(CAST(GETDATE() AS DATE) AS SMALLDATETIME);
		DECLARE @ieri SMALLDATETIME = DATEADD(MINUTE, -1, @oggi);

		;WITH cteEventi AS (
			-- Il giorno guardato
			SELECT e.Id, e.IdStato, e.[Data], e.InGiornata
			FROM dbo.ufnEventi_get_Assegnati_List(@inizio, @fine, @idUtente, @IdCalendario) e
			WHERE e.IdStato <> 'A'
			UNION
			-- Rimasti indietro, dai giorni passati
			SELECT e.Id, e.IdStato, e.[Data], e.InGiornata
			FROM dbo.ufnEventi_get_Assegnati_List('19000101', @ieri, @idUtente, @IdCalendario) e
			WHERE e.IdStato IN ('D', 'I')
		)
		SELECT
			s.Id,
			s.IdEvento,
			e.[Data],
			InGiornata = CAST(ISNULL(e.InGiornata, 0) AS BIT),
			s.Durata,
			e.IdStato,
			Colonna = CASE
				WHEN e.IdStato = 'D' AND e.[Data] < @oggi THEN 'S'
				ELSE e.IdStato
			END,
			-- Come negli altri elenchi: da eseguire o in esecuzione con la data passata (anche oggi, a un'ora gia' passata)
			Scaduto = CAST(IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0) AS BIT),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			Tipo = t.Nome,
			Richiedente = r.NomeCompleto,
			Indirizzo = r.IndirizzoCompleto,
			ev.Etichette,
			-- Proprieta' del tipo compilate (con un valore) e in tutto, per l'icona della scheda. Le caselle si/no (tipo dato
			-- B) non contano: la scheda le salva sempre (false se non spuntate) e "no" e' gia' una risposta
			ProprietaCompilate = ISNULL(p.Compilate, 0),
			ProprietaTotali = ISNULL(p.Totali, 0)
		FROM
			cteEventi e
			INNER JOIN dbo.tblEventi ev ON e.Id = ev.Id
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			OUTER APPLY (
				-- Con campi obbligatori (S3.6) contano solo quelli (una casella obbligatoria e' compilata se spuntata)
				SELECT
					Totali = COUNT(*),
					Compilate = SUM(IIF(NULLIF(LTRIM(RTRIM(v.Valore)), '') IS NULL OR (pr.IdTipoDato = 'B' AND v.Valore <> 'true'), 0, 1))
				FROM
					dbo.tblTipiProprieta tp
					LEFT JOIN dbo.tblEventiProprieta v ON v.Id = e.Id AND v.IdProprieta = tp.IdProprieta
					INNER JOIN dbo.tblProprieta pr ON tp.IdProprieta = pr.Id
				WHERE
					tp.Id = s.IdTipo
					AND tp.Lock = 0
					AND IIF(EXISTS (SELECT 1 FROM dbo.tblTipiProprieta o WHERE o.Id = s.IdTipo AND o.Lock = 0 AND o.Obbligatorio = 1),
						tp.Obbligatorio, IIF(pr.IdTipoDato <> 'B', 1, 0)) = 1
			) p
		ORDER BY
			e.[Data],
			s.Id;

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
