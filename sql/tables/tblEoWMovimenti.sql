SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEoWMovimenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdImballo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdRegistrazione] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Numero] [int] NOT NULL,
	[Data] [date] NOT NULL,
	[Quantita] [decimal](18, 2) NOT NULL,
	[Operazione] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[AllaRinfusa] [bit] NULL,
	[Lock] [tinyint] NOT NULL
 CONSTRAINT [PK_tblEoWMovimenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEoWMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMovimenti_tblEoWLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblEoWLotti] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMovimenti] CHECK CONSTRAINT [FK_tblEoWMovimenti_tblEoWLotti]
GO

ALTER TABLE [dbo].[tblEoWMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMovimenti_tblImballi] FOREIGN KEY([IdImballo])
REFERENCES [dbo].[tblImballi] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMovimenti] CHECK CONSTRAINT [FK_tblEoWMovimenti_tblImballi]
GO

ALTER TABLE [dbo].[tblEoWMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMovimenti_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMovimenti] CHECK CONSTRAINT [FK_tblEoWMovimenti_tblRifiutiMateriali]
GO

ALTER TABLE [dbo].[tblEoWMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMovimenti_tblRifiutiRegistrazioni] FOREIGN KEY([IdRegistrazione])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMovimenti] CHECK CONSTRAINT [FK_tblEoWMovimenti_tblRifiutiRegistrazioni]
GO

