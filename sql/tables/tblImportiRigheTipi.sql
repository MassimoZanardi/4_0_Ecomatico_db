SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRigheTipi](
	[Id] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdModulo] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblImportiRigheTipi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRigheTipi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheTipi_tblModuli] FOREIGN KEY([IdModulo])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheTipi] CHECK CONSTRAINT [FK_tblImportiRigheTipi_tblModuli]
GO
