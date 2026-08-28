SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblUtentiSediInterne](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblUtentiSediInterne] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblUtentiSediInterne]  WITH CHECK ADD  CONSTRAINT [FK_tblUtentiSediInterne_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblUtentiSediInterne] CHECK CONSTRAINT [FK_tblUtentiSediInterne_tblSedi]
GO

ALTER TABLE [dbo].[tblUtentiSediInterne]  WITH CHECK ADD  CONSTRAINT [FK_tblUtentiSediInterne_tblUtenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblUtentiSediInterne] CHECK CONSTRAINT [FK_tblUtentiSediInterne_tblUtenti]