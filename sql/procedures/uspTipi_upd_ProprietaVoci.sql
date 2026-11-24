SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Voci di un campo "Elenco a scelta" del tipo (S3.7, decisione dell'utente del 2026-11-24): sostituisce l'elenco con
-- quello inviato dalla scheda del tipo (JSON ["Voce 1","Voce 2", ...], nell'ordine). Sugli eventi e' salvato il testo
-- della voce: togliere o rinominare una voce non cambia le schede gia' compilate, che tengono il testo precedente
CREATE OR ALTER PROCEDURE [dbo].[uspTipi_upd_ProprietaVoci]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdProprieta CHAR(3) = NULL,
	@Voci NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdProprieta = NULLIF(LTRIM(RTRIM(@IdProprieta)), '');
		IF ISJSON(@Voci) = 0
			SET @Voci = NULL;
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
		IF @IdProprieta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProprieta non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'TPO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblTipi c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblTipiProprieta t
				INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			WHERE
				t.Id = @Id
				AND t.IdProprieta = @IdProprieta
				AND t.Lock = 0
				AND p.IdTipoDato = 'L')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Campo non trovato: aggiornare la pagina';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare le voci dell''elenco, una per riga';
			GOTO BRANCH_END;
		END

		SELECT TOP 1 @returnMessage = Errore
		FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci)
		WHERE Errore IS NOT NULL
		ORDER BY Pos;

		IF @returnMessage IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblTipiProprietaVoci
			WHERE
				Id = @Id
				AND IdProprieta = @IdProprieta;

			INSERT INTO dbo.tblTipiProprietaVoci (Id, IdProprieta, Pos, Nome)
			SELECT @Id, @IdProprieta, Pos, Nome
			FROM dbo.ufnTipi_get_ProprietaVoci_List(@Voci);
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

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
