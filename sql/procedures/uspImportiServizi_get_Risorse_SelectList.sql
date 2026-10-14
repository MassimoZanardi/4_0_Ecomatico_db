SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select delle risorse per la riga di tipo Risorsa (SU) di un importo dei servizi: persone e oggetti impiegabili
-- nei servizi, dell'azienda interna corrente della sessione o condivisi nel dominio, come nella scheda del
-- servizio (uspOsepe_get_SelectList). Le prime 50 che contengono @Search; la prima voce (Id a zeri) chiede di
-- scegliere. La risorsa selezionata è sempre presente, anche se cancellata o non più impiegabile.
CREATE OR ALTER PROCEDURE dbo.uspImportiServizi_get_Risorse_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Servizi sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			-- Risorsa selezionata: persona oppure oggetto
			SELECT
				o.Id,
				[Text] = CAST(ISNULL(p.NomeCompleto, g.Nome) AS VARCHAR(400)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblOsepe o
				LEFT JOIN dbo.tblPersone p ON o.Id = p.Id
											AND o.Tipo = 'P'
				LEFT JOIN dbo.tblOggetti g ON o.Id = g.Id
											AND o.Tipo = 'O'
			WHERE
				o.Id = @IdSelected
				AND o.Id <> @idSediciZeri
				AND (p.Id IS NOT NULL OR g.Id IS NOT NULL)
			UNION ALL
			SELECT
				t.Id,
				t.[Text],
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				(
					SELECT TOP (50)
						u.Id,
						[Text] = CAST(u.[Text] AS VARCHAR(400))
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
					WHERE
						e.Id = @IdSessione
						AND
							(
								(
								u.IdDominio = e.IdDominio
								AND u.Condivisa = 1
								)
							-- u.IdSede è l'azienda interna dell'anagrafica
							OR u.IdSede = e.IdAzienda
							)
						AND u.Tipo IN ('P', 'O')
						AND u.Disabilitata = 0
						AND u.ImpiegabileServizi = 1
						AND u.Id <> @IdSelected
						AND
							(
							@Search IS NULL
							OR u.[Text] LIKE '%' + @Search + '%'
							)
					ORDER BY u.[Text], u.Id
				) t
		) x
		ORDER BY Pos, [Text]
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
