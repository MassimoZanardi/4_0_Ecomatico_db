CREATE   PROCEDURE [dbo].[uspAree_get_List]
    @PageNumber  INT         = 1,
    @RowsPerPage INT         = 50,
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

        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'ARE',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @idDominio CHAR(16);
        SELECT @idDominio = IdDominio
        FROM   dbo.tblSessioni
        WHERE  Id = @IdSessione;

        IF @idDominio IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Sessione non valida o scaduta';
            GOTO BRANCH_END;
        END

        -- Normalizza parametri opzionali: collassa spazi multipli interni, trim, NULL se vuoto
        SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

        DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

        SELECT
            Id               = a.Id,
            StatoValore      = 0,
            StatoDescrizione = N'OK',
            Nome             = a.Nome,
            Descrizione      = a.Descrizione,
            RowsCount        = COUNT(*) OVER ()
        FROM
            dbo.tblAree a
        WHERE
            a.IdDominio = @idDominio
            AND a.Lock      = 0
            AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%')
        ORDER BY
            a.Nome
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
        THROW 50001, @returnMessage, 1
    END

END;
