CREATE   PROCEDURE [dbo].[uspTipi_get]
    @Id         CHAR(16) = NULL,
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;
        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)), '');
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
            @IdFunzione = 'TPO',
            @Permesso   = @permesso OUTPUT;
        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END
        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblTipi c
                   INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
                       ON c.IdSede = i.Id
            WHERE  c.Id = @Id
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END
        DECLARE @idModulo CHAR(3);
        SELECT @idModulo = IdModulo FROM dbo.tblTipi WHERE Id = @Id;
        IF dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione) = 0
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END
        IF NOT EXISTS (SELECT 1 FROM dbo.tblTipi WHERE Id = @Id AND Lock <= 2)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Tipo non trovato';
            GOTO BRANCH_END;
        END
        SELECT
            Id,
            IdSede,
            IdModulo,
            Nome        = ISNULL(Nome, ''),
            Descrizione = ISNULL(Descrizione, ''),
            Lock
        FROM   dbo.tblTipi
        WHERE  Id = @Id AND Lock <= 2;
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
