SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblServiziOsepe](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdOsepe] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Quantita] [decimal](18, 4) NULL,
 CONSTRAINT [PK_tblServiziOsepe] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdOsepe] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblServiziOsepe]  WITH CHECK ADD  CONSTRAINT [FK_tblServiziOsepe_tblOsepe] FOREIGN KEY([IdOsepe])
REFERENCES [dbo].[tblOsepe] ([Id])
GO

ALTER TABLE [dbo].[tblServiziOsepe] CHECK CONSTRAINT [FK_tblServiziOsepe_tblOsepe]
GO

ALTER TABLE [dbo].[tblServiziOsepe]  WITH CHECK ADD  CONSTRAINT [FK_tblServiziOsepe_tblServizi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblServizi] ([Id])
GO

ALTER TABLE [dbo].[tblServiziOsepe] CHECK CONSTRAINT [FK_tblServiziOsepe_tblServizi]