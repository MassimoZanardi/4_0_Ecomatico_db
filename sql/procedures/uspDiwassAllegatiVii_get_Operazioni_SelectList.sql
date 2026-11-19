SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Causali proposte per registrare un Allegato VII dell'azienda del contesto (docs/regole/diwass.md D8.2), secondo il
-- ruolo dell'azienda nel documento: trasporto T*aT (T) se è un trasportatore, carico da terzi T* (Z) se è l'impianto,
-- scarico a terzi aT (S) se è il produttore o chi organizza; prima la proposta (nell'ordine T, Z, S). Il filtro è
-- proprio di questa funzione (decisione dell'utente del 2026-11-19) e lo ripete uspRifiutiMovimenti_ins_DaAllegatoVii
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Operazioni_SelectList]
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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @ruoli VARCHAR(10);
		SELECT @ruoli = ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', ''))
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @ruoli IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT
			o.Id,
			[Text] = CAST(o.Pos AS VARCHAR(2)) + '. ' + o.Nome
		FROM dbo.tblRifiutiOperazioni o
		WHERE
			(
			o.Id = 'T'
			AND @ruoli LIKE '%T%'
			)
			OR
				(
				o.Id = 'Z'
				AND @ruoli LIKE '%I%'
				)
			OR
				(
				o.Id = 'S'
				AND
					(
					@ruoli LIKE '%P%'
					OR @ruoli LIKE '%O%'
					)
				)
		ORDER BY CASE o.Id WHEN 'T' THEN 0 WHEN 'Z' THEN 1 ELSE 2 END;

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
