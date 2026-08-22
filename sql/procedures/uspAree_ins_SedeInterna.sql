CREATE   PROCEDURE [dbo].[uspAree_ins_SedeInterna]
    @Id         CHAR(16) = NULL,
    @IdSede     CHAR(16) = NULL,
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)), '');
        SET @IdSede     = NULLIF(LTRIM(RTRIM(@IdSede)), '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
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
            @IdFunzione = 'ARE',
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Dominio della sessione: l'Area deve appartenere al tenant del chiamante
        DECLARE @idDominio CHAR(16);
        SELECT @idDominio = IdDominio FROM dbo.tblSessioni WHERE Id = @IdSessione;

        IF NOT EXISTS (SELECT 1 FROM dbo.tblAree WHERE Id = @Id AND IdDominio = @idDominio)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Area non trovata';
            GOTO BRANCH_END;
        END

        -- Titolarità: prima non c'era alcuna verifica che @IdSede appartenesse
        -- allo stesso Dominio dell'Area — un'azienda poteva collegare la SedeInterna
        -- di un'altra azienda (di un altro Dominio/tenant, o anche solo un'altra
        -- azienda interna non prevista) alla propria Area, iniettando visibilità
        -- indesiderata nelle condivisioni viste da quella SedeInterna (vedi
        -- ufnSedi_get_AziendeEsterneCondiviseByUtente_List, che parte dalle sedi
        -- interne del chiamante per risolvere le condivisioni).
        IF NOT EXISTS (SELECT 1 FROM dbo.tblSediInterne WHERE Id = @IdSede AND IdDominio = @idDominio)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        BEGIN TRANSACTION;
            -- Upsert: DELETE + INSERT per evitare duplicati su PK (Id, IdSede)
            DELETE dbo.tblAreeSediInterne
            WHERE  Id     = @Id
              AND  IdSede = @IdSede;

            INSERT INTO dbo.tblAreeSediInterne (Id, IdSede)
            VALUES (@Id, @IdSede);
        COMMIT TRANSACTION;

        -- Log FUORI dalla transazione: uspId_upd gestisce la propria transazione
        EXEC dbo.uspId_upd
            @Id         = @Id,
            @IdSessione = @IdSessione,
            @Operazione = 'U';

        SELECT @returnValue AS ReturnValue;

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
