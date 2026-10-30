SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Ruoli dell'azienda in un Allegato VII (tblDiwassAllegatiVii.Ruoli: O, P, D, I, T) in parole, nell'ordine del documento.
-- Nullo = documento creato in Ecomatico e non ancora letto da DIWASS: chi organizza
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_RuoliDescrizione] (
	@Ruoli VARCHAR(10))
RETURNS NVARCHAR(100)
AS
BEGIN
	DECLARE @testo NVARCHAR(100) = STUFF(
		IIF(ISNULL(@Ruoli, 'O') LIKE '%O%', N', organizzatore', N'')
		+ IIF(@Ruoli LIKE '%P%', N', produttore', N'')
		+ IIF(@Ruoli LIKE '%D%', N', destinatario', N'')
		+ IIF(@Ruoli LIKE '%I%', N', impianto', N'')
		+ IIF(@Ruoli LIKE '%T%', N', trasportatore', N''), 1, 2, N'');

	RETURN UPPER(LEFT(@testo, 1)) + SUBSTRING(@testo, 2, 100);
END;
GO
