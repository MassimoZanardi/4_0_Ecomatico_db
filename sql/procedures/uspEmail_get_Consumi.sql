SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email: quote e consumi del dominio della sessione (ufnEmail_get_Consumi), email da inviare e
-- attesa della piu' vecchia, per la finestra Azioni > Email usate. Funzione EMR, solo amministratori.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_get_Consumi]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			c.GiornoMax,
			c.MeseMax,
			c.Giorno,
			c.Mese,
			-- Email ancora da inviare del dominio, comprese quelle in attesa del giorno o del mese dopo
			DaInviare = (
				SELECT COUNT(*)
				FROM dbo.tblEmail e
				WHERE
					e.IdDominio = u.IdDominio
					AND e.IdStato IN ('D', 'P')),
			-- Minuti da cui aspetta l'email pronta per l'invio piu' vecchia (NULL se nessuna): le email in attesa del
			-- giorno o del mese dopo, o del prossimo tentativo, non sono pronte e non contano. Oltre 30 minuti l'invio e'
			-- in ritardo (operazione pianificata ferma o servizio di invio non disponibile)
			AttesaMinuti = (
				SELECT DATEDIFF(MINUTE, MIN(e.ProssimoTentativo), GETDATE())
				FROM dbo.tblEmail e
				WHERE
					e.IdDominio = u.IdDominio
					AND e.IdStato = 'D'
					AND e.ProssimoTentativo <= GETDATE())
		FROM
			dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			CROSS APPLY dbo.ufnEmail_get_Consumi(u.IdDominio) c
		WHERE s.Id = @IdSessione;

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
GO
