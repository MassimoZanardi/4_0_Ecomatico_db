SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Pannello "RENTRI - Stato" (Rifiuti/Registrazioni/Edit): 6 stati/date RENTRI in sola lettura, letti solo
-- all'apertura del pannello (SP dedicata, non parte di uspRifiutiRegistrazioni_get usata dal caricamento
-- pagina, su richiesta esplicita dell'utente). RentriDataInvioConservazione e' risolta con un JOIN
-- cross-database sull'hub 1_0_rentri: la stessa registrazione puo' essere stata portata in conservazione
-- piu' volte, si prende sempre la data piu' recente con Conservazione = 1 (TOP 1 ... ORDER BY Data DESC).
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_StatoRentri]
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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			RentriData = r.RentriData,
			RentriFormularioStato = m.RentriFormularioStato,
			RentriFormularioDataCopia = m.RentriFormularioDataCopia,
			RentriFormularioDataPresaVisione = m.RentriFormularioDataPresaVisione,
			DataEsito = r.DataFineTrasporto,
			RentriFormularioDataTrasmissione = m.RentriFormularioDataTrasmissione,
			RentriDataInvioConservazione = cons.Data
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRentriRegistri rr ON rr.Id = m.IdRegistro
			OUTER APPLY (
				SELECT TOP 1 c.Data
				FROM [1_0_rentri]..tblRegistriConservazioni c
				WHERE
					c.IdRegistro = rr.IdRentri COLLATE DATABASE_DEFAULT
					AND c.Anno = YEAR(r.[Data])
					AND r.Numero BETWEEN c.DalNumero AND c.AlNumero
					AND c.Conservazione = 1
				ORDER BY c.Data DESC
			) cons
		WHERE r.Id = @Id;

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
