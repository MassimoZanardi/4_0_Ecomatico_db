-- =====================================================================================
-- Deploy produzione 2026-09-04 (parte 2): Firma remota xFIR chiavata per operatore
-- Repo: 4_0_ecomatico
--
-- Contesto: la credenziale di firma remota RENTRI e' 1:1 con l'operatore (azienda/CF), non
-- con la sede - un utente che opera su piu' AziendeInterne (o un'associazione di categoria
-- con delega su piu' aziende) ha bisogno di una credenziale distinta per ciascuna. La prima
-- versione del modulo (deploy del 2026-09-04 precedente) chiavava invece solo per utente.
--
-- Contenuto:
--   1) Rebuild tblRentriFirmeCredenziali: chiave (IdUtente, IdCredenziale) invece di solo
--      IdUtente, con FK a tblRentriCredenziali. ATTENZIONE: svuota la tabella - conteneva
--      solo le righe di test del 2026-09-04, da ricollegare dopo il deploy.
--   2) CREATE OR ALTER uspRentriRegistri_get_IdCredenziale (nuova: risolve l'operatore/
--      Credenziale primaria a partire da un registro)
--   3) CREATE OR ALTER uspRentriFirmeCredenziali_get / _upd_Boarding / _del (estese con
--      @IdCredenziale)
--
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -b -i <questo file>
-- =====================================================================================


-- 1) Rebuild tblRentriFirmeCredenziali ------------------------------------------------
DELETE FROM dbo.tblRentriFirmeCredenziali;
GO

DROP TABLE dbo.tblRentriFirmeCredenziali;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriFirmeCredenziali](
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCredenziale] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[CredentialsId] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DeviceIdentifier] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataBoarding] [datetime2](0) NULL,
	[Lock] [tinyint] NULL
 CONSTRAINT [PK_tblRentriFirmeCredenziali] PRIMARY KEY CLUSTERED
(
	[IdUtente] ASC,
	[IdCredenziale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeCredenziali_tblUtenti] FOREIGN KEY([IdUtente])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali] CHECK CONSTRAINT [FK_tblRentriFirmeCredenziali_tblUtenti]
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeCredenziali_tblRentriCredenziali] FOREIGN KEY([IdCredenziale])
REFERENCES [dbo].[tblRentriCredenziali] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali] CHECK CONSTRAINT [FK_tblRentriFirmeCredenziali_tblRentriCredenziali]
GO


-- 2) uspRentriRegistri_get_IdCredenziale ----------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get_IdCredenziale]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdSede CHAR(16);
		SELECT @IdSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdCredenziale CHAR(16);
		SELECT @IdCredenziale = IdCredenziale
		FROM dbo.tblRentriCredenzialiSedi
		WHERE IdSede = @IdSede AND Pos = 0;

		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
			GOTO BRANCH_END;
		END

		SELECT rtn = @IdCredenziale;

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


-- 3a) uspRentriFirmeCredenziali_get ----------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_get]
	@IdSessione CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = rc.IdDominio
			WHERE rc.Id = @IdCredenziale AND u.Id = @idUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			u.Id AS IdUtente,
			u.CodiceFiscale,
			u.Nome,
			u.Cognome,
			CredentialsId = CASE WHEN c.Lock = 0 THEN c.CredentialsId ELSE NULL END,
			c.DeviceIdentifier,
			DataBoarding = CASE WHEN c.Lock = 0 THEN c.DataBoarding ELSE NULL END,
			Collegata = CASE WHEN c.IdUtente IS NOT NULL AND c.Lock = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblRentriFirmeCredenziali c ON c.IdUtente = u.Id AND c.IdCredenziale = @IdCredenziale
		WHERE u.Id = @idUtente;

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


-- 3b) uspRentriFirmeCredenziali_upd_Boarding -------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_upd_Boarding]
	@IdSessione CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@CredentialsId VARCHAR(50) = NULL,
	@DeviceIdentifier VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');
		SET @CredentialsId = NULLIF(LTRIM(RTRIM(@CredentialsId)), '');
		SET @DeviceIdentifier = NULLIF(LTRIM(RTRIM(@DeviceIdentifier)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @CredentialsId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @CredentialsId non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = rc.IdDominio
			WHERE rc.Id = @IdCredenziale AND u.Id = @idUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblUtenti
			WHERE
				Id = @idUtente
				AND CodiceFiscale IS NOT NULL
				AND Nome IS NOT NULL
				AND Cognome IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impostare Codice Fiscale, Nome e Cognome prima di collegare la credenziale di firma';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF EXISTS (SELECT 1 FROM dbo.tblRentriFirmeCredenziali WHERE IdUtente = @idUtente AND IdCredenziale = @IdCredenziale)
			BEGIN
				UPDATE dbo.tblRentriFirmeCredenziali
				SET
					CredentialsId = @CredentialsId,
					DeviceIdentifier = @DeviceIdentifier,
					DataBoarding = SYSDATETIME(),
					Lock = 0
				WHERE IdUtente = @idUtente AND IdCredenziale = @IdCredenziale;
			END
			ELSE
			BEGIN
				INSERT dbo.tblRentriFirmeCredenziali (IdUtente, IdCredenziale, CredentialsId, DeviceIdentifier, DataBoarding, Lock)
				VALUES (@idUtente, @IdCredenziale, @CredentialsId, @DeviceIdentifier, SYSDATETIME(), 0);
			END
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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


-- 3c) uspRentriFirmeCredenziali_del -----------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_del]
	@IdSessione CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = rc.IdDominio
			WHERE rc.Id = @IdCredenziale AND u.Id = @idUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRentriFirmeCredenziali
		SET
			Lock = 4,
			CredentialsId = NULL
		WHERE
			IdUtente = @idUtente
			AND IdCredenziale = @IdCredenziale
			AND Lock = 0;

		SELECT ReturnValue = @returnValue;

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
