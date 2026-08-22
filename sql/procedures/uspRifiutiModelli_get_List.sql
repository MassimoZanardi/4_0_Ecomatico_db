CREATE   PROCEDURE [dbo].[uspRifiutiModelli_get_List]
	@PageNumber  INT      = 1,
	@RowsPerPage INT      = 50,
	@IdSessione  CHAR(16) = NULL,
	@Search      VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue   INT           = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Formattazione parametri
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		-- Validazione paginazione: evita OFFSET/FETCH con valori non validi
		IF ISNULL(@PageNumber, 0)  < 1 SET @PageNumber  = 1;
		IF ISNULL(@RowsPerPage, 0) < 1 SET @RowsPerPage = 50;

		-- Conteggio totale righe (indipendente dalla pagina richiesta, così non si perde
		-- se @PageNumber è oltre l'ultima pagina disponibile)
		DECLARE @RowsCount INT;

		-- viewRifiutiModelli espansa nelle tabelle base per predicate pushdown
		SELECT @RowsCount = COUNT(*)
		FROM
			dbo.tblRifiutiModelli m
			INNER JOIN dbo.tblSessioni             ses ON m.IdRegistro    = ses.IdRegistro
			LEFT  JOIN dbo.tblRifiutiOperazioni    o   ON m.IdOperazione  = o.Id
			LEFT  JOIN dbo.tblRifiutiEer           e   ON m.IdEer         = e.Id
			LEFT  JOIN dbo.tblRifiutiStatiFisici   s   ON m.IdStatoFisico = s.Id
		WHERE
			ses.Id = @IdSessione
			AND m.Lock = 0
			AND (@Search IS NULL OR m.Nome LIKE '%' + @Search + '%')
		OPTION (RECOMPILE);

		SELECT
			RowsCount        = @RowsCount,
			m.Id,
			StatoValore      = 0,
			StatoDescrizione = 'OK',
			m.Nome,
			OperazioneNome    = o.Nome,
			EerNome           = e.Nome,
			EerDescrizione    = e.Descrizione,
			StatoFisicoCodice = s.Codice,
			StatoFisicoNome   = s.Nome,
			m.Etichette
		FROM
			dbo.tblRifiutiModelli m
			INNER JOIN dbo.tblSessioni             ses ON m.IdRegistro    = ses.IdRegistro
			LEFT  JOIN dbo.tblRifiutiOperazioni    o   ON m.IdOperazione  = o.Id
			LEFT  JOIN dbo.tblRifiutiEer           e   ON m.IdEer         = e.Id
			LEFT  JOIN dbo.tblRifiutiStatiFisici   s   ON m.IdStatoFisico = s.Id
		WHERE
			ses.Id = @IdSessione
			AND m.Lock = 0
			AND (@Search IS NULL OR m.Nome LIKE '%' + @Search + '%')
		ORDER BY m.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS FETCH NEXT @RowsPerPage ROWS ONLY
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