SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMigrazioni](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Versione] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdDominioDa] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSedeInternaDa] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IdDominioA] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Simulazione] [bit] NOT NULL,
	[DataInizio] [datetime2](0) NOT NULL,
	[DataFine] [datetime2](0) NULL,
	[Esito] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Messaggio] [nvarchar](2000) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblMigrazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMigrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblMigrazioni_tblDomini] FOREIGN KEY([IdDominioA])
REFERENCES [dbo].[tblDomini] ([Id])
GO

ALTER TABLE [dbo].[tblMigrazioni] CHECK CONSTRAINT [FK_tblMigrazioni_tblDomini]
GO
