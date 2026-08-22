CREATE   PROCEDURE [dbo].[uspServizi_del_All]
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale
        IF ISNULL(@Conferma, '') <> 'conferma'
            GOTO BRANCH_END;

        -- Cattura gli Id FUORI dalla transazione (sono letture)
        SELECT IdEvento AS Id INTO #tEventi FROM dbo.tblServizi;
        SELECT Id       INTO #tId    FROM dbo.tblServizi;

        -- Legge le firme FUORI dalla transazione
        SELECT IdFirma INTO #tFirme
        FROM   dbo.tblEventiFirme
        WHERE  Id IN (SELECT Id FROM #tEventi);

        BEGIN TRANSACTION;

            -- Figlie di tblEventi (FK dirette) → prima di tblEventi
            DELETE dbo.tblEventiUtenti        WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblRicorrenzeEccezioni WHERE IdEvento IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblRicorrenze          WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblEventiProprieta     WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblEventiFirme         WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblEventiEtichette     WHERE Id       IN (SELECT Id FROM #tEventi);

            -- Servizi e Osepe associati
            DELETE dbo.tblServiziOsepe;
            DELETE dbo.tblServizi;

            -- Firme (dopo aver eliminato tblEventiFirme che le referenzia)
            DELETE dbo.tblFirme               WHERE Id       IN (SELECT IdFirma FROM #tFirme);

            -- Evento
            DELETE dbo.tblEventi              WHERE Id       IN (SELECT Id FROM #tEventi);

            -- Pulizia log e Id
            DELETE dbo.tblIdCancellati        WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblIdCancellati        WHERE Id       IN (SELECT Id FROM #tId);
            DELETE dbo.tblIdLog               WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblIdLog               WHERE Id       IN (SELECT Id FROM #tId);
            DELETE dbo.tblId                  WHERE Id       IN (SELECT Id FROM #tEventi);
            DELETE dbo.tblId                  WHERE Id       IN (SELECT Id FROM #tId);

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        THROW;  -- propaga l'eccezione originale: C# la logga come SqlException inattesa
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;

END;
