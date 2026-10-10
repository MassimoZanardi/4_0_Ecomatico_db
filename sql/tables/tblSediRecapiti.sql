SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblSediRecapiti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRecapito] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[Valore] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblSediRecapiti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdRecapito] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblSediRecapiti]  WITH CHECK ADD  CONSTRAINT [FK_tblSediRecapiti_tblRecapiti] FOREIGN KEY([IdRecapito])
REFERENCES [dbo].[tblRecapiti] ([Id])
GO

ALTER TABLE [dbo].[tblSediRecapiti] CHECK CONSTRAINT [FK_tblSediRecapiti_tblRecapiti]
GO

ALTER TABLE [dbo].[tblSediRecapiti]  WITH CHECK ADD  CONSTRAINT [FK_tblSediRecapiti_tblSedi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblSediRecapiti] CHECK CONSTRAINT [FK_tblSediRecapiti_tblSedi]
GO
