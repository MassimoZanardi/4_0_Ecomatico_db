CREATE   PROCEDURE [dbo].[uspEtichette_get]
    @Id         CHAR(16) = NULL,
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)),         '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
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
            @IdFunzione = 'ETC',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblEtichette e
                   INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON e.IdSede = i.Id
            WHERE  e.Id = @Id
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @idModulo CHAR(3);
        SELECT @idModulo = IdModulo FROM dbo.tblEtichette WHERE Id = @Id;

        IF dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione) = 0
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblEtichette WHERE Id = @Id AND Lock <= 2)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Etichetta non trovata';
            GOTO BRANCH_END;
        END

        SELECT
            e.Id,
            e.IdSede,
            e.IdModulo,
            e.IdColore,
            Nome        = ISNULL(e.Nome, ''),
            Descrizione = ISNULL(e.Descrizione, ''),
            e.Visualizzazione,
            ColoreCss   = c.Css,
            ColoreHex   = c.Hex,
            e.Lock
        FROM
            dbo.tblEtichette e
            LEFT JOIN dbo.tblColori c ON e.IdColore = c.Id
        WHERE
            e.Id = @Id;

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
