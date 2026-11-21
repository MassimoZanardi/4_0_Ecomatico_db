-- Servizi: durata del servizio in minuti (tblServizi.Durata), facoltativa. NULL = durata non indicata: il servizio
-- occupa la sola cella dell'ora di inizio, come prima del 2026-11-21. Il servizio termina entro la mezzanotte del
-- giorno di inizio (controllo in uspServizi_upd e uspServiziAssegnati_upd), quindi la durata non supera le 24 ore.
-- Da installare prima delle SP uspServizi_* che leggono o scrivono la colonna. Si può rilanciare.

IF COL_LENGTH('dbo.tblServizi', 'Durata') IS NULL
	ALTER TABLE dbo.tblServizi ADD Durata INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_tblServizi_Durata')
	ALTER TABLE dbo.tblServizi WITH CHECK ADD CONSTRAINT CK_tblServizi_Durata CHECK (Durata > 0 AND Durata <= 1440);
GO
