SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Scollega BIT = 0,
	@Identificativo VARCHAR(20) = NULL,
	@BloccoFormulari VARCHAR(10) = NULL,
	@DataInizioInvio DATE = NULL,
	@ConservazioneSostitutiva BIT = 0,
	@ConservazioneSostitutivaRagioneSociale VARCHAR(50) = NULL,
	@ConservazioneSostitutivaPartitaIva VARCHAR(20) = NULL,
	@ConservazioneSostitutivaEmail VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Scollega = ISNULL(@Scollega, 0);
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));
		SET @BloccoFormulari = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@BloccoFormulari, 0, 1));
		SET @ConservazioneSostitutiva = ISNULL(@ConservazioneSostitutiva, 0);
		SET @ConservazioneSostitutivaRagioneSociale = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneSostitutivaRagioneSociale, 0, 1);
		SET @ConservazioneSostitutivaPartitaIva = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneSostitutivaPartitaIva, 0, 1);
		SET @ConservazioneSostitutivaEmail = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneSostitutivaEmail, 0, 1);

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede del registro
		DECLARE @idSede CHAR(16);
		SELECT @idSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRentri CHAR(16);
		SELECT @idRentri = IdRentri
		FROM dbo.tblRentriRegistri
		WHERE Id = @Id;

		-- Scollegamento esplicito: la conservazione sostitutiva non ha senso su un registro non
		-- collegato a RENTRI, azzerata insieme allo scollegamento (libera anche il posto nel
		-- conteggio ConservazioniMax del Dominio)
		IF @Scollega = 1
		BEGIN
			BEGIN TRANSACTION;
				IF @idRentri IS NOT NULL
				BEGIN
					DELETE dbo.tblRentriRegistri WHERE Id = @Id;
					DELETE [1_0_rentri]..tblRegistri WHERE Id = @idRentri;
				END

				UPDATE dbo.tblRifiutiRegistri
				SET
					ConservazioneSostitutiva = 0,
					ConservazioneSostitutivaRagioneSociale = NULL,
					ConservazioneSostitutivaPartitaIva = NULL,
					ConservazioneSostitutivaEmail = NULL
				WHERE Id = @Id;
			COMMIT TRANSACTION;
			SELECT ReturnValue = @returnValue;
			GOTO BRANCH_END;
		END

		-- Il registro non ha una propria credenziale: eredita sempre la Primaria (Pos=0) della Sede su cui si appoggia
		DECLARE @idRentriSede CHAR(16);
		SELECT @idRentriSede = IdRentri
		FROM dbo.tblRentriCredenzialiSedi
		WHERE
			IdSede = @idSede
			AND Pos = 0;

		IF @idRentriSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista già un altro registro con lo stesso identificativo
		IF @Identificativo IS NOT NULL AND EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriRegistri r
				INNER JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
			WHERE
				r.Id <> @Id
				AND h.Identificativo = @Identificativo
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro registro con lo stesso identificativo è già presente';
			GOTO BRANCH_END;
		END

		-- Limite di registri con conservazione sostitutiva abilitata per Dominio (tblDomini.ConservazioniMax);
		-- @Id escluso dal conteggio: se già abilitata su questo stesso registro non va contata come "nuova"
		IF @ConservazioneSostitutiva = 1
		BEGIN
			DECLARE @idDominio CHAR(16);
			SELECT @idDominio = IdDominio FROM dbo.tblSessioni WHERE Id = @IdSessione;

			IF ISNULL((SELECT ConservazioniMax FROM dbo.tblDomini WHERE Id = @idDominio), 0)
				<=
				(SELECT COUNT(*)
				 FROM
					 dbo.tblRifiutiRegistri r
					 INNER JOIN dbo.tblSediInterne i ON r.IdSede = i.Id
				 WHERE
					 i.IdDominio = @idDominio
					 AND r.ConservazioneSostitutiva = 1
					 AND r.Lock = 0
					 AND r.Id <> @Id
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'È stato raggiunto il numero massimo di registri con conservazione sostitutiva abilitata';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblRegistri (Id, IdSede, Identificativo, BloccoFormulari, DataInizioInvio)
				VALUES (@idRentri, @idRentriSede, @Identificativo, @BloccoFormulari, @DataInizioInvio);

				INSERT INTO dbo.tblRentriRegistri (Id, IdRentri)
				VALUES (@Id, @idRentri);
			END
			ELSE
			BEGIN
				UPDATE [1_0_rentri]..tblRegistri
				SET
					IdSede = @idRentriSede,
					Identificativo = @Identificativo,
					BloccoFormulari = @BloccoFormulari,
					DataInizioInvio = @DataInizioInvio
				WHERE Id = @idRentri;
			END

			UPDATE dbo.tblRifiutiRegistri
			SET
				ConservazioneSostitutiva = @ConservazioneSostitutiva,
				ConservazioneSostitutivaRagioneSociale = @ConservazioneSostitutivaRagioneSociale,
				ConservazioneSostitutivaPartitaIva = @ConservazioneSostitutivaPartitaIva,
				ConservazioneSostitutivaEmail = @ConservazioneSostitutivaEmail
			WHERE Id = @Id;
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
