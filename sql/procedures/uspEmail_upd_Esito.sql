SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): esito dell'invio di un'email presa da uspEmail_upd_Prendi (stato P).
-- @Inviata = 1: inviata (I).
-- @Inviata = 0: il posto nella quota torna libero (tblEmailConsumi del giorno in cui e' stata contata); con @Riprova = 1
-- (servizio di invio non raggiungibile, troppe richieste, errore interno) torna da inviare (D) e si riprova dopo 5, 10,
-- 20 e 40 minuti; al quinto tentativo, o con @Riprova = 0 (indirizzo rifiutato), non inviata (E). @Errore va nella Nota.
-- @Rilascia = 1 (il giro si e' fermato prima di inviarla: tempo finito o servizio di invio non disponibile): torna da
-- inviare (D) per il giro successivo, senza contare un tentativo e liberando il posto nella quota; ProssimoTentativo
-- resta quello di prima (gia' passato), cosi' l'attesa in Email usate (uspEmail_get_Consumi) continua a crescere.
-- Un'email che non e' piu' in invio (gia' chiusa da un altro giro) resta com'e'.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_upd_Esito]
	@Id CHAR(16) = NULL,
	@Inviata BIT = 0,
	@Riprova BIT = 0,
	@Rilascia BIT = 0,
	@Errore NVARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Errore = NULLIF(LTRIM(RTRIM(@Errore)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			IF @Inviata = 1
			BEGIN
				UPDATE dbo.tblEmail
				SET
					IdStato = 'I',
					Invio = GETDATE(),
					Tentativi = Tentativi + 1,
					Nota = NULL
				WHERE
					Id = @Id
					AND IdStato = 'P';
			END
			ELSE
			BEGIN
				UPDATE c
				SET Numero = c.Numero - 1
				FROM
					dbo.tblEmailConsumi c
					INNER JOIN dbo.tblEmail e ON c.IdDominio = e.IdDominio
											  AND c.Giorno = e.QuotaGiorno
				WHERE
					e.Id = @Id
					AND e.IdStato = 'P'
					AND c.Numero > 0;

				IF @Rilascia = 1
					UPDATE dbo.tblEmail
					SET
						IdStato = 'D',
						Presa = NULL,
						QuotaGiorno = NULL,
						Nota = N'In attesa: rimandata al giro successivo'
					WHERE
						Id = @Id
						AND IdStato = 'P';
				ELSE
					UPDATE dbo.tblEmail
					SET
						IdStato = IIF(@Riprova = 1 AND Tentativi + 1 < 5, 'D', 'E'),
						ProssimoTentativo = DATEADD(MINUTE, 5 * POWER(2, Tentativi), GETDATE()),
						Tentativi = Tentativi + 1,
						QuotaGiorno = NULL,
						Nota = ISNULL(@Errore, N'Invio non riuscito')
					WHERE
						Id = @Id
						AND IdStato = 'P';
			END

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
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
GO
