-- Formulario unico per l'attività di pulizia manutentiva delle reti fognarie (art. 230, comma 5, D.Lgs. 152/2006),
-- vidimato su Vi.Vi.FIR e non sul RENTRI. Al RENTRI va solo la registrazione di carico (operazione P, codice RE).
-- 1) colonna tblRifiutiOperazioni.IsFormularioUnico e le due operazioni del formulario unico, create se mancano, le sole con
--    IsFormularioUnico = 1: P "Carico di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)"
--    (carico, codice RE: il rifiuto va al deposito temporaneo dello spurghista, riquadro 5.1 del modello) e Q "Trasporto
--    di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)" (carico e scarico, codice T*aT: il
--    rifiuto va direttamente all'impianto, riquadro 5.2);
-- 2) P e Q con IsFormulario = 1: Rifiuti > Formulari le propone e il formulario condivide il movimento con la
--    registrazione, come per lo scarico S (tblRifiutiFormulari, tblRifiutiFormulariTrasportiTerresti);
-- 3) tabella tblRifiutiMovimentiSediProduzione: indirizzi di intervento del formulario (al massimo 10, come le righe
--    del modello Albo-2022-A), con la quantità stimata, e indice per sede (controlli sulla cancellazione delle sedi);
-- 4) P configurata come F (l'altro carico RE) e Q come T (l'altro T*aT): stessi tipi di registro
--    (tblRifiutiOperazioniRegistriTipi) e stesse operazioni di scarico che ne prelevano la quantità (tblRifiutiOperazioniRelazioni:
--    R e S per la P, nessuna per la Q);
-- 5) modulo VVF (Vi.Vi.FIR), che richiede il modulo Rifiuti: senza VVF sul dominio P e Q non si propongono;
-- 6) colonna tblRifiutiMovimenti.ViviFirVidimato (numero vidimato su Vi.Vi.FIR).
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF COL_LENGTH('dbo.tblRifiutiOperazioni', 'IsFormularioUnico') IS NULL
	ALTER TABLE dbo.tblRifiutiOperazioni ADD IsFormularioUnico BIT NULL;
GO
IF NOT EXISTS (SELECT 1
FROM dbo.tblRifiutiOperazioni
WHERE Id = 'P')
	INSERT dbo.tblRifiutiOperazioni
		(Id, Operazione, Codice, Nome, IsRentri, ProduttoreSede, TrasportatoreSede, DestinatarioSede, IntermediarioSede, Pos,
		OperazioneAuto, IsFormulario, IsIntegrazioneFir, IsProduttore, IsTrasportatore, IsDestinatario, IsIntermediario,
		IsAttivitaRs, IsEsito, IsAttivitaProvenienza, IsMateriale, IsStoccaggioIstantaneo, IsRentriAccettazione, IsFatturabile,
		IsFormularioUnico)
	VALUES
		('P', 'C', 'RE', 'Carico di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)', 1, 1, 1, 0, 0, 11,
		NULL, 1, 1, 1, 1, 1, 0,
		0, 0, 1, 0, 0, 0, 0,
		1);

IF NOT EXISTS (SELECT 1
FROM dbo.tblRifiutiOperazioni
WHERE Id = 'Q')
	INSERT dbo.tblRifiutiOperazioni
		(Id, Operazione, Codice, Nome, IsRentri, ProduttoreSede, TrasportatoreSede, DestinatarioSede, IntermediarioSede, Pos,
		OperazioneAuto, IsFormulario, IsIntegrazioneFir, IsProduttore, IsTrasportatore, IsDestinatario, IsIntermediario,
		IsAttivitaRs, IsEsito, IsAttivitaProvenienza, IsMateriale, IsStoccaggioIstantaneo, IsRentriAccettazione, IsFatturabile,
		IsFormularioUnico)
	VALUES
		('Q', 'X', 'T*aT', 'Trasporto di rifiuto prodotto in più unità locali (per attività di pulizia manutentiva)', 1, 0, 1, 0, 0, 12,
		NULL, 1, 1, 1, 1, 1, 0,
		1, 1, 0, 0, 0, 0, 0,
		1);
