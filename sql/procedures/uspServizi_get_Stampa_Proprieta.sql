SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Proprietà del tipo stampate sul Rapporto di intervento, nell'ordine del tipo (Pos), anche senza valore: la stampa
-- mette al loro posto lo spazio da compilare a mano. Data in formato dd/MM/yyyy, Sì/No in Spuntata. Stessi diritti
-- di uspServizi_get_Stampa, che fa anche i controlli sul servizio da stampare
CREATE OR ALTER PROCEDURE dbo.uspServizi_get_Stampa_Proprieta
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @assegnato BIT;

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

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		-- Servizio assegnato all'utente della sessione: con la sola SRA si stampano solo questi
		SET @assegnato = IIF(EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventiUtenti u ON s.IdEvento = u.Id
				INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente
			WHERE
				s.Id = @Id
				AND ss.Id = @IdSessione
		), 1, 0);

		-- Calendario di una sede accessibile e permesso SRV, oppure SRA sul servizio assegnato
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		   OR NOT (@permessoSrv >= 1 OR (@permessoSra >= 1 AND @assegnato = 1))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			t.Nome,
			p.IdTipoDato,
			Valore = CASE p.IdTipoDato
				WHEN 'D' THEN CONVERT(VARCHAR(10), TRY_CONVERT(DATE, ep.Valore, 23), 103)
				WHEN 'B' THEN NULL
				ELSE NULLIF(ep.Valore, '')
			END,
			Spuntata = CAST(IIF(p.IdTipoDato = 'B' AND ep.Valore = 'true', 1, 0) AS BIT)
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblTipiProprieta t ON s.IdTipo = t.Id
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta ep ON s.IdEvento = ep.Id
												  AND t.IdProprieta = ep.IdProprieta
		WHERE s.Id = @Id
		ORDER BY t.Pos;

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
