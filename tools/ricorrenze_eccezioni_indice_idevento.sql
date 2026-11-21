-- Indice sull'occorrenza modificata (tblRicorrenzeEccezioni.IdEvento, il sostituto dell'eccezione): lo cercano per ogni
-- riga gli elenchi di Servizi e Scadenze (serie dell'occorrenza modificata, "Tutta la serie") e uspEventi_get_Ricorrenza.
-- Prova del 2026-11-21 con 15.000 servizi e 300 serie: Elenco di un anno da 13,6 s a 3,1 s, di un mese da 1,8 s a 0,8 s
-- (poi la paginazione sulle chiavi in uspServizi_get_List). Si può rilanciare.

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RicorrenzeEccezioni_IdEvento' AND object_id = OBJECT_ID('dbo.tblRicorrenzeEccezioni'))
	CREATE NONCLUSTERED INDEX IX_RicorrenzeEccezioni_IdEvento ON dbo.tblRicorrenzeEccezioni (IdEvento) INCLUDE (Lock);
GO
