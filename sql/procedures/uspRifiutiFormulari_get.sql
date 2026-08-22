CREATE PROCEDURE [dbo].[uspRifiutiFormulari_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del
 formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

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
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = f.Id,
			IdMovimento = m.Id,
			m.IdRegistro,
			IdOperazione = ISNULL(m.IdOperazione, '0'),
			OperazioneNome = ISNULL(o.Nome, ''),
			IdEer = ISNULL(m.IdEer, '000000'),
			IdProvenienza = ISNULL(m.IdProvenienza, 'S'),
			IdStatoFisico = ISNULL(m.IdStatoFisico, '0'),
			IdAttivitaRs = ISNULL(m.IdAttivita, '00'),
			VerificatoInPartenza = ISNULL(f.VerificatoInPartenza, 0),

			IsRegistrazioneAssociata = CAST(IIF(r.Id IS NOT NULL AND r.Lock < 2, 1, 0) AS BIT),
			RegistrazioneData = ISNULL(r.[Data], GETDATE()),
			RegistrazioneNumero = ISNULL(r.Numero, 0),

			-- Dati formulario
			FormularioNumero = ISNULL(m.FormularioNumero, ''),
			FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
			IdAdr = ISNULL(f.IdAdr, '00'),
			NumeroOnu = ISNULL(f.NumeroOnu, ''),
			TrasportoAdr = ISNULL(f.TrasportoAdr, 0),
			AdrNote = ISNULL(f.AdrNote, ''),
			IdImballo = ISNULL(f.IdImballo, '00'),
			Quantita = ISNULL(m.Quantita, 0),
			IdUnitaMisura = ISNULL(m.IdUnitaMisura, 'KG'),
			ColliNumero = ISNULL(f.ColliNumero, ''),
			AllaRinfusa = ISNULL(f.AllaRinfusa, 0),

			IdAnalisiTipo = ISNULL(f.IdAnalisiTipo, '0'),
			AnalisiNumero = ISNULL(f.AnalisiNumero, ''),
			AnalisiData = f.AnalisiData,

			FormularioNote = ISNULL(f.Note, ''),
			UtenteNote = ISNULL(m.Note, ''),

			-- Autorizzazioni
			IdAutorizzazioneProduttoreDetentore = ISNULL(mp.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneDestinatario = ISNULL(md.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore1 = ISNULL(mt1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore2 = ISNULL(mt2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore3 = ISNULL(mt3.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario1 = ISNULL(mi1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario2 = ISNULL(mi2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario3 = ISNULL(mi3.IdAutorizzazione, REPLICATE('0', 16)),

			LuogoDiProduzione = ISNULL(f.LuogoDiProduzione, 0),
			Detentore = ISNULL(f.Detentore, 0),

			-- Trasporti
			DataInizioTrasporto = m.DataInizioTrasporto,
			IdTipoTrasporto1 = ISNULL(mt1.IdTipo, 'G'),
			IdTipoTrasporto2 = ISNULL(mt2.IdTipo, 'G'),
			IdTipoTrasporto3 = ISNULL(mt3.IdTipo, 'G'),

			-- Trasporto terreste (G)
			TargaMotrice = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.TargaMotrice, '') ELSE '' END,
			TargaRimorchio = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.TargaRimorchio, '') ELSE '' END,
			ConducenteNome = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.ConducenteNome, '') ELSE '' END,
			ConducenteCognome = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.ConducenteCognome, '') ELSE '' END,
			Percorso = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.Percorso, '') ELSE '' END,
			RimorchioPrecedente = CASE WHEN mt1.IdTipo = 'G' THEN ISNULL(fg.RimorchioPrecedente, 0) ELSE 0 END,

			-- Trasporto marittimo (N)
			Nave = CASE WHEN mt1.IdTipo = 'N' THEN ISNULL(fn.Nave, '') ELSE '' END,
			Imdg = CASE WHEN mt1.IdTipo = 'N' THEN ISNULL(fn.Imdg, 0) ELSE 0 END,

			-- Trasporto ferroviario (T)
			Treno = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Treno, '') ELSE '' END,
			Tratta = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Tratta, '') ELSE '' END,
			Rid = CASE WHEN mt1.IdTipo = 'T' THEN ISNULL(ft.Rid, 0) ELSE 0 END,

			Lock = f.Lock
		FROM
			dbo.tblRifiutiFormulari f
		INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
		LEFT JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			-- Produttori
		LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
			-- Destinatari
		LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			-- Trasportatori
		LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
		LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
		LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt3 ON m.Id = mt3.Id AND mt3.Pos = 2
			-- Intermediari
		LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
		LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
		LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi3 ON m.Id = mi3.Id AND mi3.Pos = 2
			-- Trasporti
		LEFT JOIN dbo.tblRifiutiFormulariTrasportiTerresti fg ON f.Id = fg.Id
		LEFT JOIN dbo.tblRifiutiFormulariTrasportiMarittimi fn ON f.Id = fn.Id
		LEFT JOIN dbo.tblRifiutiFormulariTrasportiFerroviari ft ON f.Id = ft.Id
		WHERE
			f.Id = @Id
			AND f.Lock <= 2;

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
