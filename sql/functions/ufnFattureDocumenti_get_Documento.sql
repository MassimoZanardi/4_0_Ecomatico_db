SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Blocco "Cliente a cui fatturare": il documento @Id del modulo @IdModulo (RIF registrazione dei rifiuti, MAG
-- movimento di magazzino con il suo DDT), se la sessione lo vede (titolarità sulla sede del registro o del DDT).
-- Una riga al massimo. Serve alle SP uspFattureDocumenti_*, così permessi e dati di base del documento sono
-- letti nello stesso modo per ogni modulo.
-- IsFatturabile: registrazione di un'operazione fatturabile e non rettifica; DDT emesso di un movimento di
-- scarico con una causale fatturabile. Lock: 0 se il documento è confermato.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Documento (
	@Id CHAR(16),
	@IdModulo CHAR(3),
	@IdSessione CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		IdModulo = CAST('RIF' AS CHAR(3)),
		a.IdAzienda,
		Lock = CAST(a.Lock AS TINYINT),
		IsFatturabile = CAST(IIF(a.IsFatturabile = 1 AND a.IsRettifica = 0, 1, 0) AS BIT),
		a.IdFattura,
		a.IdClienteIndicato
	FROM
		dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
	WHERE @IdModulo = 'RIF'

	UNION ALL

	SELECT
		a.Id,
		IdModulo = CAST('MAG' AS CHAR(3)),
		a.IdAzienda,
		a.Lock,
		a.IsFatturabile,
		a.IdFattura,
		a.IdClienteIndicato
	FROM
		dbo.ufnImportiMagazzino_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeDdt = x.Id
	WHERE @IdModulo = 'MAG'
);
GO
