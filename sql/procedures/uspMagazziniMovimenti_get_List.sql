SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@ConDdt BIT = 0,
	@DdtNumero INT = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtMittente VARCHAR(50) = NULL,
	@DdtDestinatario VARCHAR(50) = NULL,
	@DdtTrasportatore VARCHAR(50) = NULL,
	@DdtEmessi BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		-- Ricerca sul DDT: "Con DDT" limita ai movimenti che hanno un DDT e abilita gli altri filtri
		-- sul DDT, che senza di esso vengono ignorati. Mittente, destinatario e trasportatore sono
		-- testo libero cercato ("contiene") in nome + indirizzo dell'anagrafica, come nelle select del DDT.
		SET @ConDdt = ISNULL(@ConDdt, 0);
		-- Elenco DDT (Magazzino > DDT): solo i movimenti con un DDT emesso, cioè non ricevuto da un
		-- fornitore (sezionale R); le date della ricerca e l'ordinamento sono quelli del DDT
		SET @DdtEmessi = ISNULL(@DdtEmessi, 0);
		IF @DdtEmessi = 1 SET @ConDdt = 1;
		SET @DdtNumeroFornitore = NULLIF(LTRIM(RTRIM(@DdtNumeroFornitore)), '');
		SET @DdtMittente = NULLIF(LTRIM(RTRIM(@DdtMittente)), '');
		SET @DdtDestinatario = NULLIF(LTRIM(RTRIM(@DdtDestinatario)), '');
		SET @DdtTrasportatore = NULLIF(LTRIM(RTRIM(@DdtTrasportatore)), '');
		IF @ConDdt = 0
		BEGIN
			SET @DdtNumero = NULL;
			SET @DdtNumeroFornitore = NULL;
			SET @DdtMittente = NULL;
			SET @DdtDestinatario = NULL;
			SET @DdtTrasportatore = NULL;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			m.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			OperazioneNome = o.Nome,
			m.Data,
			m.Numero,
			RigheCount = ISNULL(r.RigheCount, 0) + ISNULL(re.RigheCount, 0),
			-- DDT del movimento (al massimo uno, garantito in SP: nessun vincolo UNIQUE); NULL se non c'è
			DdtNumero = d.Numero,
			DdtSezionale = d.Sezionale,
			DdtData = d.[Data],
			DdtSedeNome = d.SedeNome,
			DdtCausaleNome = d.CausaleNome,
			DdtDestinatarioNome = d.DestinatarioNome,
			m.Lock,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniMovimenti m
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblMagazziniOperazioni o ON m.IdOperazione = o.Id
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = m.Id) r
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = m.Id) re
			OUTER APPLY (
				SELECT TOP (1)
					dd.Id,
					dd.Numero,
					dd.NumeroFornitore,
					dd.Sezionale,
					dd.[Data],
					dd.IdMittente,
					dd.IdDestinatario,
					dd.IdTrasportatore,
					SedeNome = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
					CausaleNome = ca.Nome,
					DestinatarioNome = ds.NomeCompleto + ISNULL(' ' + ds.IndirizzoCompleto, '')
				FROM
					dbo.tblMagazziniDdt dd
					LEFT JOIN dbo.tblSedi sd ON dd.IdSede = sd.Id
					LEFT JOIN dbo.tblMagazziniCausali ca ON dd.IdCausale = ca.Id
					LEFT JOIN dbo.tblSedi ds ON dd.IdDestinatario = ds.Id
				WHERE dd.IdMovimento = m.Id
				ORDER BY dd.Id
			) d
		WHERE
			e.Id = @IdSessione
			AND m.Lock = 0
			AND (@IdOperazione IS NULL OR m.IdOperazione = @IdOperazione)
			AND (@DallaData IS NULL OR IIF(@DdtEmessi = 1, d.[Data], m.[Data]) >= @DallaData)
			AND (@AllaData IS NULL OR IIF(@DdtEmessi = 1, d.[Data], m.[Data]) <= @AllaData)
			AND (@ConDdt = 0 OR d.Id IS NOT NULL)
			AND (@DdtEmessi = 0 OR ISNULL(d.Sezionale, '') <> 'R')
			AND (@DdtNumero IS NULL OR d.Numero = @DdtNumero)
			AND (@DdtNumeroFornitore IS NULL OR d.NumeroFornitore LIKE '%' + @DdtNumeroFornitore + '%')
			AND (@DdtMittente IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sm WHERE sm.Id = d.IdMittente AND sm.NomeCompleto + ISNULL(' ' + sm.IndirizzoCompleto, '') LIKE '%' + @DdtMittente + '%'))
			AND (@DdtDestinatario IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sn WHERE sn.Id = d.IdDestinatario AND sn.NomeCompleto + ISNULL(' ' + sn.IndirizzoCompleto, '') LIKE '%' + @DdtDestinatario + '%'))
			AND (@DdtTrasportatore IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi st WHERE st.Id = d.IdTrasportatore AND st.NomeCompleto + ISNULL(' ' + st.IndirizzoCompleto, '') LIKE '%' + @DdtTrasportatore + '%'))
		ORDER BY
			IIF(@DdtEmessi = 1, d.[Data], m.[Data]) DESC,
			IIF(@DdtEmessi = 1, d.Numero, m.Numero) DESC,
			m.Numero DESC
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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
GO
