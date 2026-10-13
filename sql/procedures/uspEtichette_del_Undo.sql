CREATE OR ALTER PROCEDURE [dbo].[uspEtichette_del_Undo]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;

	BEGIN TRY

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblEtichette i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE c.IdSessione = @IdSessione;

			IF EXISTS (
				SELECT 1
				FROM dbo.tblEtichette i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				WHERE
					c.IdSessione = @IdSessione
					AND i.IdModulo IN ('SRV', 'SCD')
			)
			BEGIN
				UPDATE e
				SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c2.Hex, c2.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblEventiEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c2 ON et.IdColore = c2.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
				FROM dbo.tblEventi e
				INNER JOIN dbo.tblEventiEtichette t ON e.Id = t.Id
				INNER JOIN dbo.tblIdCancellati c ON t.IdEtichetta = c.Id
				WHERE c.IdSessione = @IdSessione;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblEtichette i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				WHERE
					c.IdSessione = @IdSessione
					AND i.IdModulo = 'RIF'
			)
			BEGIN
				UPDATE e
				SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c2.Hex, c2.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblRifiutiRegistrazioniEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c2 ON et.IdColore = c2.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
				FROM dbo.tblRifiutiRegistrazioni e
				INNER JOIN dbo.tblRifiutiRegistrazioniEtichette t ON e.Id = t.Id
				INNER JOIN dbo.tblIdCancellati c ON t.IdEtichetta = c.Id
				WHERE c.IdSessione = @IdSessione;

				UPDATE e
				SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c2.Hex, c2.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblRifiutiFormulariEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c2 ON et.IdColore = c2.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
				FROM dbo.tblRifiutiFormulari e
				INNER JOIN dbo.tblRifiutiFormulariEtichette t ON e.Id = t.Id
				INNER JOIN dbo.tblIdCancellati c ON t.IdEtichetta = c.Id
				WHERE c.IdSessione = @IdSessione;

				UPDATE e
				SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c2.Hex, c2.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblRifiutiModelliEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c2 ON et.IdColore = c2.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
				FROM dbo.tblRifiutiModelli e
				INNER JOIN dbo.tblRifiutiModelliEtichette t ON e.Id = t.Id
				INNER JOIN dbo.tblIdCancellati c ON t.IdEtichetta = c.Id
				WHERE c.IdSessione = @IdSessione;
			END
			-- Magazzino: le etichette stanno sui DDT
			IF EXISTS (SELECT 1 FROM dbo.tblEtichette i INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id WHERE c.IdSessione = @IdSessione AND i.IdModulo = 'MAG')
			BEGIN
				UPDATE e
				SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c2.Hex, c2.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblMagazziniDdtEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c2 ON et.IdColore = c2.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
				FROM dbo.tblMagazziniDdt e
				INNER JOIN dbo.tblMagazziniDdtEtichette t ON e.Id = t.Id
				INNER JOIN dbo.tblIdCancellati c ON t.IdEtichetta = c.Id
				WHERE c.IdSessione = @IdSessione;
			END

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT; -- @@ROWCOUNT DOPO DELETE tblIdCancellati

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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
