SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniMovimenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Data] [date] NULL,
	[Numero] [int] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblMagazziniMovimenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMagazziniMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimenti_tblMagazziniOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblMagazziniOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimenti] CHECK CONSTRAINT [FK_tblMagazziniMovimenti_tblMagazziniOperazioni]
GO

ALTER TABLE [dbo].[tblMagazziniMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimenti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimenti] CHECK CONSTRAINT [FK_tblMagazziniMovimenti_tblSedi]
GO
