SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Data massima ammessa dall'applicazione: la stessa di Constants.SQL.MaxDate (Ecomatico.Core/Constants.cs).
-- Se cambia, va cambiata in tutti e due i punti
CREATE OR ALTER FUNCTION [dbo].[ufnDate_get_Max]()
RETURNS SMALLDATETIME
WITH SCHEMABINDING
AS
BEGIN
	RETURN '20501231';
END;
GO
