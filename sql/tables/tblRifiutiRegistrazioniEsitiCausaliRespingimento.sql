SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiRegistrazioniEsitiCausaliRespingimento](
	[Id] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Codice] [varchar](2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Nome] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiRegistrazioniEsitiCausaliRespingimento] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
