CREATE   PROCEDURE [dbo].[uspOggetti_get]
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
            @IdFunzione = 'APC',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @idUtente  CHAR(16);
        DECLARE @idAzienda CHAR(16);

        SELECT @idUtente  = IdUtente,
               @idAzienda = IdAzienda
        FROM   dbo.tblSessioni
        WHERE  Id = @IdSessione;

        -- Titolarità: l'oggetto è visibile se appartiene a un'azienda interna dell'utente
        -- OPPURE se è condiviso da un'altra azienda tramite Area comune (vedi Ramo 2 di
        -- uspOggetti_get_List, che già lista questi oggetti condivisi). Prima di questa
        -- seconda condizione, un oggetto visibile in lista dava "Non si dispone dei
        -- diritti necessari" se aperto da un utente di un'azienda diversa da quella
        -- proprietaria. La sola lettura è permessa qui; la modifica resta bloccata da
        -- uspOggetti_upd (che confronta IdSede con l'azienda specifica della sessione).
        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblOggetti o
                   INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@idUtente) i
                       ON o.IdSede = i.Id
            WHERE  o.Id = @Id
        )
        AND NOT EXISTS (
            SELECT 1
            FROM   dbo.ufnOggetti_get_CondivisiByUtente_List(@idUtente) c
            WHERE  c.Id = @Id
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblOggetti WHERE Id = @Id AND Lock <= 2)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Oggetto non trovato';
            GOTO BRANCH_END;
        END

        SELECT
            p.Id,
            p.IdSede,
            Nome               = ISNULL(p.Nome, ''),
            Codice             = ISNULL(p.Codice, ''),
            Descrizione        = ISNULL(p.Descrizione, ''),
            IdUnitaMisura      = ISNULL(p.IdUnitaMisura, 'NR'),
            ImpiegabileServizi = ISNULL(p.ImpiegabileServizi, 0),
            IdTipo             = ISNULL(p.IdTipo, 'AA'),
            Disabilitata       = CAST(ISNULL(p.Disabilitata, 0) AS BIT),
            Condivisa          = CAST(IIF(c.Id IS NULL, 0, 1) AS BIT),
            CondivisaDaArea    = ISNULL(c.Area, ''),
            CondivisaDaAltri   = CAST(IIF(@idAzienda = p.IdSede, 0, 1) AS BIT),
            p.Lock
        FROM
            dbo.tblOggetti p
            OUTER APPLY (
                SELECT TOP 1
                    ae.Id,
                    Area = a.Nome
                FROM   dbo.tblAreeOsepe ae
                       INNER JOIN dbo.tblAree a ON ae.Id = a.Id
                WHERE  a.Lock     = 0
                  AND  ae.IdOsepe = p.Id
            ) c
        WHERE
            p.Id = @Id
			AND p.Lock <= 2;

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
