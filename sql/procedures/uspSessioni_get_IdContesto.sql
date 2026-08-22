CREATE   PROCEDURE [dbo].[uspSessioni_get_IdContesto]
    @Id       CHAR(16) = NULL,
    @Contesto INT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Restituisce l'Id del contesto richiesto dalla sessione
        -- 0=Dominio, 1=Azienda, 2=Sede, 3=Registro, 4=Magazzino, 5=Calendario
        SELECT
            IdContesto = ISNULL(CASE @Contesto
                WHEN 0 THEN IdDominio
                WHEN 1 THEN IdAzienda
                WHEN 2 THEN IdSede
                WHEN 3 THEN IdRegistro
                WHEN 4 THEN IdMagazzino
                WHEN 5 THEN IdCalendario
            END, REPLICATE('0', 16))
        FROM dbo.tblSessioni
        WHERE Id = @Id;

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
