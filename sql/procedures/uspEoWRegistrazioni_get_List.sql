SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWRegistrazioni_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Allocazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Le select dei filtri usano gli zeri come "nessuna selezione"
		SET @IdLotto = NULLIF(NULLIF(LTRIM(RTRIM(@IdLotto)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @Allocazione = NULLIF(LTRIM(RTRIM(@Allocazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Allocazione: NULL = tutte, D = con quantità ancora da allocare, A = allocate per intero
		IF @Allocazione IS NOT NULL AND @Allocazione NOT IN ('D', 'A')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Allocazione deve essere D (Da allocare) o A (Allocate)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul Lotto indicato
		IF @IdLotto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Una riga per ogni allocazione (registrazione M + lotto); una registrazione M senza
		-- allocazioni ha una sola riga senza lotto. Valori operativi (viewRifiutiRegistrazioniEffettive):
		-- le rettifiche non ricevono mai allocazioni e non compaiono
		;WITH reg AS (
			SELECT
				r.Id,
				RegistroNome = g.Nome,
				r.Numero,
				r.Data,
				MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
				QuantitaOperativa = vo.Quantita,
				IsAnnullata = ISNULL(vo.IsAnnullata, 0),
				QuantitaAllocataTotale = ISNULL(a.QuantitaAllocata, 0),
				NumeroAllocazioni = ISNULL(a.NumeroAllocazioni, 0)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
				OUTER APPLY (
					SELECT
						QuantitaAllocata = SUM(q.Quantita),
						NumeroAllocazioni = COUNT(*)
					FROM dbo.tblEoWLottiRifiutiRegistrazioni q
					WHERE q.IdRegistrazione = r.Id) a
			WHERE
				r.Lock < 2
				AND o.IsMateriale = 1
				AND ISNULL(vo.IsRettifica, 0) = 0
				AND g.IdSede = @idSede
				AND
					(
					@IdMateriale IS NULL
					OR r.IdMateriale = @IdMateriale
					)
				AND
					(
					@DallaData IS NULL
					OR r.Data >= @DallaData
					)
				AND
					(
					@AllaData IS NULL
					OR r.Data < DATEADD(DAY, 1, @AllaData)
					)
		)
		SELECT
			reg.Id,
			-- Stato della registrazione (uguale su ogni sua riga): 0 = allocata per intero, 1 = allocata
			-- in parte o non allocata, 2 = anomalia (allocata più della quantità operativa)
			StatoValore = CASE
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale < 0 THEN 2
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale > 0 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale < 0
					THEN 'Allocata più della quantità della registrazione: allocati ' + FORMAT(reg.QuantitaAllocataTotale, 'N2', 'it-IT')
						+ ' kg su ' + FORMAT(reg.QuantitaOperativa, 'N2', 'it-IT') + ' kg'
				WHEN reg.NumeroAllocazioni = 0
					THEN 'Non allocata: ' + FORMAT(reg.QuantitaOperativa, 'N2', 'it-IT') + ' kg da allocare'
				WHEN reg.QuantitaOperativa - reg.QuantitaAllocataTotale > 0
					THEN 'Allocata in parte: allocati ' + FORMAT(reg.QuantitaAllocataTotale, 'N2', 'it-IT') + ' kg su '
						+ FORMAT(reg.QuantitaOperativa, 'N2', 'it-IT') + ' kg, '
						+ FORMAT(reg.QuantitaOperativa - reg.QuantitaAllocataTotale, 'N2', 'it-IT') + ' kg da allocare'
				ELSE 'Allocata per intero: ' + FORMAT(reg.QuantitaAllocataTotale, 'N2', 'it-IT') + ' kg'
			END,
			reg.RegistroNome,
			reg.Numero,
			reg.Data,
			reg.MaterialeNome,
			IdLotto = lr.IdLotto,
			LottoNome = l.Nome,
			QuantitaAllocata = lr.Quantita,
			QuantitaDaAllocare = reg.QuantitaOperativa - reg.QuantitaAllocataTotale,
			RowsCount = COUNT(*) OVER ()
		FROM
			reg
			LEFT JOIN dbo.tblEoWLottiRifiutiRegistrazioni lr ON reg.Id = lr.IdRegistrazione
			LEFT JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
		WHERE
			-- Una registrazione M senza allocazioni e senza quantità operativa (annullata o a zero)
			-- non ha nulla da allocare: non compare
			(
				reg.NumeroAllocazioni > 0
				OR (reg.IsAnnullata = 0 AND reg.QuantitaOperativa > 0)
			)
			AND
				(
				@IdLotto IS NULL
				OR lr.IdLotto = @IdLotto
				)
			AND
				(
				@Allocazione IS NULL
				OR
					(
					@Allocazione = 'D'
					AND reg.QuantitaOperativa - reg.QuantitaAllocataTotale > 0
					)
				OR
					(
					@Allocazione = 'A'
					AND reg.NumeroAllocazioni > 0
					AND reg.QuantitaOperativa - reg.QuantitaAllocataTotale <= 0
					)
				)
		ORDER BY reg.Data DESC, reg.Numero DESC, lr.Pos, l.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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
