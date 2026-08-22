CREATE OR ALTER PROCEDURE [dbo].[uspSessioni_upd]
	@Id CHAR(16) = NULL,
	@Contesto INT = NULL,
	@IdContesto CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	/*
     * Aggiorna il contesto attivo della sessione @Id.
     *
     * @Contesto → colonna aggiornata in tblSessioni:
     *   0 = Dominio    → IdDominio    (solo da sessione su dominio Master)
     *   1 = Azienda    → IdAzienda
     *   2 = Sede       → IdSede
     *   3 = Registro   → IdRegistro
     *   4 = Magazzino  → IdMagazzino
     *   5 = Calendario → IdCalendario
     *
     */

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;

	BEGIN TRY

		-- ── Validazione parametri ───────────────────────────────────────────
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdContesto = NULLIF(LTRIM(RTRIM(@IdContesto)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @Contesto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Contesto non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdContesto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdContesto non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- ── Aggiornamento contesto sessione ─────────────────────────────────
		-- Ogni branch verifica implicitamente i permessi tramite JOIN:
		-- se l'utente non ha accesso al contesto, @@ROWCOUNT = 0.
		IF @Contesto = 0 -- Dominio
		BEGIN
			-- ✅ JOIN diretto su tblDomini al posto di EXISTS inline
			UPDATE x
			SET IdDominio = @IdContesto
			FROM dbo.tblSessioni x
			INNER JOIN dbo.tblUtenti ut ON x.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			INNER JOIN dbo.tblDomini dt ON dt.Id = @IdContesto
			WHERE
				x.Id = @Id
				AND d.[Master] = 1
				AND dt.Lock = 0;
		END
		ELSE IF @Contesto = 1 -- Azienda
		BEGIN
			UPDATE x
			SET IdAzienda = @IdContesto
			FROM dbo.tblSessioni x
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(x.IdUtente) u
			WHERE
				x.Id = @Id
				AND u.Id = @IdContesto;
		END
		ELSE IF @Contesto = 2 -- Sede
		BEGIN
			UPDATE x
			SET IdSede = @IdContesto
			FROM dbo.tblSessioni x
			CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(x.IdUtente) u
			WHERE
				x.Id = @Id
				AND u.Id = @IdContesto;
		END
		ELSE IF @Contesto = 3 -- Registro
		BEGIN
			UPDATE x
			SET IdRegistro = @IdContesto
			FROM dbo.tblSessioni x
			CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(x.IdUtente) u
			INNER JOIN dbo.tblRifiutiRegistri r ON u.Id = r.IdSede
			WHERE
				x.Id = @Id
				AND r.Id = @IdContesto
				AND r.Lock = 0;
		END
		ELSE IF @Contesto = 4 -- Magazzino
		BEGIN
			UPDATE x
			SET IdMagazzino = @IdContesto
			FROM dbo.tblSessioni x
			CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(x.IdUtente) u
			INNER JOIN dbo.tblMagazzini m ON u.Id = m.IdSede
			WHERE
				x.Id = @Id
				AND m.Id = @IdContesto
				AND m.Lock = 0;
		END
		ELSE IF @Contesto = 5 -- Calendario
		BEGIN
			UPDATE x
			SET IdCalendario = @IdContesto
			FROM dbo.tblSessioni x
			CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(x.IdUtente) u
			INNER JOIN dbo.tblCalendari c ON u.Id = c.IdSede
			WHERE
				x.Id = @Id
				AND c.Id = @IdContesto
				AND c.Lock = 0;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Valore @Contesto non valido: ' + CAST(@Contesto AS VARCHAR(5));
			GOTO BRANCH_END;
		END

		-- ✅ Verifica che il contesto sia stato effettivamente aggiornato
		-- @@ROWCOUNT = 0 significa: sessione non trovata OPPURE
		-- @IdContesto non accessibile dall'utente della sessione
		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non trovata o contesto non accessibile dall''utente';
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	-- ── Uscita per validazioni (fuori TRY/CATCH — intenzionale) ────────────
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Errore non specificato');
		THROW 50001, @returnMessage, 1;
	END

END;
