CREATE OR ALTER PROCEDURE [dbo].[uspSedi_get]
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

		IF EXISTS (SELECT 1
		FROM dbo.tblSedi
		WHERE
			Id = @Id
			AND InternaEsterna = 'I'
		)
		BEGIN
			IF NOT EXISTS (
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
		ELSE
		BEGIN
			DECLARE @lockCheck INT = (SELECT Lock
			FROM dbo.tblSedi
			WHERE Id = @Id);

			IF @lockCheck = 0
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

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblSedi
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sede non trovata';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);

		SELECT
			s.Id,
			IdParent = ISNULL(s.IdParent, REPLICATE('0', 16)),
			IdAziendaInterna = ISNULL(s.IdAziendaInterna, REPLICATE('0', 16)),
			IdTipo = ISNULL(s.IdTipo, 'L'),
			s.InternaEsterna,
			Nome = ISNULL(s.Nome, ''),
			Cognome = ISNULL(s.Cognome, ''),
			PartitaIva = ISNULL(s.PartitaIva, ''),
			CodiceFiscale = ISNULL(s.CodiceFiscale, ''),
			IndirizzoCompleto = ISNULL(s.IndirizzoCompleto, ''),
			NomeCompleto = ISNULL(s.NomeCompleto, ''),
			Note = ISNULL(s.Note, ''),
			IdComune = ISNULL(ind.IdComune, REPLICATE('0', 6)),
			IdNazione = ISNULL(ind.IdNazione, '380'),
			CAP = ISNULL(ind.CAP, ''),
			Indirizzo = ISNULL(ind.Indirizzo, ''),
			NumeroCivico = ISNULL(ind.NumeroCivico, ''),
			Localita = ISNULL(ind.Localita, ''),
			Telefono0 = ISNULL(t0.Valore, ''),
			Telefono1 = ISNULL(t1.Valore, ''),
			Telefono2 = ISNULL(t2.Valore, ''),
			Email0 = ISNULL(m0.Valore, ''),
			Email1 = ISNULL(m1.Valore, ''),
			Email2 = ISNULL(m2.Valore, ''),
			Disabilitata = ISNULL(s.Disabilitata, 0),
			-- Se la sede è genitore (referenziata come IdParent da altre) e nessuno dei suoi figli
			-- ha UnitaLocale=true, la si mostra come true a prescindere dal valore salvato: sana a
			-- video l'invariante "sempre almeno un true nel gruppo" anche per dati legacy non
			-- ancora passati da uspSedi_upd (che invece persiste la stessa regola).
			-- Lock = 0 su entrambe le EXISTS: un figlio cancellato non deve contare né come "ha
			-- figli" né il suo eventuale UnitaLocale=1 residuo deve essere considerato valido.
			UnitaLocale = CASE
				WHEN EXISTS (SELECT 1
				FROM dbo.tblSedi c
				WHERE
					c.IdParent = s.Id
					AND c.Lock = 0
				)
				 AND NOT EXISTS (SELECT 1
				 FROM dbo.tblSedi c
				 WHERE
					 c.IdParent = s.Id
					 AND c.UnitaLocale = 1
					 AND c.Lock = 0
				 )
					THEN CAST(1 AS BIT)
				ELSE CAST(ISNULL(s.UnitaLocale, 0) AS BIT)
				END,
			Condivisa = CAST(IIF(c.Id IS NULL, 0, 1) AS BIT),
			CondivisaDaArea = ISNULL(c.Area, ''),
			CondivisaDaAltri = CAST(IIF(@idAzienda = s.IdAziendaInterna, 0, 1) AS BIT),
			s.Lock
		FROM
			dbo.tblSedi s
			LEFT JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
			LEFT JOIN dbo.tblIndirizzi ind ON si.IdIndirizzo = ind.Id
			LEFT JOIN dbo.tblSediRecapiti t0 ON s.Id = t0.Id AND t0.IdRecapito = 'T0'
			LEFT JOIN dbo.tblSediRecapiti t1 ON s.Id = t1.Id AND t1.IdRecapito = 'T1'
			LEFT JOIN dbo.tblSediRecapiti t2 ON s.Id = t2.Id AND t2.IdRecapito = 'T2'
			LEFT JOIN dbo.tblSediRecapiti m0 ON s.Id = m0.Id AND m0.IdRecapito = 'M0'
			LEFT JOIN dbo.tblSediRecapiti m1 ON s.Id = m1.Id AND m1.IdRecapito = 'M1'
			LEFT JOIN dbo.tblSediRecapiti m2 ON s.Id = m2.Id AND m2.IdRecapito = 'M2'
			OUTER APPLY (
				SELECT TOP 1
					ae.Id,
					Area = a.Nome
				FROM dbo.tblAreeOsepe ae
				INNER JOIN dbo.tblAree a ON ae.Id = a.Id
				WHERE
					a.Lock = 0
					AND (ae.IdOsepe = s.Id OR ae.IdOsepe = s.IdParent)
			) c
		WHERE
			s.Id = @Id
			AND s.Lock <= 2;

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




