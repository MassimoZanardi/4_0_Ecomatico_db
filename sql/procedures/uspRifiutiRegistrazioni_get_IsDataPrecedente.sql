CREATE   PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_IsDataPrecedente]
    @IdRegistro        CHAR(16) = NULL,
    @RegistrazioneData DATE     = NULL,
    @IdSessione        CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @IdRegistro IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @RegistrazioneData IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @RegistrazioneData non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'RRG',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (
            SELECT 1
            FROM
                dbo.tblRifiutiRegistri g
                INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
            WHERE
                g.Id = @IdRegistro
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        SELECT rtn = CAST(
            IIF(EXISTS (
                SELECT 1
                FROM   dbo.tblRifiutiRegistrazioni r
                       INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
                WHERE  m.IdRegistro = @IdRegistro
                  AND  r.[Data]     > @RegistrazioneData
                  AND  r.Lock       < 2
            ), 1, 0)
        AS BIT);

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1
    END

END;
