CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get]
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
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				Id = @Id
				AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Autorizzazione non trovata';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		DECLARE @idAzienda CHAR(16);
		SELECT @idUtente = IdUtente,
			   @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Titolarità: controllata indipendentemente dal Lock (prima scattava solo per
		-- Lock=0, lasciando le bozze Lock=2 di altre aziende leggibili da chiunque avesse
		-- permesso RAT). Visibile se la sede è interna alla sessione OPPURE se è una sede
		-- esterna condivisa con l'utente (vedi Ramo 2 di uspRifiutiAutorizzazioni_get_List,
		-- che già lista queste autorizzazioni condivise).
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.IdAziendaInterna = i.Id
			WHERE a.Id = @Id)
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(@idUtente) x ON s.Id = x.Id
			WHERE
				a.Id = @Id
				AND x.IdAziendaInterna <> @idAzienda
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			IdSede = ISNULL(a.IdSede, REPLICATE('0', 16)),
			IdRuolo = ISNULL(a.IdRuolo, '0'),
			Ruolo = r.Nome,
			IdTipo = ISNULL(a.IdTipo, '0'),
			IdNumeroTipo = ISNULL(a.IdNumeroTipo,
										CASE IdRuolo
											WHEN 'D' THEN 'C'
											ELSE 'A'
										END),
			Numero = ISNULL(a.Numero, ''),
			IsNumero = CAST(CASE
									   WHEN a.Lock = 2 THEN 1
									   WHEN a.Numero IS NULL THEN 0
									   ELSE 1
								   END AS BIT),
			Identificativo = ISNULL(a.Identificativo, ''),
			Note = ISNULL(a.Note, ''),
			DataInizio = ISNULL(a.DataInizio, GETDATE()),
			DataFine = ISNULL(a.DataFine, DATEADD(YEAR, 3, GETDATE())),
			Disabilitata = ISNULL(a.Disabilitata, 0),
			IsEerAssociabili = r.Eer,
			IsTargheAssociabili = r.Targhe,
			IsConducentiAssociabili = r.Conducenti,
			IsAttivitaAssociabili = r.Attivita,
			Condivisa = CAST(IIF(c.Id IS NULL, 0, 1) AS BIT),
			CondivisaDaArea = ISNULL(c.Area, ''),
			CondivisaDaAltri = CAST(IIF(@idAzienda = s.IdAziendaInterna, 0, 1) AS BIT),
			a.Lock
		FROM
			dbo.tblRifiutiAutorizzazioni a
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
			OUTER APPLY (
				SELECT TOP 1
					ae.Id,
					Area = ar.Nome
				FROM
					dbo.tblAreeOsepe ae
					INNER JOIN dbo.tblAree ar ON ae.Id = ar.Id
				WHERE
					ar.Lock = 0
					AND (ae.IdOsepe = s.Id OR ae.IdOsepe = s.IdParent)
			) c
		WHERE
			a.Id = @Id
			AND a.Lock <= 2;

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
