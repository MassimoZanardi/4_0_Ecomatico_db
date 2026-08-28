SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEoWMovimentiRelazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdParent] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Pos] [int] NULL
 CONSTRAINT [PK_tblEoWMovimentiRelazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdParent] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEoWMovimentiRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMovimentiRelazioni_tblEoWMovimenti_Id] FOREIGN KEY([Id])
REFERENCES [dbo].[tblEoWMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMovimentiRelazioni] CHECK CONSTRAINT [FK_tblEoWMovimentiRelazioni_tblEoWMovimenti_Id]
GO

ALTER TABLE [dbo].[tblEoWMovimentiRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMovimentiRelazioni_tblEoWMovimenti_IdParent] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblEoWMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMovimentiRelazioni] CHECK CONSTRAINT [FK_tblEoWMovimentiRelazioni_tblEoWMovimenti_IdParent]
GO

