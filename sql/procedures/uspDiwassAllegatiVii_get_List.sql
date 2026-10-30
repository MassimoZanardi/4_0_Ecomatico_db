SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Allegati VII: documenti dell'azienda del contesto, inviati da Ecomatico o ricevuti da DIWASS (Ricevuto = 1),
-- dal più recente, con i ruoli dell'azienda, l'avanzamento e il passaggio che le spetta (docs/regole/diwass.md D6)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@Ruolo CHAR(1) = NULL,
	@DaFare BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

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

		-- Scope: azienda del contesto (senza azienda nessuna riga). @Stato: B = bozze, altrimenti lo stato DIWASS; @Ruolo:
		-- uno dei ruoli dell'azienda (O, P, D, I, T); @DaFare = 1: solo i documenti con un passaggio che spetta all'azienda
		SELECT
			a.Id,
			StatoValore = CASE
				WHEN a.Stato IS NULL OR a.DaInviare = 1 THEN 1
				WHEN a.Stato IN ('CANCELLED', 'TAKE_BACK') THEN 2
				ELSE 0
			END,
			StatoDescrizione = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato)
				+ IIF(a.DaInviare = 1, ' - modifiche da inviare a DIWASS', ''),
			a.Numero,
			a.Stato,
			StatoNome = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			a.DataSpedizione,
			EerNome = e.Nome,
			a.Descrizione,
			DestinatarioNome = ISNULL(d.NomeCompleto, x.Nome),
			OrganizzatoreNome = ISNULL(so.NomeCompleto, xo.Nome),
			Ricevuto = CAST(ISNULL(a.Ricevuto, 0) AS BIT),
			a.Ruoli,
			RuoliNome = dbo.ufnDiwassAllegatiVii_get_RuoliDescrizione(a.Ruoli),
			v.Trasportatori,
			v.PreseInCarico,
			v.PresaInCaricoData,
			v.RicezioneDestinatarioPrevista,
			v.RicezioneDestinatarioData,
			v.RicezioneImpiantoData,
			v.CompletamentoData,
			v.DaFare,
			v.Scadenza,
			PaeseDestinazione = n.Nome,
			a.Quantita,
			a.UnitaQuantita,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni s ON a.IdAziendaInterna = s.IdAzienda
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti x ON a.Id = x.Id AND x.Ruolo = 'D' AND x.Pos = 1
			LEFT JOIN dbo.tblSedi d ON x.IdSede = d.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti xo ON a.Id = xo.Id AND xo.Ruolo = 'O' AND xo.Pos = 1
			LEFT JOIN dbo.tblSedi so ON xo.IdSede = so.Id
			LEFT JOIN dbo.tblNazioni n ON a.IdNazioneDestinazione = n.Id
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Avanzamento(a.Id) v
		WHERE
			s.Id = @IdSessione
			AND a.Lock = 0
			AND
				(
				@Stato IS NULL
				OR
					(
					@Stato = 'B'
					AND a.Stato IS NULL
					)
				OR a.Stato = @Stato
				)
			AND
				(
				@Search IS NULL
				OR a.Numero LIKE '%' + @Search + '%'
				OR a.Descrizione LIKE '%' + @Search + '%'
				OR e.Nome LIKE '%' + @Search + '%'
				OR ISNULL(d.NomeCompleto, x.Nome) LIKE '%' + @Search + '%'
				OR ISNULL(so.NomeCompleto, xo.Nome) LIKE '%' + @Search + '%'
				)
			AND
				(
				@Ruolo IS NULL
				OR ISNULL(a.Ruoli, 'O') LIKE '%' + @Ruolo + '%'
				)
			AND
				(
				ISNULL(@DaFare, 0) = 0
				OR v.DaFare IS NOT NULL
				)
		ORDER BY a.DataSpedizione DESC, a.Id DESC
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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
