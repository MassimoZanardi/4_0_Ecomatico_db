SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stato dell'Allegato VII in italiano: NULL = bozza in Ecomatico, gli altri sono gli stati di DIWASS
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_StatoDescrizione] (
	@Stato VARCHAR(20))
RETURNS VARCHAR(50)
WITH SCHEMABINDING
AS
BEGIN
	RETURN CASE @Stato
		WHEN 'ANNOUNCED' THEN 'Annunciato'
		WHEN 'MOVING' THEN 'In viaggio'
		WHEN 'RECEIVED' THEN 'Ricevuto'
		WHEN 'COMPLETED' THEN 'Completato'
		WHEN 'CANCELLED' THEN 'Annullato'
		WHEN 'TAKE_BACK' THEN 'Ripresa'
		ELSE ISNULL(@Stato, 'Bozza')
	END;
END;
GO
