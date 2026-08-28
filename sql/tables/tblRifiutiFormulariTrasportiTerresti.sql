SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiFormulariTrasportiTerresti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[TargaMotrice] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[TargaRimorchio] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[ConducenteNome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[ConducenteCognome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Percorso] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[RimorchioPrecedente] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiFormulariTrasportiTerresti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiFormulariTrasportiTerresti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulariTrasportiTerresti_tblRifiutiFormulari] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiFormulari] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulariTrasportiTerresti] CHECK CONSTRAINT [FK_tblRifiutiFormulariTrasportiTerresti_tblRifiutiFormulari]