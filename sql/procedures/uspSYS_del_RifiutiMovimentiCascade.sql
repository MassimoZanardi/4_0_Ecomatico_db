CREATE OR ALTER PROCEDURE dbo.uspSYS_del_RifiutiMovimentiCascade
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

        SELECT Id INTO #tm FROM dbo.tblRifiutiMovimenti;
        SELECT Id INTO #tr FROM dbo.tblRifiutiRegistrazioni;
        SELECT Id INTO #tf FROM dbo.tblRifiutiFormulari;

        BEGIN TRANSACTION;
            DELETE dbo.tblRifiutiRegistrazioniRelazioni  WHERE Id       IN (SELECT Id FROM #tr) OR IdParent IN (SELECT Id FROM #tr);
            DELETE dbo.tblRifiutiMovimentiClassiPericolo WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiTrasportatori  WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiDestinatari    WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiIntermediari   WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiProduttori     WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiFormulariEtichette      WHERE Id       IN (SELECT Id FROM #tf);
            -- Mancanti nell'originale uspRifiutiMovimenti_del_All: sono dettagli 1:1 a chiave
            -- condivisa (Id NOT NULL) di tblRifiutiFormulari, quindi bloccano la DELETE successiva
            -- su tblRifiutiFormulari con un errore FK se anche una sola riga esiste.
            DELETE dbo.tblRifiutiFormulariTrasportiFerroviari WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiFormulariTrasportiMarittimi  WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiFormulariTrasportiTerresti   WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiRegistrazioniEtichette  WHERE Id       IN (SELECT Id FROM #tr);
            -- Gestione EoW: nessun registro viene cancellato da questa SP, solo movimenti/
            -- registrazioni/formulari - tblEoWMaterialiRegistri resta quindi intatto (i suoi
            -- IdRegistro restano validi). tblEoWMovimenti.IdRegistrazione è invece nullable e
            -- referenzia le Registrazioni che stanno per essere cancellate: si azzera il
            -- collegamento anziché cancellare il movimento, che resta un record di magazzino
            -- valido anche senza la registrazione di origine.
            UPDATE dbo.tblEoWMovimenti SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #tr);
            DELETE dbo.tblRifiutiFormulari;
            DELETE dbo.tblRifiutiRegistrazioni;
            DELETE dbo.tblRifiutiMovimentiLog;
            DELETE dbo.tblRifiutiMovimenti;
            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #tm),
            ', Registrazioni rimosse: ', (SELECT COUNT(*) FROM #tr),
            ', Formulari rimossi: ', (SELECT COUNT(*) FROM #tf), '.');

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
