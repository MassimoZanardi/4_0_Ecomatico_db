/*
Deploy produzione 2026-09-22 - Modulo EoW: fix allocazioni percentuali,
giacenze rifiuti (esclusione quantita allocata a lotti EoW), blocco
registrazioni Materiale come figlie in una relazione, riordino menu.

Contenuto:
1. uspRifiutiRegistrazioni_ins_Relazione       - blocca Materiale come figlia (Id)
2. uspRifiutiRegistrazioni_ins_RelazioniTutte  - stesso blocco, inserimento massivo
3. uspRifiutiGiacenze_get_List                 - giacenza esclude quantita allocata a lotti EoW
4. uspRifiutiGiacenze_get_Carichi_List         - idem, vista drill-down Carichi
5. uspEoWAllocazioni_ins_Lotto                 - somma percentuali <= 100, priorita duplicata su Custom
6. uspEoWAllocazioni_esegui                    - somma percentuali <= 100, arrotondamento solo se = 100
7. tools/eow_menu_pos_swap.sql                 - sposta EoW sopra Rentri nel menu principale
*/

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Recupera l'operazione del padre e verifica che esista
		DECLARE @operazioneParent CHAR(1);
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT
			@operazioneParent = Operazione,
			@rentriIdentificativo = RentriIdentificativo,
			@rentriData = RentriData
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @IdParent;

		IF @operazioneParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione padre non trovata';
			GOTO BRANCH_END;
		END

		-- Una registrazione di produzione Materiale (causale K) è l'ultima fase del ciclo: può
		-- derivare da un precedente scarico (es. R, trattamento interno) come IdParent, ma non può
		-- mai comparire come @Id (figlio) - significherebbe che qualcos'altro la consuma a sua volta,
		-- cosa che non deve poter accadere.
		IF EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni WHERE Id = @Id AND IdMateriale IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di produzione Materiale è l''ultima fase del ciclo e non può essere associata come figlia di un''altra registrazione';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie (né come padre né come figlia) - difesa in profondità, la UI già la esclude
		-- dalle liste di selezione (uspRifiutiRegistrazioni_get_RegistrazioniDaAssociare_List)
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica IN (@Id, @IdParent))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		IF (
			SELECT COUNT(DISTINCT r.Id)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id IN (@Id, @IdParent)) < 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1) + 1
		FROM dbo.tblRifiutiRegistrazioniRelazioni s
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;
		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			VALUES
				(@Id, @IdParent, @operazioneParent, 0, @pos);

			-- Imposta la registrazione padre nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_RelazioniTutte]
	@IdSessione CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Calcolata una sola volta e riusata nei due controlli titolarità sottostanti,
		-- invece di richiamare la function separatamente per ciascuno
		DECLARE @sedi TABLE (Id CHAR(16) PRIMARY KEY);
		INSERT @sedi (Id)
		SELECT Id
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione);

		IF (
			SELECT COUNT(DISTINCT g.Id)
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro) = 0
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
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdParent
				AND (RentriIdentificativo IS NOT NULL OR RentriData IS NOT NULL)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie - difesa in profondità, la UI già nasconde la sezione per queste registrazioni
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni s
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;

		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		BEGIN TRANSACTION;

			--      QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0)
			INSERT dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			SELECT TOP(499 - @pos)
				r.Id,
				@IdParent,
				IIF(r.Operazione = 'C', 'S', 'C'),
				0,
				@pos + ROW_NUMBER() OVER (ORDER BY YEAR(r.[Data]), r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN (
					SELECT
						l.Id,
						Quantita = SUM(l.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
						INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
					WHERE
						p.Lock < 2
						AND mp.Quantita > 0
					GROUP BY l.Id
				) a ON r.Id = a.Id
			WHERE
				r.Lock = 0
				AND m.IdRegistro = @IdRegistro
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdEer = @IdEer
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdUnitaMisura = @IdUnitaMisura
					)
				AND
					(
					r.[Data] < @Data
					OR
						(
						r.[Data] = @Data
						AND r.Numero < @Numero
						)
					)
				AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
				AND m.Quantita - ISNULL(a.Quantita, 0) > 0 -- QuantitaResidua > 0
				-- Una registrazione di produzione Materiale è l'ultima fase del ciclo: non può mai
				-- diventare figlia (Id) di un'altra registrazione tramite questo inserimento massivo
				AND r.IdMateriale IS NULL
				AND NOT EXISTS ( SELECT 1 FROM dbo.tblRifiutiRegistrazioniRelazioni x WHERE x.Id = r.Id AND x.IdParent = @IdParent )
				-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
				-- proprie: non deve mai comparire come candidata da associare
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			ORDER BY YEAR(r.[Data]), r.Numero;

			SET @returnValue = @@ROWCOUNT;

			-- Imposta la registrazione nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;

		COMMIT TRANSACTION;

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

	SELECT ReturnValue = @returnValue;
END;

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('E', 'M', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve valere ''E'', ''M'' oppure ''T''';
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

		-- Titolarità: prima non esisteva alcun controllo che @IdRegistro appartenesse
		-- all'azienda della sessione — chiunque conoscesse un Id di registro poteva
		-- leggere le giacenze di un'altra azienda.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;
		IF @Data IS NULL SET @Data = GETDATE();

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- @Vista IN ('E', 'M'): solo righe Rifiuto prodotto/trattato, raggruppate per EER + stato fisico.
		-- @Vista = 'M': solo righe Materiale prodotto, raggruppate per materiale.
		-- @Vista = 'T': tutti i tipi, raggruppati per combinazione esatta di etichette (r.Etichette,
		-- JSON canonico già mantenuto da uspEtichette_upd/_del su tblRifiutiRegistrazioni.Etichette;
		-- NULL = bucket "Nessuna etichetta"). Le tre modalità condividono la stessa query: i rami
		-- P/T (Rifiuto prodotto/trattato) sono attivi per @Vista IN ('E','T'), il ramo M (Materiale)
		-- per @Vista IN ('M','T'); la chiave di GROUP BY usa CASE su @Vista, così la dimensione non
		-- richiesta collassa a una costante per ogni riga e non spezza ulteriormente i gruppi.
		-- StatoValore/StatoDescrizione (semaforo anzianità giacenza) sono derivati in un SELECT
		-- esterno alla CTE Giacenze, per non ripetere tre volte l'espressione DATEDIFF.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		-- Una registrazione Materiale non compare mai come Id (figlio) in tblRifiutiRegistrazioniRelazioni
		-- (blocco applicativo in uspRifiutiRegistrazioni_ins_Relazione/_ins_RelazioniTutte): l'unica causa
		-- di riduzione della sua giacenza è l'allocazione a un lotto EoW.
		QuantitaAllocataEoW AS (
			SELECT
				w.IdRegistrazione AS Id,
				Quantita = SUM(w.Quantita)
			FROM dbo.tblEoWLottiRifiutiRegistrazioni w
			GROUP BY w.IdRegistrazione
		),
		Giacenze AS (
			SELECT
				TipoCodice = 'P',
				Tipo = 'Rifiuto prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR m.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'T',
				Tipo = 'Rifiuto trattato',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'S'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR m.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'M',
				Tipo = 'Materiale prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				IdStatoFisico = NULL,
				StatoFisico = CASE WHEN @Vista IN ('E', 'M') THEN 'nd' END,
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAllocataEoW a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('M', 'T')
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0
		)
		SELECT
			TipoCodice, Tipo, Id, Nome, Descrizione, IdStatoFisico, StatoFisico, Etichette,
			Quantita, GiacenzaGiorni, MovimentiNumero,
			StatoValore = CASE
				WHEN GiacenzaGiorni > 365 THEN 2
				WHEN GiacenzaGiorni > 30  THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN GiacenzaGiorni > 365 THEN 'In giacenza da oltre un anno (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni > 30  THEN 'In giacenza da oltre 30 giorni (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni = 1   THEN 'In giacenza da 1 giorno'
				ELSE 'In giacenza da ' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni'
			END
		FROM Giacenze
		ORDER BY
			GiacenzaGiorni DESC,
			Nome,
			StatoFisico,
			Tipo,
			Etichette
		OFFSET @Offset ROWS
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
		THROW 50001, @returnMessage, 1
	END

END;
GO

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_Carichi_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Tipo CHAR(1) = NULL,
	@Id CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Etichette VARCHAR(2000) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @Etichette = NULLIF(LTRIM(RTRIM(@Etichette)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('E', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve valere ''E'' oppure ''T''';
			GOTO BRANCH_END;
		END
		-- @Tipo = NULL: vista "senza filtri", elenca tutti i carichi in giacenza a prescindere
		-- da tipo/EER/etichetta (raggiungibile direttamente dal menu Azioni). Se invece @Tipo è
		-- valorizzato (drill-down da una riga EER o Etichette), deve essere uno dei tre codici noti.
		IF @Tipo IS NOT NULL AND @Tipo NOT IN ('P', 'T', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve valere ''P'', ''T'' oppure ''M''';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NOT NULL AND @Vista = 'E' AND @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto con @Vista = ''E''';
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
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;
		IF @Data IS NULL SET @Data = GETDATE();

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Dettaglio dei singoli carichi (registrazioni) che compongono una riga aggregata
		-- di uspRifiutiGiacenze_get_List: stessa logica di quantità residua (Quantita -
		-- QuantitaAssegnata), stesse tre casistiche (Rifiuto prodotto/trattato, Materiale
		-- prodotto), ma senza aggregazione e filtrate sul gruppo scelto da chi ha cliccato
		-- la riga (@Vista = 'E' -> @Id [+@IdStatoFisico], @Vista = 'T' -> @Etichette).
		-- RowsCount e StatoValore/StatoDescrizione (semaforo anzianità giacenza) sono calcolati
		-- nel SELECT esterno alla CTE Carichi, non dentro ciascun ramo: altrimenti con @Tipo =
		-- NULL (nessun filtro, tutti i rami attivi) RowsCount riporterebbe solo il conteggio
		-- parziale del proprio ramo invece del totale.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		-- Una registrazione Materiale non compare mai come Id (figlio) in tblRifiutiRegistrazioniRelazioni
		-- (blocco applicativo in uspRifiutiRegistrazioni_ins_Relazione/_ins_RelazioniTutte): l'unica causa
		-- di riduzione della sua giacenza è l'allocazione a un lotto EoW.
		QuantitaAllocataEoW AS (
			SELECT
				w.IdRegistrazione AS Id,
				Quantita = SUM(w.Quantita)
			FROM dbo.tblEoWLottiRifiutiRegistrazioni w
			GROUP BY w.IdRegistrazione
		),
		Carichi AS (
			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = m.IdStatoFisico,
				StatoFisico = s.Nome,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'P')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR (e.Id = @Id AND m.IdStatoFisico = @IdStatoFisico))
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR e.Id LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)

			UNION ALL

			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = m.IdStatoFisico,
				StatoFisico = s.Nome,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'T')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'S'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR (ISNULL(e.Id, '') = ISNULL(@Id, '') AND ISNULL(m.IdStatoFisico, '') = ISNULL(@IdStatoFisico, '')))
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR ISNULL(e.Id, '') LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)

			UNION ALL

			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = NULL,
				StatoFisico = NULL,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAllocataEoW a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'M')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR e.Id = @Id)
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
		)
		SELECT
			Id, Numero, [Data], IdEer, EerNome, IdStatoFisico, StatoFisico, Etichette,
			IdUnitaMisura, Quantita, QuantitaAssegnata, QuantitaResidua, GiacenzaGiorni,
			StatoValore = CASE
				WHEN GiacenzaGiorni > 365 THEN 2
				WHEN GiacenzaGiorni > 30  THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN GiacenzaGiorni > 365 THEN 'In giacenza da oltre un anno (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni > 30  THEN 'In giacenza da oltre 30 giorni (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni = 1   THEN 'In giacenza da 1 giorno'
				ELSE 'In giacenza da ' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni'
			END,
			RowsCount = COUNT(*) OVER ()
		FROM Carichi
		ORDER BY GiacenzaGiorni DESC, EerNome, Numero
		OFFSET @Offset ROWS
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
		THROW 50001, @returnMessage, 1
	END

END;
GO

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_ins_Lotto
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Valore DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @idAllocazioneTipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@idAllocazioneTipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale dell'allocazione non è un campo proprio: si ricava dal primo lotto aggiunto
		-- e deve restare coerente con gli altri lotti già presenti (nessuna anagrafica/duplicazione
		-- separata, "un'Allocazione = un Materiale" è solo un vincolo, non uno stato memorizzato).
		DECLARE @idMaterialeAllocazione CHAR(2) = (
			SELECT TOP 1 l.IdMateriale
			FROM dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id
		);

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeAllocazione IS NOT NULL AND @idMaterialeLotto <> @idMaterialeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale degli altri lotti già presenti nell''allocazione';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id AND IdLotto = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo lotto è già presente nell''allocazione';
			GOTO BRANCH_END;
		END

		-- Validazione specifica per tipo (i valori dei tipi sono in tblEoWAllocazioniTipi: U=Lotto
		-- unico, P=Percentuale, C=Priorità/Capacità)
		IF @idAllocazioneTipo = 'U' AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'P' AND (@Valore IS NULL OR @Valore <= 0 OR @Valore > 100)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere maggiore di zero e non superiore a 100';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'P' AND @Valore + ISNULL((
				SELECT SUM(la.Valore)
				FROM dbo.tblEoWLottiAllocazioni la
				WHERE la.IdAllocazione = @Id
			), 0) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La somma delle percentuali dei lotti non può superare 100';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'C' AND (@Valore IS NULL OR @Valore <= 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La priorità deve essere un valore maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'C' AND EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni la
				WHERE la.IdAllocazione = @Id AND la.Valore = @Valore
			)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questa priorità è già assegnata a un altro lotto dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'U'
			SET @Valore = NULL;

		BEGIN TRANSACTION;
			INSERT dbo.tblEoWLottiAllocazioni (IdLotto, IdAllocazione, Valore)
			VALUES (@IdLotto, @Id, @Valore);
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_esegui
	@IdRegistrazione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL OR @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @idAllocazioneTipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@idAllocazioneTipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock = 0;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeAllocazione <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''allocazione selezionata non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'M'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo tipo di allocazione non supporta l''esecuzione automatica';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock di tutti i lotti coinvolti in un unico statement (ordine di acquisizione stabile,
			-- via index seek sulla PK, per ridurre il rischio di deadlock con esecuzioni concorrenti
			-- su insiemi di lotti sovrapposti), poi del movimento - stesso ordine di
			-- uspEoWLottiRifiutiRegistrazioni_ins.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = l.Id
			FROM dbo.tblEoWLotti l WITH (UPDLOCK, HOLDLOCK)
			WHERE l.Id IN (SELECT IdLotto FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
			ORDER BY l.Id;

			SELECT @lockRow = Id FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK) WHERE Id = @idMovimento;

			-- Righe di configurazione + quantità già attribuita ad ognuno dei lotti coinvolti, lette
			-- sotto lock (fonte unica di verità, nessun ricalcolo su dati stimati prima del lock)
			DECLARE @righe TABLE (IdLotto CHAR(16) PRIMARY KEY, Valore DECIMAL(18, 2) NULL, QuantitaMax DECIMAL(18, 2) NULL, QuantitaAttribuita DECIMAL(18, 2) NOT NULL);
			INSERT INTO @righe (IdLotto, Valore, QuantitaMax, QuantitaAttribuita)
			SELECT
				la.IdLotto,
				la.Valore,
				l.QuantitaMax,
				QuantitaAttribuita = ISNULL((SELECT SUM(r.Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni r WHERE r.IdLotto = la.IdLotto), 0)
			FROM
				dbo.tblEoWLottiAllocazioni la
				INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id;

			IF NOT EXISTS (SELECT 1 FROM @righe)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''allocazione non ha lotti configurati';
				GOTO BRANCH_END;
			END

			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita FROM dbo.tblRifiutiMovimenti WHERE Id = @idMovimento);
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione = @IdRegistrazione
			), 0);
			DECLARE @quantitaDaAllocare DECIMAL(18, 2) = ISNULL(@quantitaMovimento, 0) - @quantitaAttribuitaRegistrazione;

			IF @quantitaDaAllocare <= 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non c''è quantità residua da allocare per questa registrazione';
				GOTO BRANCH_END;
			END

			-- Piano di ripartizione calcolato per tipo (U = Lotto unico, P = Percentuale, C = Priorità/Capacità)
			DECLARE @piano TABLE (IdLotto CHAR(16) PRIMARY KEY, Quantita DECIMAL(18, 2) NOT NULL);

			IF @idAllocazioneTipo = 'U'
			BEGIN
				IF (SELECT COUNT(*) FROM @righe) <> 1
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''allocazione di tipo Lotto unico deve avere esattamente un lotto configurato';
					GOTO BRANCH_END;
				END

				INSERT INTO @piano (IdLotto, Quantita)
				SELECT IdLotto, @quantitaDaAllocare FROM @righe;
			END
			ELSE IF @idAllocazioneTipo = 'P'
			BEGIN
				DECLARE @sommaPercentuali DECIMAL(18, 2) = (SELECT SUM(ISNULL(Valore, 0)) FROM @righe);
				IF @sommaPercentuali > 100
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Le percentuali configurate non possono superare 100';
					GOTO BRANCH_END;
				END

				-- Arrotondamento a 2 decimali per riga. Il resto viene pareggiato sull'ultimo lotto (per
				-- Id) solo se le percentuali configurate coprono l'intero 100%: in quel caso il resto è
				-- puro errore di arrotondamento da correggere. Se invece sommano a meno di 100 (allocazione
				-- volutamente parziale, es. un solo lotto al 60%), il resto è quantità non allocata per
				-- scelta e deve restare tale, non va scaricato sull'ultimo lotto.
				INSERT INTO @piano (IdLotto, Quantita)
				SELECT
					IdLotto,
					Quantita = ROUND(@quantitaDaAllocare * Valore / 100.0, 2)
				FROM @righe;

				IF @sommaPercentuali = 100
				BEGIN
					DECLARE @idUltimoLotto CHAR(16) = (SELECT TOP 1 IdLotto FROM @righe ORDER BY IdLotto DESC);
					DECLARE @resto DECIMAL(18, 2) = @quantitaDaAllocare - (SELECT SUM(Quantita) FROM @piano);
					UPDATE @piano SET Quantita = Quantita + @resto WHERE IdLotto = @idUltimoLotto;
				END
			END
			ELSE IF @idAllocazioneTipo = 'C'
			BEGIN
				-- Ripartizione greedy per priorità (Valore crescente = priorità più alta): iterazione
				-- riga per riga, nessun pattern set-based equivalente per un bin-packing sequenziale.
				DECLARE @rimanente DECIMAL(18, 2) = @quantitaDaAllocare;
				DECLARE @curIdLotto CHAR(16), @curQuantitaMax DECIMAL(18, 2), @curQuantitaAttribuita DECIMAL(18, 2);

				DECLARE curRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT IdLotto, QuantitaMax, QuantitaAttribuita
					FROM @righe
					ORDER BY ISNULL(Valore, 999999999), IdLotto;

				OPEN curRighe;
				FETCH NEXT FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAttribuita;
				WHILE @@FETCH_STATUS = 0 AND @rimanente > 0
				BEGIN
					DECLARE @capacitaResidua DECIMAL(18, 2) = CASE
						WHEN @curQuantitaMax IS NULL THEN @rimanente
						ELSE @curQuantitaMax - @curQuantitaAttribuita
					END;
					IF @capacitaResidua > 0
					BEGIN
						DECLARE @presoQui DECIMAL(18, 2) = IIF(@capacitaResidua < @rimanente, @capacitaResidua, @rimanente);
						INSERT INTO @piano (IdLotto, Quantita) VALUES (@curIdLotto, @presoQui);
						SET @rimanente -= @presoQui;
					END
					FETCH NEXT FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAttribuita;
				END
				CLOSE curRighe;
				DEALLOCATE curRighe;

				IF @rimanente > 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'La capacità configurata nei lotti è insufficiente per la quantità da allocare';
					GOTO BRANCH_END;
				END
			END

			-- Verifica finale capacità per riga (ridondante per U/P dove già implicito, ma protegge
			-- comunque da una configurazione QuantitaMax incoerente) e upsert nella tabella risultato
			IF EXISTS (
				SELECT 1
				FROM @piano p INNER JOIN @righe r ON p.IdLotto = r.IdLotto
				WHERE r.QuantitaMax IS NOT NULL AND r.QuantitaAttribuita + p.Quantita > r.QuantitaMax
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità calcolata supera la capacità residua di uno o più lotti';
				GOTO BRANCH_END;
			END

			MERGE dbo.tblEoWLottiRifiutiRegistrazioni AS target
			USING @piano AS source
				ON target.IdRegistrazione = @IdRegistrazione AND target.IdLotto = source.IdLotto
			WHEN MATCHED THEN
				UPDATE SET Quantita = target.Quantita + source.Quantita
			WHEN NOT MATCHED THEN
				INSERT (IdRegistrazione, IdLotto, Quantita)
				VALUES (@IdRegistrazione, source.IdLotto, source.Quantita);

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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

GO

SET NOCOUNT ON;

-- Sposta EoW sopra Rentri (tra Rifiuti e Rentri) nel menu principale.
-- Prima: Rifiuti(4), Rentri(5), EoW(6), Impostazioni(7)
-- Dopo:  Rifiuti(4), EoW(5), Rentri(6), Impostazioni(7)
UPDATE dbo.tblMenu
SET Pos = CASE Id WHEN 'AH0' THEN 5 WHEN 'AG0' THEN 6 END
WHERE Id IN ('AH0', 'AG0');

GO
