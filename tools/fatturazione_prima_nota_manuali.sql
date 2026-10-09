-- Fatturazione > Prima nota, saldo iniziale e movimenti manuali.
-- tblBancheCasse.SaldoIniziale e DataSaldoIniziale: saldo della banca o cassa all'inizio del giorno indicato; il
-- saldo progressivo della prima nota parte da lì (i movimenti precedenti non lo modificano).
-- tblPagamenti.IdConto: conto facoltativo di un movimento manuale, cioè di un pagamento non legato a rate di
-- fatture (nessuna riga in tblFattureRatePagamenti): spese bancarie, prelievi, versamenti, stipendi.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già le colonne.
SET NOCOUNT ON;
GO
IF COL_LENGTH('dbo.tblBancheCasse', 'SaldoIniziale') IS NULL
	ALTER TABLE dbo.tblBancheCasse ADD SaldoIniziale DECIMAL(18, 2) NULL;
IF COL_LENGTH('dbo.tblBancheCasse', 'DataSaldoIniziale') IS NULL
	ALTER TABLE dbo.tblBancheCasse ADD DataSaldoIniziale DATE NULL;
IF COL_LENGTH('dbo.tblPagamenti', 'IdConto') IS NULL
	ALTER TABLE dbo.tblPagamenti ADD IdConto CHAR(16) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblPagamenti_tblFattureConti')
BEGIN
	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblFattureConti FOREIGN KEY (IdConto) REFERENCES dbo.tblFattureConti (Id);
	ALTER TABLE dbo.tblPagamenti CHECK CONSTRAINT FK_tblPagamenti_tblFattureConti;
END
GO
