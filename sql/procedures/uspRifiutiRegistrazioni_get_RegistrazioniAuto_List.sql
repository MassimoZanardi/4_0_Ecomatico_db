SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_RegistrazioniAuto_List]
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
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RRG', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla registrazione di origine.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Solo per registrazioni con Operazione 'I' (scarico per trattamento interno) collegate a
		-- un Modello con righe di generazione automatica configurate: nessuna riga altrimenti
		-- (nessun errore, l'assenza di righe è la condizione normale per la maggior parte delle registrazioni).
		SELECT
			ra.Id,
			ra.Posizione,
			ra.Percentuale,
			ra.IdEer,
			EerNome = eer.Nome + ISNULL(' - ' + eer.Descrizione, ''),
			ra.IdMateriale,
			MaterialeNome = mat.Nome,
			ra.IdStatoFisico,
			StatoFisicoNome = sf.Nome,
			ra.IdUnitaMisura,
			UnitaMisuraNome = um.Nome,
			EtichetteNomi = (
				SELECT STRING_AGG(e.Nome, ', ')
				FROM
					dbo.tblRifiutiModelliRegistrazioniAutoEtichette re
					INNER JOIN dbo.tblEtichette e ON re.IdEtichetta = e.Id
				WHERE re.Id = ra.Id)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto ra ON ra.IdModello = m.IdModello
			LEFT JOIN dbo.tblRifiutiEer eer ON ra.IdEer = eer.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON ra.IdMateriale = mat.Id
			LEFT JOIN dbo.tblRifiutiStatiFisici sf ON ra.IdStatoFisico = sf.Id
			LEFT JOIN dbo.tblUnitaMisura um ON ra.IdUnitaMisura = um.Id
		WHERE
			r.Id = @Id
			AND o.Codice = 'I'
			AND ra.Lock = 0
		ORDER BY ra.Posizione
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
		THROW 50001, @returnMessage, 1
	END

END;
