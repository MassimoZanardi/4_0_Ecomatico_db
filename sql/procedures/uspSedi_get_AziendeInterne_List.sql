CREATE   PROCEDURE [dbo].[uspSedi_get_AziendeInterne_List]
    @PageNumber    INT         = 1,
    @RowsPerPage   INT         = 50,
    @IdSessione    CHAR(16) = NULL,
    @Nome          VARCHAR(50) = NULL,
    @Indirizzo     VARCHAR(50) = NULL,
    @CodiceFiscale VARCHAR(50) = NULL,
    @Note          VARCHAR(50) = NULL
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
            @IdFunzione = 'AZI',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        SET @Nome          = dbo.ufnStringhe_get_SenzaSpazi(@Nome,          0, 1);
        SET @Indirizzo     = dbo.ufnStringhe_get_SenzaSpazi(@Indirizzo,     0, 1);
        SET @CodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1);
        SET @Note          = dbo.ufnStringhe_get_SenzaSpazi(@Note,          0, 1);

        DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

        SELECT
            s.Id,
            StatoValore      = 0,
            StatoDescrizione = CAST('OK' AS VARCHAR(50)),
            s.NomeCompleto,
            s.IndirizzoCompleto,
            s.CodiceFiscale,
            s.PartitaIva,
            RowsCount        = COUNT(*) OVER ()
        FROM
            dbo.tblSedi          s
            INNER JOIN dbo.tblSediInterne   i   ON s.Id           = i.Id
            INNER JOIN dbo.tblSessioni      e   ON i.IdDominio    = e.IdDominio
            INNER JOIN dbo.tblUtenti        u   ON e.IdUtente     = u.Id
            LEFT  JOIN dbo.tblSediIndirizzi si  ON s.Id           = si.Id
            LEFT  JOIN dbo.tblIndirizzi     ind ON si.IdIndirizzo = ind.Id
        WHERE
            e.Id           = @IdSessione
            AND u.IdRuolo  = 'AD'
            AND s.IdParent IS NULL
            AND s.Lock     = 0
            AND (@Nome          IS NULL OR s.NomeCompleto      LIKE '%' + @Nome          + '%')
            AND (@Indirizzo     IS NULL OR s.IndirizzoCompleto LIKE '%' + @Indirizzo     + '%')
            AND (@CodiceFiscale IS NULL OR s.CodiceFiscale     LIKE '%' + @CodiceFiscale + '%')
            AND (@Note          IS NULL OR s.Note              LIKE '%' + @Note          + '%')
        ORDER BY s.NomeCompleto
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
