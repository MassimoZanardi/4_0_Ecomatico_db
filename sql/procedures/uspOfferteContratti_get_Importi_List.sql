SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi di un contratto o di un'offerta dell'azienda interna corrente della sessione.
--   @Disponibili = 0: gli importi associati al contratto @Id (tutti, anche di un modulo non più attivo sul
--                     dominio: ModuloAttivo = 0, così si vedono e si possono togliere)
--   @Disponibili = 1: gli importi attivi dell'azienda che si possono associare: non associati ad alcun contratto
--                     o offerta (un importo sta in uno solo) e di un modulo attivo sul dominio; al massimo 50,
--                     filtrabili con @Search
-- Si legge con il permesso sui contratti (OCC): non serve quello sugli importi (OCI).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get_Importi_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Disponibili BIT = 0,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Disponibili = ISNULL(@Disponibili, 0);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = oc.IdSede
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione
			AND oc.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		-- Moduli dei documenti attivi sul dominio: pre-calcolati FUORI dalla query
		DECLARE @rifAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0);
		DECLARE @magAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0);
		DECLARE @srvAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0);

		SELECT TOP (IIF(@Disponibili = 1, 50, 100000))
			t.Id,
			t.IdModulo,
			Modulo = CASE t.IdModulo WHEN 'RIF' THEN 'Rifiuti' WHEN 'MAG' THEN 'Magazzino' WHEN 'SRV' THEN 'Servizi' END,
			t.ModuloAttivo,
			t.Nome,
			Priorita = p.Nome,
			Righe = (SELECT COUNT(*) FROM dbo.tblImportiRighe g WHERE g.IdImporto = t.Id)
		FROM
			(
				SELECT
					i.Id,
					i.Nome,
					i.IdPriorita,
					IdModulo = CAST(CASE
						WHEN r.Id IS NOT NULL THEN 'RIF'
						WHEN m.Id IS NOT NULL THEN 'MAG'
						WHEN v.Id IS NOT NULL THEN 'SRV'
					END AS CHAR(3)),
					ModuloAttivo = CAST(CASE
						WHEN r.Id IS NOT NULL THEN @rifAttivo
						WHEN m.Id IS NOT NULL THEN @magAttivo
						WHEN v.Id IS NOT NULL THEN @srvAttivo
						ELSE 0
					END AS BIT),
					Associato = IIF(ci.IdImporto IS NULL, 0, 1),
					Suo = IIF(ci.IdOffertaContratto = @Id, 1, 0)
				FROM
					dbo.tblImporti i
					LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
					LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
					LEFT JOIN dbo.tblImportiServizi v ON i.Id = v.Id
					LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
				WHERE
					i.IdSede = @idAzienda
					AND i.Lock = 0
			) t
			LEFT JOIN dbo.tblImportiPriorita p ON t.IdPriorita = p.Id
		WHERE
			(
				@Disponibili = 0
				AND t.Suo = 1
			)
			OR
			(
				@Disponibili = 1
				AND t.Associato = 0
				AND t.ModuloAttivo = 1
				AND (@Search IS NULL OR t.Nome LIKE '%' + @Search + '%')
			)
		ORDER BY t.IdModulo, t.Nome, t.Id
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
