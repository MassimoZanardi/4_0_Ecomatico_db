SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblSediDatiEstesi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAteco] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[NumeroRea] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Dipendenti] [int] NULL,
	[LegaleNome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[LegaleCognome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblSediDatiEstesi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblSediDatiEstesi]  WITH CHECK ADD  CONSTRAINT [FK_tblSediDatiEstesi_tblSedi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblSediDatiEstesi] CHECK CONSTRAINT [FK_tblSediDatiEstesi_tblSedi]
GO
