SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: le importazioni dei registri dell'azienda interna corrente della sessione, in preparazione
-- (anteprima, Stato P) ed eseguite (Stato E), con il registro, l'account di chi le ha fatte e i conteggi. Usata
-- dall'elenco e dall'esportazione, che devono vedere le stesse righe (uspRentriImportazioni_get_List,
-- uspRentriImportazioni_get_Esportazione). Senza azienda nel contesto nessuna riga.
-- Data = data dell'esecuzione, o della preparazione per un'anteprima: è quella del filtro e dell'ordine.
-- UtenteAccount = email di accesso, anche di un utente cancellato (cancellazione logica, Lock = 4), con l'indicazione.
-- Importate = registrazioni create dall'importazione (azione I con l'Id della registrazione): solo per le eseguite.
-- @Search cerca nel nome del registro; @Stato: P, E o NULL tutte.
CREATE OR ALTER FUNCTION dbo.ufnRentriImportazioni_get_Elenco
(
	@IdSessione CHAR(16),
	@Search VARCHAR(50),
	@Stato CHAR(1),
	@DallaData DATE,
	@AllaData DATE
)
RETURNS TABLE
AS
RETURN
(
	SELECT
		m.Id,
		m.Stato,
		m.IdRegistro,
		RegistroNome = g.Nome,
		m.Modalita,
		m.DalAnno,
		m.DalNumero,
		m.AlAnno,
		m.AlNumero,
		m.FinoAlPrimoProblema,
		m.DataCreazione,
		m.DataEsecuzione,
		Data = ISNULL(m.DataEsecuzione, m.DataCreazione),
		UtenteAccount = CASE WHEN u.Email IS NULL THEN NULL WHEN u.Lock = 4 THEN CONCAT(u.Email, ' (utente cancellato)') ELSE u.Email END,
		Movimenti = s.Movimenti,
		Importate = IIF(m.Stato = 'E', s.Importate, NULL)
	FROM
		dbo.tblRentriImportazioni m
		INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		INNER JOIN dbo.tblSessioni e ON e.Id = @IdSessione
		LEFT JOIN dbo.tblUtenti u ON m.IdUtente = u.Id
		CROSS APPLY (
			SELECT
				Movimenti = COUNT(*),
				Importate = ISNULL(SUM(IIF(x.Azione = 'I' AND x.IdRegistrazione IS NOT NULL, 1, 0)), 0)
			FROM dbo.tblRentriImportazioniMovimenti x
			WHERE x.IdImportazione = m.Id
		) s
	WHERE
		i.IdAziendaInterna = e.IdAzienda
		AND m.Stato IN ('P', 'E')
		AND (@Stato IS NULL OR m.Stato = @Stato)
		AND (@Search IS NULL OR g.Nome LIKE '%' + @Search + '%')
		AND (@DallaData IS NULL OR ISNULL(m.DataEsecuzione, m.DataCreazione) >= @DallaData)
		AND (@AllaData IS NULL OR ISNULL(m.DataEsecuzione, m.DataCreazione) < DATEADD(DAY, 1, @AllaData))
);
GO
