SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Quota di conservazioni xFIR per il Registro in contesto (Rifiuti/Registrazioni/Index, azione
-- "RENTRI - Conservazione sostitutiva xFIR"): Max = tblRifiutiRegistri.ConservazioniXfirMax (limite
-- annuo configurato in Rentri/Registri/Edit), GiaUtilizzati = somma di
-- tblRifiutiMovimenti.RentriFormularioInviiConservazione gia' consumata nello stesso anno solare
-- indicato (@Anno), sullo stesso Registro. Il confronto con l'esito di
-- uspRentriFormulari_get_ConservazioneXfir_List (nuovi xFIR coinvolti) resta lato C#.
-- exec dbo.uspRentriFormulari_get_ConservazioneXfir_Limite @IdSessione='...', @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFormulari_get_ConservazioneXfir_Limite]
	@IdSessione CHAR(16) = NULL,
	@Anno INT = NULL
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
		IF @Anno IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''anno';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Max = ISNULL(g.ConservazioniXfirMax, 0),
			GiaUtilizzati = ISNULL((
				SELECT SUM(m.RentriFormularioInviiConservazione)
				FROM
					dbo.tblRifiutiMovimenti m
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
				WHERE
					m.IdRegistro = g.Id
					AND r.Lock < 2
					AND YEAR(r.[Data]) = @Anno
			), 0)
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.tblSessioni e ON g.Id = e.IdRegistro
		WHERE e.Id = @IdSessione;

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

END
GO
