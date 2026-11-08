SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMigrazioniCodici](
	[Versione] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[Tabella] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[CodiceOrigine] [varchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[CodiceDestinazione] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblMigrazioniCodici] PRIMARY KEY CLUSTERED 
(
	[Versione] ASC,
	[Tabella] ASC,
	[CodiceOrigine] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
