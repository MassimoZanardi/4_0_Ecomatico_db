CREATE PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Numerazione]
	@IdSessione CHAR(16),
	@DalNumero INT,
	@AlNumero INT,
	@Anno INT,
	@PrimoNumero INT
AS
BEGIN

SET NOCOUNT, XACT_ABORT ON

BEGIN TRY

DECLARE @returnValue INT = 0
DECLARE @returnMessage NVARCHAR(200) = NULL

-- Controlla il permesso sulla funzione
DECLARE @permesso TINYINT
EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RRG', @Permesso = @permesso OUTPUT
IF 2 > @permesso
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'Non si dispone dei diritti necessari'
	GOTO BRANCH_END
END

DECLARE @totaleDaRinumerare INT
SELECT
	@totaleDaRinumerare = COUNT(*)
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
WHERE
	e.Id = @IdSessione
	AND r.Lock < 2
	AND YEAR(r.[Data]) = @Anno
	AND r.Numero BETWEEN @DalNumero AND @AlNumero

-- Se non c'è nulla da rinumerare
IF @totaleDaRinumerare = 0
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'Non ci sono registrazioni nell''intervallo indicato'
	GOTO BRANCH_END
END

-- Se la numerazione finale supera 999.999
IF @PrimoNumero + @totaleDaRinumerare > 999999
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'La rinumerazione non può assegnare numeri maggiori di 999.999'
	GOTO BRANCH_END
END

-- Se la nuova rinumerazione entra in conflitto con altre registrazioni al di fuori del gruppo che sarà rinumerato
IF EXISTS (SELECT 1
	FROM
		dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
	WHERE
		e.Id = @IdSessione
		AND r.Lock < 2
		AND YEAR(r.[Data]) = @Anno
		AND r.Numero NOT BETWEEN @DalNumero AND @AlNumero
		AND r.Numero BETWEEN @PrimoNumero AND @PrimoNumero + @totaleDaRinumerare
)
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'La nuova numerazione è in conflitto con quella di altre registrazioni'
	GOTO BRANCH_END
END

UPDATE r
SET Numero = t.NumeroBase + @PrimoNumero - 1
FROM
	dbo.tblRifiutiRegistrazioni r INNER JOIN
	(SELECT
		r.Id,
		NumeroBase = ROW_NUMBER() OVER (ORDER BY r.[Data], r.Numero)
	FROM
		dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
	WHERE
		e.Id = @IdSessione
		AND r.Lock < 2
		AND YEAR(r.[Data]) = @Anno
		AND r.Numero BETWEEN @DalNumero AND @AlNumero
	) t ON r.Id = t.Id

	SET @returnValue = @@ROWCOUNT

END TRY
BEGIN CATCH
	THROW;
END CATCH

BRANCH_END:

SET NOCOUNT, XACT_ABORT OFF

IF @returnValue < 0
BEGIN
	SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
	THROW 50001, @returnMessage, 1;
END

SELECT ReturnValue = @returnValue

END
