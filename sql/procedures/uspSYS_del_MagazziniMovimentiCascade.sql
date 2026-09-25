SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_MagazziniMovimentiCascade
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Conferma = dbo.ufnStringhe_get_SenzaSpazi(@Conferma, 0, 1);

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Variante di uspSYS_del_MagazziniCascade che cancella solo i dati di movimentazione
        -- (Movimenti/Righe/RigheEoW/ripartizioni sui lotti/Ddt) e mantiene l'anagrafica
        -- (Articoli/Lotti): i Lotti non memorizzano quantità derivate dai movimenti (la
        -- giacenza è sempre calcolata), quindi restano coerenti. Lookup del modulo e Lotti EoW
        -- non toccati.
        SELECT Id INTO #tm FROM dbo.tblMagazziniMovimenti;
        SELECT Id INTO #td FROM dbo.tblMagazziniDdt;
        SELECT Id INTO #tr FROM dbo.tblMagazziniMovimentiRighe;
        SELECT Id INTO #te FROM dbo.tblMagazziniMovimentiRigheEoW;

        BEGIN TRANSACTION;
            -- Ripartizioni riga->lotto (FK NO_ACTION su Righe/RigheEoW): vanno svuotate prima
            -- delle Righe/RigheEoW; condividono l'Id della riga, nessun Id proprio in tblId.
            DELETE dbo.tblMagazziniMovimentiRigheLotti;
            DELETE dbo.tblMagazziniMovimentiRigheEoWLotti;

            -- DDT: FK NO_ACTION su IdMovimento - va rimosso prima del Movimento.
            DELETE dbo.tblMagazziniDdt;

            -- Righe tradizionali ed EoW: FK NO_ACTION su IdMovimento.
            DELETE dbo.tblMagazziniMovimentiRighe;
            DELETE dbo.tblMagazziniMovimentiRigheEoW;

            DELETE dbo.tblMagazziniMovimenti;

            DELETE dbo.tblIdCancellati
            WHERE Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #td)
               OR Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #te);
            DELETE dbo.tblIdLog
            WHERE Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #td)
               OR Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #te);
            DELETE dbo.tblId
            WHERE Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #td)
               OR Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #te);
        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #tm),
            ', Righe rimosse: ', (SELECT COUNT(*) FROM #tr) + (SELECT COUNT(*) FROM #te),
            ', Ddt rimossi: ', (SELECT COUNT(*) FROM #td),
            '. Articoli e Lotti mantenuti.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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
GO
