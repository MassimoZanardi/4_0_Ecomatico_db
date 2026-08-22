CREATE PROCEDURE [dbo].[uspServiziAssegnati_get]
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

		-- Controllo permesso: SRV (Gestione Servizi) O SRA (Servizi Assegnati)
		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 1 > @permessoSrv AND 1 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Verifica che il servizio appartenga a un calendario accessibile dalla sessione
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			s.IdTipo,
			IdRichiedente = ISNULL(s.IdRichiedente, ''),
			IdEvento = ISNULL(s.IdEvento, ''),
			Descrizione = ISNULL(s.Descrizione, ''),
			DataRichiesta = ISNULL(s.DataRichiesta, GETDATE()),
			IdStato = ISNULL(e.IdStato, 'D'),
			[Data] = ISNULL(e.[Data], DATEADD(MINUTE, ((DATEDIFF(MINUTE, 0, GETDATE()) / 30) * 30), 0)),
			InGiornata = ISNULL(e.InGiornata, 0),
			e.Lock,
			Proprieta = dbo.ufnEventi_get_TipoProprieta(s.IdEvento, s.IdTipo),
			FirmaRichiedente = fr.Firma
		FROM
			dbo.tblServizi s
		INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		LEFT JOIN dbo.tblEventiFirme er ON e.Id = er.Id
												   AND er.IdTipo = 'R'
		LEFT JOIN dbo.tblFirme fr ON er.IdFirma = fr.Id
		WHERE
			s.Id = @Id
			AND e.Lock <= 2;

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
