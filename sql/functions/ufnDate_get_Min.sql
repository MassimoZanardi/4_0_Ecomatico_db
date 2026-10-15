SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Data minima ammessa dall'applicazione: la stessa di Constants.SQL.MinDate (Ecomatico.Core/Constants.cs).
-- Se cambia, va cambiata in tutti e due i punti
CREATE OR ALTER FUNCTION [dbo].[ufnDate_get_Min]()
RETURNS SMALLDATETIME
WITH SCHEMABINDING
AS
BEGIN
	RETURN '20000101';
END;
GO
