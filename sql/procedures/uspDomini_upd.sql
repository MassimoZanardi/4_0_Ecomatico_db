SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdStato CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Riferimento VARCHAR(50) = NULL,
	@Scadenza DATE = NULL,
	@ScadenzaAuto BIT = 1,
	@UtentiMax INT = 1,
	@AziendeMax INT = 1,
	@SediMax INT = 1,
	@RegistriMax INT = 0,
	@MagazziniMax INT = 0,
	@ServiziMax INT = 0,
	@RentriMax INT = 0,
	@ConservazioniMax INT = 0,
	@ConservazioniXfirMax INT = 0,
	@Demo BIT = 0,
	@Codice CHAR(5) = NULL,
	@NoLogo BIT = 0,
	@Url VARCHAR(200) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @primaAttivazione BIT = 0;
	DECLARE @returnIdUtente CHAR(16) = NULL;
	DECLARE @returnIdSede CHAR(16) = NULL;
	DECLARE @returnIdIndirizzo CHAR(16) = NULL;

	BEGIN TRY

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');

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
		IF @IdStato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStato non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDominiStati
		WHERE Id = @IdStato)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Stato dominio non valido';
			GOTO BRANCH_END;
		END

		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Riferimento = dbo.ufnStringhe_get_SenzaSpazi(@Riferimento, 0, 1);
		SET @Url = dbo.ufnStringhe_get_SenzaSpazi(@Url, 0, 1);
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');

		IF @Nome IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id <> @Id
				AND Nome = @Nome
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non possono esistere 2 domini con lo stesso nome';
			GOTO BRANCH_END;
		END

		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id <> @Id
				AND Codice = @Codice
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non possono esistere 2 domini con lo stesso codice';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @Id
			AND Lock = 2
		)
			SET @primaAttivazione = 1;

		IF @primaAttivazione = 1
		BEGIN
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdUtente OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdSede OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdIndirizzo OUTPUT;
		END

		BEGIN TRANSACTION;

			IF @primaAttivazione = 1
			BEGIN
				INSERT INTO dbo.tblUtenti
					(Id, IdDominio, IdRuolo, IdStato, Email, Scadenza, [Master],
					 PasswordScadenzaGiorni, PasswordLunghezzaMinima,
					 PasswordPrecedenti, Lock)
				VALUES
					(@returnIdUtente, @Id, 'AD', 'AT',
					 RTRIM(@Id) + '@ecomatico.it',
					 '20501231',
					 1, 0, 8, 0, 0);

				-- Solo la password corrente dell'utente collegato: lo storico (fino a 5 righe)
				-- avrebbe la stessa Data e violerebbe la chiave (Id, Data)
				INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data])
				SELECT TOP 1 @returnIdUtente, p.[Password], GETDATE()
				FROM dbo.tblUtentiPassword p
				INNER JOIN dbo.tblSessioni e ON p.Id = e.IdUtente
				WHERE e.Id = @IdSessione
				ORDER BY p.[Data] DESC;

				INSERT INTO dbo.tblUtentiDefault (Id)
				VALUES (@returnIdUtente);

				INSERT INTO dbo.tblSedi
					(Id, IdParent, IdAziendaInterna, InternaEsterna, IdTipo,
					 Disabilitata, Nome, CodiceFiscale, PartitaIva,
					 NomeCompleto, Lock)
				VALUES
					(@returnIdSede, NULL, @returnIdSede, 'I', 'L',
					 0, '(Da indicare)', '00000000000', '00000000000',
					 '(Da indicare)', 0);

				INSERT INTO dbo.tblSediInterne (Id, IdDominio)
				VALUES (@returnIdSede, @Id);

				INSERT INTO dbo.tblIndirizzi
					(Id, Indirizzo, CAP, Localita, IdComune, IdNazione)
				VALUES
					(@returnIdIndirizzo,
					 '(Indicare la via e numero civico)',
					 '20100', NULL, '015146', '380');

				INSERT INTO dbo.tblSediIndirizzi (Id, IdIndirizzo)
				VALUES (@returnIdSede, @returnIdIndirizzo);

				INSERT INTO dbo.tblDominiModuli (Id, IdModulo)
				SELECT @Id, Id
				FROM dbo.tblModuli
				WHERE Id IN ('BAS', 'IMP');
			END

			DELETE f
			FROM dbo.tblUtentiFunzioni f
			INNER JOIN dbo.tblUtenti u ON f.Id = u.Id
			WHERE
				u.IdDominio = @Id
				AND f.IdFunzione NOT IN ( SELECT mf.IdFunzione FROM dbo.tblModuliFunzioni mf INNER JOIN dbo.tblDominiModuli dm ON mf.Id = dm.IdModulo WHERE dm.Id = @Id );

			UPDATE dbo.tblDomini
			SET
				Lock = 0,
				IdStato = @IdStato,
				Nome = ISNULL(@Nome, Nome),
				Riferimento = ISNULL(@Riferimento, Riferimento),
				Scadenza = ISNULL(@Scadenza, Scadenza),
				ScadenzaAuto = @ScadenzaAuto,
				UtentiMax = @UtentiMax,
				AziendeMax = @AziendeMax,
				SediMax = @SediMax,
				RegistriMax = @RegistriMax,
				MagazziniMax = @MagazziniMax,
				ServiziMax = @ServiziMax,
				RentriMax = @RentriMax,
				ConservazioniMax = @ConservazioniMax,
				ConservazioniXfirMax = @ConservazioniXfirMax,
				Demo = @Demo,
				Codice = ISNULL(@Codice, Codice),
				Logo = IIF(@NoLogo = 1, NULL, Logo),
				[Url] = ISNULL(@Url, [Url])
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Dominio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

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
