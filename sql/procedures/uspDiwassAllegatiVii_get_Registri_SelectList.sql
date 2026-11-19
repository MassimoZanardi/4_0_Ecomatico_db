SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registri in cui registrare un Allegato VII dell'azienda del contesto (docs/regole/diwass.md D8.2): registri attivi
-- delle sedi interne dell'azienda visibili all'utente, prima quelli della sede che compare nel documento con il ruolo
-- dell'azienda (stesso operatore DIWASS), poi per nome. Casella di ricerca a fianco della select (@Search sul testo,
-- come Copia/incolla delle registrazioni): al massimo 20 voci, il registro scelto (@IdSelected) resta sempre in elenco
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Registri_SelectList]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
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

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = a.IdAziendaInterna
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT TOP 20
			g.Id,
			[Text] = g.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto
		FROM
			dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			INNER JOIN dbo.tblRifiutiRegistri g ON i.Id = g.IdSede
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			OUTER APPLY (
				SELECT TOP 1 Nel = 1
				FROM
					dbo.tblDiwassAllegatiViiSoggetti x
					LEFT JOIN dbo.tblDiwassOperatori ox ON x.IdSede = ox.Id
					LEFT JOIN dbo.tblDiwassOperatori os ON os.Id = s.Id
				WHERE
					x.Id = @Id
					AND
						(
						x.IdSede = s.Id
						OR ISNULL(ox.OperatorInternalId, x.OperatorInternalId) = os.OperatorInternalId
						)
			) d
		WHERE
			g.Lock = 0
			AND s.IdAziendaInterna = @idAzienda
			AND
				(
				@Search IS NULL
				OR g.Id = @IdSelected
				OR (g.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto) LIKE '%' + @Search + '%'
				)
		ORDER BY IIF(g.Id = @IdSelected, 0, 1), ISNULL(d.Nel, 0) DESC, g.Nome, s.Nome
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
