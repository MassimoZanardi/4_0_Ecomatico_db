SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_upd_Stato]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
-- Servizi > Assegnati, vista Bacheca (S7.6): pulsante Inizia, il servizio da eseguire passa a In esecuzione. Solo
-- questo passaggio: concludere (Eseguito) richiede la scheda, con le proprieta' e la firma, e tornare indietro si fa
-- dalla scheda. Stessi controlli di uspServiziAssegnati_upd: permesso di modifica su SRV o SRA, servizio di un
-- calendario di una sede accessibile e assegnato all'utente della sessione (S7.3). In Servizi > Assegnati ci sono solo
-- servizi singoli e occorrenze modificate, quindi si cambia sempre un solo evento
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @idEvento CHAR(16);
		DECLARE @idStato CHAR(1);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Servizio di un calendario accessibile e assegnato all'utente della sessione
		SELECT
			@idEvento = e.Id,
			@idStato = e.IdStato
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			INNER JOIN dbo.tblEventiUtenti u ON e.Id = u.Id
			INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente AND ss.Id = @IdSessione
		WHERE
			s.Id = @Id
			AND e.Lock = 0;

		IF @idEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @idStato <> 'D'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si inizia solo un servizio da eseguire: aggiornare la pagina';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblEventi
		SET IdStato = 'I'
		WHERE
			Id = @idEvento
			AND IdStato = 'D'
			AND Lock = 0;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si inizia solo un servizio da eseguire: aggiornare la pagina';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
