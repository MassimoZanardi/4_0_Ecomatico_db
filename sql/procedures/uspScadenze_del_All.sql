CREATE   PROCEDURE [dbo].[uspScadenze_del_All]
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale
        IF ISNULL(@Conferma, '') <> 'conferma'
            GOTO BRANCH_END;

        -- Cattura gli Id FUORI dalla transazione (sono letture)
        SELECT IdEvento AS Id INTO #tEventi FROM dbo.tblScadenze;
        SELECT Id       INTO #tId    FROM dbo.tblScadenze;

        BEGIN TRANSACTION;

            -- Figlie di tblEventi via Id (FK dirette) → prima di tblEventi
            DELETE dbo.tblEventiProprieta      WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblRicorrenzeEccezioni  WHERE IdEvento IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblEventiEtichette      WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblRicorrenze           WHERE Id       IN (SELECT Id FROM #tEventi);

            -- Servizi associati agli eventi scadenza
            DELETE dbo.tblServiziOsepe         WHERE Id IN (
                SELECT Id FROM dbo.tblServizi WHERE IdEvento IN (SELECT Id FROM #tEventi));
            DELETE dbo.tblServizi              WHERE IdEvento IN (SELECT Id FROM #tEventi);

            -- Scadenze e Osepe
            DELETE dbo.tblScadenzeOsepe;
            DELETE dbo.tblScadenze;

            -- Evento
            DELETE dbo.tblEventi               WHERE Id       IN (SELECT Id FROM #tEventi);

            -- Pulizia log e Id
            DELETE dbo.tblIdCancellati         WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblIdCancellati         WHERE Id       IN (SELECT Id FROM #tId);
            DELETE dbo.tblIdLog                WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblIdLog                WHERE Id       IN (SELECT Id FROM #tId);
            DELETE dbo.tblId                   WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblId                   WHERE Id       IN (SELECT Id FROM #tId);

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        THROW;  -- propaga l'eccezione originale: C# la logga come SqlException inattesa
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;

END;
