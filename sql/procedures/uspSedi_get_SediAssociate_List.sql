CREATE OR ALTER PROCEDURE [dbo].[uspSedi_get_SediAssociate_List]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
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

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblSedi
		WHERE
			Id = @Id
			AND InternaEsterna = 'I'
		)
		BEGIN
			-- Il controllo di titolarità si applica solo a sedi già confermate (Lock = 0):
			-- su una sede esterna ancora in draft (Lock = 2, appena creata da uspSedi_ins)
			-- IdAziendaInterna non è ancora valorizzata (viene calcolata solo da uspSedi_upd),
			-- quindi il join fallirebbe sempre e bloccherebbe anche il creatore del draft.
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @Id
				AND Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
						   ON s.IdAziendaInterna = i.Id
				WHERE s.Id = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Titolarità: Admin dello stesso Dominio della sede, oppure Admin di un Dominio Master.
			-- Stessa guardia Lock = 0 di cui sopra, per coerenza con uspSedi_upd.
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @Id
				AND Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
				INNER JOIN dbo.tblUtenti a ON i.IdDominio = a.IdDominio
				INNER JOIN dbo.tblSessioni e ON a.Id = e.IdUtente
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
					AND a.IdRuolo = 'AD'
					AND a.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
				WHERE
					e.Id = @IdSessione
					AND ut.IdRuolo = 'AD'
					AND ut.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
		END

		SELECT TOP 50
			Id,
			NomeCompleto,
			IndirizzoCompleto
		FROM
			dbo.tblSedi
		WHERE
			IdParent = @Id
			AND Lock = 0
			AND
				(
				@Search IS NULL
				OR NomeCompleto LIKE '%' + @Search + '%'
				OR IndirizzoCompleto LIKE '%' + @Search + '%'
				)
		ORDER BY NomeCompleto
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
