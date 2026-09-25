SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_RelazioniTutte]
	@IdSessione CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Calcolata una sola volta e riusata nei due controlli titolarità sottostanti,
		-- invece di richiamare la function separatamente per ciascuno
		DECLARE @sedi TABLE (Id CHAR(16) PRIMARY KEY);
		INSERT @sedi (Id)
		SELECT Id
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione);

		IF (
			SELECT COUNT(DISTINCT g.Id)
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdParent
				AND (RentriIdentificativo IS NOT NULL OR RentriData IS NOT NULL)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie - difesa in profondità, la UI già nasconde la sezione per queste registrazioni
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni s
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;

		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		BEGIN TRANSACTION;

			--      QuantitaResidua = v.Quantita - ISNULL(a.Quantita, 0)
			INSERT dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			SELECT TOP(499 - @pos)
				r.Id,
				@IdParent,
				IIF(r.Operazione = 'C', 'S', 'C'),
				0,
				@pos + ROW_NUMBER() OVER (ORDER BY YEAR(r.[Data]), r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN (
					SELECT
						l.Id,
						Quantita = SUM(l.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
					WHERE
						p.Lock < 2
						-- Valori effettivi (viewRifiutiRegistrazioniEffettive): uno scarico annullato ha Quantita = 0,
						-- le sue relazioni restano per la stampa ma non consumano piu' il carico
						AND vp.Quantita > 0
					GROUP BY l.Id
				) a ON r.Id = a.Id
			WHERE
				r.Lock = 0
				AND m.IdRegistro = @IdRegistro
				AND
					(
					@idOperazione IN ('K', 'M')
					OR v.IdEer = @IdEer
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR v.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR v.IdUnitaMisura = @IdUnitaMisura
					)
				AND
					(
					r.[Data] < @Data
					OR
						(
						r.[Data] = @Data
						AND r.Numero < @Numero
						)
					)
				AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
				AND v.Quantita - ISNULL(a.Quantita, 0) > 0 -- QuantitaResidua > 0
				-- Una registrazione di produzione Materiale è l'ultima fase del ciclo: non può mai
				-- diventare figlia (Id) di un'altra registrazione tramite questo inserimento massivo
				AND r.IdMateriale IS NULL
				AND NOT EXISTS ( SELECT 1 FROM dbo.tblRifiutiRegistrazioniRelazioni x WHERE x.Id = r.Id AND x.IdParent = @IdParent )
				-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
				-- proprie: non deve mai comparire come candidata da associare
				AND v.IsRettifica = 0
			ORDER BY YEAR(r.[Data]), r.Numero;

			SET @returnValue = @@ROWCOUNT;

			-- Imposta la registrazione nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;

		COMMIT TRANSACTION;

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

	SELECT ReturnValue = @returnValue;
END;
