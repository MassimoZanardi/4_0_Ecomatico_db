CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_Quantita]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Data DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @Giacenza DECIMAL(18, 2);

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdEer IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEer non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: stesso controllo di uspRifiutiGiacenze_get_List/_get_Carichi_List.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @Data = ISNULL(@Data, GETDATE());

		-- Stessa logica di quantità residua di uspRifiutiGiacenze_get_List/_get_Carichi_List
		-- (Quantita - QuantitaAssegnata), ma senza raggruppamento/paginazione: un unico SUM
		-- per la combinazione Registro+Eer+StatoFisico richiesta. I due rami "Rifiuto prodotto"
		-- (IdOperazione <> 'R', Operazione = 'C') e "Rifiuto trattato" (IdOperazione = 'R',
		-- Operazione = 'S') sono mutuamente esclusivi sullo stesso record, quindi si possono
		-- unire in un solo OR invece di due UNION ALL separate.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		)
		SELECT
			@Giacenza = SUM(m.Quantita - ISNULL(a.Quantita, 0))
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
		WHERE
			r.Lock = 0
			AND r.[Data] <= @Data
			AND m.IdRegistro = @IdRegistro
			AND m.IdEer = @IdEer
			AND m.IdStatoFisico = @IdStatoFisico
			AND m.Quantita > 0
			AND (
				(ISNULL(m.IdOperazione, '') <> 'R' AND o.Operazione = 'C')
				OR (m.IdOperazione = 'R' AND o.Operazione = 'S')
			)
			AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0;

		SELECT rtn = ISNULL(@Giacenza, 0);

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
