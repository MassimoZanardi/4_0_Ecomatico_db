SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): mette in coda un'email (tblEmail, stato D). Una riga = un messaggio a un indirizzo. Non controlla
-- permessi: la chiamano le SP che preparano le email (avvisi, comunicazioni al cliente, email di prova, avvisi sulla
-- quota), che hanno gia' fatto i loro controlli. L'invio e la quota li gestisce uspEmail_upd_Prendi.
-- @Tipo: S di servizio (fuori quota), U avviso a un utente, C comunicazione al cliente.
-- L'Id non passa da tblId (nessuna sessione: la coda si riempie anche dall'operazione pianificata); la chiave
-- primaria esclude comunque i doppioni.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_ins]
	@IdDominio CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@IdUtente CHAR(16) = NULL,
	@Indirizzo VARCHAR(250) = NULL,
	@Mittente NVARCHAR(100) = NULL,
	@RispondiA VARCHAR(250) = NULL,
	@Oggetto NVARCHAR(250) = NULL,
	@Contenuto NVARCHAR(MAX) = NULL,
	@Id CHAR(16) = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdDominio = NULLIF(LTRIM(RTRIM(@IdDominio)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @Indirizzo = NULLIF(LOWER(LTRIM(RTRIM(@Indirizzo))), '');
		SET @Mittente = NULLIF(LTRIM(RTRIM(@Mittente)), '');
		SET @RispondiA = NULLIF(LOWER(LTRIM(RTRIM(@RispondiA))), '');
		SET @Oggetto = NULLIF(LTRIM(RTRIM(@Oggetto)), '');
		SET @Id = NULL;

		IF @IdDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdDominio non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('S', 'U', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere S, U o C';
			GOTO BRANCH_END;
		END
		-- Un solo indirizzo, con la forma minima nome@dominio.estensione: il servizio di invio fa il controllo completo
		IF @Indirizzo IS NULL OR @Indirizzo LIKE '%[ ;,]%' OR @Indirizzo NOT LIKE '_%@_%._%'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indirizzo email non valido';
			GOTO BRANCH_END;
		END
		IF @Oggetto IS NULL OR NULLIF(LTRIM(RTRIM(@Contenuto)), '') IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Oggetto e contenuto dell''email non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblDomini WHERE Id = @IdDominio)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dominio non trovato';
			GOTO BRANCH_END;
		END

		SET @Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

		INSERT INTO dbo.tblEmail
			(Id, IdDominio, Tipo, IdUtente, Indirizzo, Mittente, RispondiA, Oggetto, Contenuto, IdStato)
		VALUES
			(@Id, @IdDominio, @Tipo, @IdUtente, @Indirizzo, @Mittente, @RispondiA, @Oggetto, @Contenuto, 'D');

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
