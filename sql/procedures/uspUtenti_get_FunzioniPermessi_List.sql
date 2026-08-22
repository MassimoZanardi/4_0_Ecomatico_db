CREATE PROCEDURE [dbo].[uspUtenti_get_FunzioniPermessi_List]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro
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

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND IdDominio = @idDominioSessione
		)
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			f.Id,
			f.Nome,
			Moduli = STRING_AGG(CONCAT('[', m.Nome, ']'), ' ')
					   WITHIN GROUP (ORDER BY m.Nome),
			Permesso = ISNULL(p.Nome, 'Accesso negato')
		FROM
			dbo.tblUtenti u
		INNER JOIN dbo.tblDominiModuli d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblModuli m ON d.IDModulo = m.Id
		INNER JOIN dbo.tblModuliFunzioni mf ON m.Id = mf.Id
		INNER JOIN dbo.tblFunzioni f ON mf.IdFunzione = f.Id
		LEFT JOIN dbo.tblUtentiFunzioni uf ON f.Id = uf.IdFunzione
											   AND uf.Id = @Id
		LEFT JOIN dbo.tblPermessi p ON uf.IdPermesso = p.Id
		WHERE
			u.Id = @Id
			AND f.[Master] = 0
			AND f.[Admin] = 0
			AND f.Attiva = 1
			AND m.Id NOT IN ('BAS', 'IMP') -- BAS = Base, IMP = Impostazioni (moduli esclusi)
		GROUP BY
			f.Id, f.Nome, p.Nome
		ORDER BY
			f.Nome;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
