SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_MagazziniCascade
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

        -- Solo i dati transazionali del modulo (Articoli/Lotti/Movimenti/Righe/Ddt): le
        -- tabelle di lookup (Operazioni, CriteriScarichiLotti, Causali) sono configurazione
        -- del modulo, non dati di gestione, e non vengono toccate.
        SELECT Id INTO #ta FROM dbo.tblMagazziniArticoli;
        SELECT Id INTO #tl FROM dbo.tblMagazziniLotti;
        SELECT Id INTO #tm FROM dbo.tblMagazziniMovimenti;
        SELECT Id INTO #td FROM dbo.tblMagazziniDdt;

        BEGIN TRANSACTION;
            -- Relazioni carico/scarico (FK NO_ACTION su Id/IdParent verso Righe) e ripartizioni
            -- riga EoW->lotto EoW: vanno svuotate prima di cancellare Righe/RigheEoW sottostanti
            DELETE dbo.tblMagazziniMovimentiRigheRelazioni;
            DELETE dbo.tblMagazziniMovimentiRigheEoWLotti;

            -- DDT: FK NO_ACTION su IdMovimento (oltre a IdSede/IdMittente/IdDestinatario/
            -- IdTrasportatore verso tblSedi, non toccate qui) - va rimosso prima delle Righe/Movimenti sottostanti.
            DELETE dbo.tblMagazziniDdt;

            -- Righe tradizionali ed EoW: FK NO_ACTION su IdMovimento (RigheEoW.IdMovimento non
            -- ha FK nello schema reale, ma va comunque rimossa prima del Movimento per pulizia).
            DELETE dbo.tblMagazziniMovimentiRighe;
            DELETE dbo.tblMagazziniMovimentiRigheEoW;

            DELETE dbo.tblMagazziniMovimenti;
            DELETE dbo.tblMagazziniLotti;
            DELETE dbo.tblMagazziniArticoli;

            DELETE dbo.tblIdCancellati
            WHERE Id IN (SELECT Id FROM #ta) OR Id IN (SELECT Id FROM #tl)
               OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #td);
            DELETE dbo.tblIdLog
            WHERE Id IN (SELECT Id FROM #ta) OR Id IN (SELECT Id FROM #tl)
               OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #td);
            DELETE dbo.tblId
            WHERE Id IN (SELECT Id FROM #ta) OR Id IN (SELECT Id FROM #tl)
               OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #td);
        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Articoli rimossi: ', (SELECT COUNT(*) FROM #ta),
            ', Lotti rimossi: ', (SELECT COUNT(*) FROM #tl),
            ', Movimenti rimossi: ', (SELECT COUNT(*) FROM #tm),
            ', Ddt rimossi: ', (SELECT COUNT(*) FROM #td), '.');

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