GO
UPDATE dbo.tblRifiutiOperazioni
SET IsFormularioUnico = IIF(Id IN ('P', 'Q'), 1, 0)
WHERE ISNULL(IsFormularioUnico, 2) <> IIF(Id IN ('P', 'Q'), 1, 0);

UPDATE dbo.tblRifiutiOperazioni
SET IsFormulario = 1
WHERE
	Id IN ('P', 'Q')
	AND ISNULL(IsFormulario, 0) = 0;
GO
IF OBJECT_ID('dbo.tblRifiutiMovimentiSediProduzione', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblRifiutiMovimentiSediProduzione (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdSede CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		Quantita DECIMAL(18, 2) NULL,
		Pos TINYINT NULL,
		CONSTRAINT PK_tblRifiutiMovimentiSediProduzione PRIMARY KEY CLUSTERED (Id ASC, IdSede ASC)
	);

	ALTER TABLE dbo.tblRifiutiMovimentiSediProduzione WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiSediProduzione_tblRifiutiMovimenti
		FOREIGN KEY (Id) REFERENCES dbo.tblRifiutiMovimenti (Id);
	ALTER TABLE dbo.tblRifiutiMovimentiSediProduzione WITH CHECK ADD CONSTRAINT FK_tblRifiutiMovimentiSediProduzione_tblSedi
		FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
END
GO
IF NOT EXISTS (SELECT 1
FROM sys.indexes
WHERE
	object_id = OBJECT_ID('dbo.tblRifiutiMovimentiSediProduzione')
	AND name = 'IX_RifiutiMovimentiSediProduzione_IdSede'
)
	CREATE NONCLUSTERED INDEX IX_RifiutiMovimentiSediProduzione_IdSede ON dbo.tblRifiutiMovimentiSediProduzione (IdSede ASC);
GO
INSERT dbo.tblRifiutiOperazioniRegistriTipi (Id, IdTipo)
SELECT x.Id, f.IdTipo
FROM
	(VALUES ('P', 'F'), ('Q', 'T')) x (Id, IdModello)
	INNER JOIN dbo.tblRifiutiOperazioniRegistriTipi f ON f.Id = x.IdModello
WHERE NOT EXISTS (SELECT 1
FROM dbo.tblRifiutiOperazioniRegistriTipi p
WHERE
	p.Id = x.Id
	AND p.IdTipo = f.IdTipo
);

INSERT dbo.tblRifiutiOperazioniRelazioni (Id, IdParent)
SELECT f.Id, 'P'
FROM dbo.tblRifiutiOperazioniRelazioni f
WHERE
	f.IdParent = 'F'
	AND NOT EXISTS (SELECT 1
	FROM dbo.tblRifiutiOperazioniRelazioni p
	WHERE
		p.Id = f.Id
		AND p.IdParent = 'P'
	);
GO
IF NOT EXISTS (SELECT 1
FROM dbo.tblModuli
WHERE Id = 'VVF')
	INSERT dbo.tblModuli (Id, Nome, Attivo)
	VALUES ('VVF', 'Vi.Vi.FIR', 1);

IF NOT EXISTS (SELECT 1
FROM dbo.tblModuliRelazioni
WHERE
	Id = 'RIF'
	AND IdParent = 'VVF'
)
	INSERT dbo.tblModuliRelazioni (Id, IdParent)
	VALUES ('RIF', 'VVF');
GO
-- 6) colonna tblRifiutiMovimenti.ViviFirVidimato: il numero del formulario unico è stato vidimato su Vi.Vi.FIR
--    (Rifiuti > Formulari, "Vi.Vi.FIR - Vidima formulario unico"): blocca il numero e colora di verde l'icona degli elenchi
IF COL_LENGTH('dbo.tblRifiutiMovimenti', 'ViviFirVidimato') IS NULL
	ALTER TABLE dbo.tblRifiutiMovimenti ADD ViviFirVidimato BIT NULL;
GO
