CREATE PROCEDURE [dbo].[uspRifiutiModelli_get_Etichette_SelectList]
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
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: senza questo controllo, chiunque avesse una sessione valida
		-- poteva leggere le etichette di un modello di un'altra azienda conoscendone
		-- l'Id — stesso pattern usato in uspRifiutiModelli_get.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = t.Id,
			[Text] =
				(SELECT
					e.Nome,
					Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
					e.Descrizione,
					e.Visualizzazione
				FROM
					dbo.tblEtichette e
				INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
				WHERE t.Id = e.Id FOR JSON PATH),
			Selected = CAST(IIF(e.IdEtichetta IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblEtichette t
		LEFT OUTER JOIN (
				SELECT IdEtichetta
				FROM dbo.tblRifiutiModelliEtichette
				WHERE Id = @Id) e ON t.Id = e.IdEtichetta
		WHERE
			-- Filtro sede corretto: tblRifiutiModelli non ha una colonna IdSede propria,
			-- prima veniva usata una subquery che referenziava una colonna inesistente;
			-- T-SQL la risolveva silenziosamente sullo scope esterno (t.IdSede), rendendo
			-- il filtro un confronto con se stesso sempre vero (nessun errore, nessuno
			-- scoping reale) — confermato: la SP restituiva tutte le etichette RIF di
			-- qualunque azienda, non solo quelle della sede del modello.
			t.IdSede = (
				SELECT g.IdSede
				FROM
					dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				WHERE m.Id = @Id
			)
			AND t.IdModulo = 'RIF'
			AND t.Lock = 0
		ORDER BY
			Selected DESC, [Text];

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
