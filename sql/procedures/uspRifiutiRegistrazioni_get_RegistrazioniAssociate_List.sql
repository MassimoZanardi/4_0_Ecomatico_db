CREATE   PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_RegistrazioniAssociate_List]
    @PageNumber  INT      = 1,
    @RowsPerPage INT      = 50,
    @IdParent    CHAR(16) = NULL,
    @IdSessione  CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdParent   = NULLIF(LTRIM(RTRIM(@IdParent)),   '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @IdParent IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'RRG',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (
            SELECT 1
            FROM
                dbo.tblRifiutiRegistrazioni  r
                INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
                INNER JOIN dbo.tblRifiutiRegistri  g ON m.IdRegistro  = g.Id
                INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
            WHERE
                r.Id = @IdParent
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF @PageNumber  < 1 SET @PageNumber  = 1;
        IF @RowsPerPage < 1 SET @RowsPerPage = 50;

        DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

        -- FIX: IdUnitaMisura e Quantita spostate da tblRifiutiRegistrazioni (r/p) a tblRifiutiMovimenti (m/mp)
        ;WITH cte AS (
            SELECT
                Verso           = 0,
                r.Id,
                r.Operazione,
                r.Numero,
                r.[Data],
                m.IdUnitaMisura,
                m.Quantita,
                QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
                EerNome         = e.Nome,
                StatoFisicoNome = s.Nome,
                l.Pos
            FROM
                dbo.tblRifiutiRegistrazioniRelazioni l
                INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id          = r.Id
                INNER JOIN dbo.tblRifiutiMovimenti     m ON r.IdMovimento = m.Id
                LEFT  JOIN (
                    -- Somma delle quantità associate (figlie) per ogni registrazione padre
                    SELECT
                        l2.Id,
                        Quantita = SUM(l2.Quantita)
                    FROM
                        dbo.tblRifiutiRegistrazioniRelazioni l2
                        INNER JOIN dbo.tblRifiutiRegistrazioni p  ON l2.IdParent = p.Id
                        INNER JOIN dbo.tblRifiutiMovimenti     mp ON p.IdMovimento = mp.Id
                    WHERE
                        p.Lock      < 2
                        AND mp.Quantita > 0
                    GROUP BY l2.Id
                ) a  ON r.Id = a.Id
                LEFT  JOIN dbo.tblRifiutiEer         e ON m.IdEer         = e.Id
                LEFT  JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
            WHERE
                l.IdParent  = @IdParent
                AND l.Quantita >= 0
                AND r.Lock      = 0
        ),
        cteTotali AS (
            SELECT
                Registrazioni = COUNT(*),
                Totali        = IIF(Operazione = 'S', 'Scarichi ', 'Carichi ') +
                    'associati: '              + FORMAT(COUNT(*),                   'N0', 'IT-it') +
                    ' | Tot. q.tà associata: ' + FORMAT(ISNULL(SUM(Quantita),        0), 'N2', 'IT-it') +
                    ' | Tot. q.tà residua: '   + FORMAT(ISNULL(SUM(QuantitaResidua), 0), 'N2', 'IT-it')
            FROM   cte
            GROUP BY Operazione
        )
        SELECT
            c.Verso, c.Id, c.Operazione, c.Numero, c.[Data],
            c.IdUnitaMisura, c.Quantita, c.QuantitaResidua,
            c.EerNome, c.StatoFisicoNome, c.Pos,
            t.Registrazioni, t.Totali
        FROM       cte       c
        CROSS JOIN cteTotali t

        UNION ALL

        SELECT
            Verso           = 0,
            Id              = NULL,
            Operazione      = NULL,
            Numero          = 0,
            [Data]          = '19000101',
            IdUnitaMisura   = NULL,
            Quantita        = 0,
            QuantitaResidua = 0,
            EerNome         = NULL,
            StatoFisicoNome = NULL,
            Pos             = 0,
            Registrazioni   = 0,
            Totali          = IIF(r.Operazione = 'C', 'Scarichi associati', 'Carichi associati')
        FROM   dbo.tblRifiutiRegistrazioni r
        WHERE  r.Id = @IdParent
          AND  NOT EXISTS (SELECT 1 FROM cte)

        ORDER BY Pos
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1
    END

END;
