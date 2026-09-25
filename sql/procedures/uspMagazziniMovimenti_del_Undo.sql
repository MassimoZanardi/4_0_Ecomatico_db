SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

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
			FROM dbo.tblMagazziniMovimenti i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			-- Ripristinare uno scarico riattiva le sue relazioni carico/scarico: nel frattempo
			-- i carichi potrebbero essere stati consumati da altri scarichi, e nessun carico
			-- può risultare consumato oltre la propria quantità
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblMagazziniMovimentiRighe rc
					CROSS APPLY (
						SELECT Consumata = SUM(rel.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rel.Id = rc.Id
							AND mp.Lock IN (0, 2)
					) q
				WHERE
					rc.Id IN (
						SELECT rel2.Id
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel2
							INNER JOIN dbo.tblMagazziniMovimentiRighe rp2 ON rel2.IdParent = rp2.Id
							INNER JOIN dbo.tblIdCancellati k ON rp2.IdMovimento = k.Id
						WHERE k.IdSessione = @IdSessione
					)
					AND q.Consumata > rc.Quantita
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile ripristinare: i carichi utilizzati dallo scarico sono stati nel frattempo consumati da altri scarichi';
				GOTO BRANCH_END;
			END

			-- Stesso vincolo per le righe EoW: nessun lotto EoW scaricato oltre la quantità
			-- prodotta (quote di registrazioni M attive)
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblEoWLotti l
					CROSS APPLY (
						SELECT Scaricata = SUM(rs.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheEoWLotti rs WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rs.IdLotto = l.Id
							AND mp.Lock IN (0, 2)
					) sc
					OUTER APPLY (
						SELECT Prodotta = SUM(qp.Quantita)
						FROM
							dbo.tblEoWLottiRifiutiRegistrazioni qp
							INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
						WHERE
							qp.IdLotto = l.Id
							AND rr.Lock < 2
					) p
				WHERE
					l.Id IN (
						SELECT rs2.IdLotto
						FROM
							dbo.tblMagazziniMovimentiRigheEoWLotti rs2
							INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp2 ON rs2.Id = rp2.Id
							INNER JOIN dbo.tblIdCancellati k ON rp2.IdMovimento = k.Id
						WHERE k.IdSessione = @IdSessione
					)
					AND sc.Scaricata > ISNULL(p.Prodotta, 0)
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile ripristinare: i lotti EoW utilizzati dallo scarico sono stati nel frattempo consumati da altri scarichi';
				GOTO BRANCH_END;
			END

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

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
GO
