CREATE   PROCEDURE [dbo].[uspUtenti_get_List]
    @PageNumber  INT         = 1,
    @RowsPerPage INT         = 50,
    @IdSessione  CHAR(16) = NULL,
    @Email       VARCHAR(50) = NULL,
    @Ruolo       VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
        SET @Email      = dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1);
        SET @Ruolo      = dbo.ufnStringhe_get_SenzaSpazi(@Ruolo, 0, 1);

        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue   = -1;
            SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Valori di default difensivi
        IF @PageNumber  < 1 SET @PageNumber  = 1;
        IF @RowsPerPage < 1 SET @RowsPerPage = 50;

        -- Controllo permesso sulla funzione
        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'UTE',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue   = -1;
            SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

        -- Titolarità: elenco scoperto tramite il Dominio corrente della sessione
        -- (join su tblSessioni.IdDominio). Il cambio di dominio operativo è riservato
        -- agli Admin di Dominio Master tramite un percorso separato e già protetto.
        SELECT
            u.Id,
            StatoValore = CASE
                WHEN u.IdStato  = 'SO'      THEN 1
                WHEN u.Scadenza < GETDATE() THEN 2
                ELSE 0
            END,
            StatoDescrizione = CASE
                WHEN u.IdStato  = 'SO'      THEN 'Utente sospeso'
                WHEN u.Scadenza < GETDATE() THEN 'Utente scaduto'
                ELSE 'OK'
            END,
            u.Email,
            Ruolo  = r.Nome,
            Stato  = st.Nome,
            u.Scadenza,
            UltimoAccesso = IIF(ul.[Data] IS NULL,
                                'Nessuno',
                                FORMAT(ul.[Data], 'dd/MM/yyyy HH:mm')),
            RowsCount = COUNT(*) OVER ()
        FROM
            dbo.tblUtenti    u
            INNER JOIN dbo.tblSessioni s  ON u.IdDominio = s.IdDominio
            INNER JOIN dbo.tblUtentiRuoli    r  ON u.IdRuolo   = r.Id
            INNER JOIN dbo.tblUtentiStati    st ON u.IdStato   = st.Id
            OUTER APPLY (
                SELECT TOP 1 l.[Data]
                FROM   dbo.tblUtentiLogin l
                WHERE  l.Id = u.Id
                ORDER BY l.[Data] DESC
            ) ul
        WHERE
            u.Lock     = 0
            AND u.[Master] = 0
            AND s.Id       = @IdSessione
            AND (@Email IS NULL OR u.Email LIKE '%' + @Email + '%')
            AND (@Ruolo IS NULL OR r.Nome  LIKE '%' + @Ruolo + '%')
        ORDER BY u.Email
        OFFSET @Offset ROWS
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
