/*
	Deploy produzione - 2026-09-11 - Rimozione colonna residua tblRifiutiRegistri.ConservazioneSostitutiva

	Motivazione: durante lo sviluppo del campo tblRifiutiRegistri.ConservazioniXfirMax e' emersa,
	sullo stesso DB dev, una colonna bit "ConservazioneSostitutiva" mai referenziata da alcuna SP/vista
	ne' da alcun codice applicativo. Il commit 3bf1e5a ("Conservazione sostitutiva del registro: dati
	unicamente su hub 1_0_rentri", gia' in produzione - antenato del tag deployed-prod) documenta
	esplicitamente che questa colonna (insieme a ConservazioneSostitutivaRagioneSociale/PartitaIva/
	Email, spostate sull'hub [1_0_rentri]..tblRegistri) era diventata ridondante e "puo' essere
	droppata (fuori da questo script)" - il drop pero' non era mai stato eseguito. Le 3 colonne
	sorelle (RagioneSociale/PartitaIva/Email) risultano gia' assenti sul DB dev: solo
	ConservazioneSostitutiva e' rimasta.

	Verifica di non utilizzo eseguita su questo repo: nessun riferimento a "g.ConservazioneSostitutiva"
	(alias standard di tblRifiutiRegistri) in nessuna SP/vista attiva in sql/procedures o sql/views.
	Le uniche occorrenze del nome "ConservazioneSostitutiva" nel codice riguardano la colonna omonima
	- ma distinta - su tblRifiutiRegistrazioni (flusso di blocco conservazione sostitutiva sulle
	singole registrazioni, tuttora attivo: uspRifiutiRegistrazioni_get/_upd/_del,
	uspRentriRegistrazioni_upd_ConservazioneBlocco/_upd_Esito/_upd_PresaVisione).

	Contenuto di questo script (solo 4_0_ecomatico):
	1) ALTER TABLE dbo.tblRifiutiRegistri DROP COLUMN ConservazioneSostitutiva, guardato con IF EXISTS
	   per restare idempotente anche se lo script viene rieseguito per errore dopo che il passo e'
	   gia' stato applicato.

	Verificato su DB dev: colonna rimossa senza errori, nessun default/check constraint presente,
	nessuna dipendenza in sys.dm_sql_referencing_entities('dbo.tblRifiutiRegistri','OBJECT') sulla
	colonna specifica (solo dipendenze sulla tabella nel suo complesso, per altre colonne).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-11_registri_drop_conservazionesostitutiva.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/
--------------------------------------------------------------------------------
-- 1) dbo.tblRifiutiRegistri: drop colonna residua (idempotente)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiRegistri') AND name = 'ConservazioneSostitutiva')
BEGIN
	EXEC(N'ALTER TABLE dbo.tblRifiutiRegistri DROP COLUMN ConservazioneSostitutiva;');
END
GO
