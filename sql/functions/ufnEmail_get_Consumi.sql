SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): quote e consumi del dominio. GiornoMax e MeseMax da tblDomini (0 se vuoti: con uno dei due a 0
-- le email agli utenti e ai clienti non partono), Giorno e Mese = email contate oggi e nel mese di calendario in corso
-- (tblEmailConsumi; le email di servizio non contano). Le email non usate non passano al mese dopo.
CREATE OR ALTER FUNCTION [dbo].[ufnEmail_get_Consumi] (
	@IdDominio CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		GiornoMax = ISNULL(d.EmailGiornoMax, 0),
		MeseMax = ISNULL(d.EmailMeseMax, 0),
		Giorno = ISNULL((
			SELECT c.Numero
			FROM dbo.tblEmailConsumi c
			WHERE
				c.IdDominio = d.Id
				AND c.Giorno = CAST(GETDATE() AS DATE)), 0),
		Mese = ISNULL((
			SELECT SUM(c.Numero)
			FROM dbo.tblEmailConsumi c
			WHERE
				c.IdDominio = d.Id
				AND c.Giorno >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
				AND c.Giorno <= CAST(GETDATE() AS DATE)), 0)
	FROM dbo.tblDomini d
	WHERE d.Id = @IdDominio
);
GO
