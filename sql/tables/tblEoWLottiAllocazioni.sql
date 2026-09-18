SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[tblEoWLottiAllocazioni](
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAllocazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Valore] [int] NULL,
 CONSTRAINT [PK_tblEoWLottiAllocazioni] PRIMARY KEY CLUSTERED 
(
	[IdLotto] ASC,
	[IdAllocazione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [dbo].[tblEoWLottiAllocazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiAllocazioni_tblEoWAllocazioni] FOREIGN KEY([IdAllocazione])
REFERENCES [dbo].[tblEoWAllocazioni] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLottiAllocazioni] CHECK CONSTRAINT [FK_tblEoWLottiAllocazioni_tblEoWAllocazioni]
GO

ALTER TABLE [dbo].[tblEoWLottiAllocazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiAllocazioni_tblEoWLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblEoWLotti] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLottiAllocazioni] CHECK CONSTRAINT [FK_tblEoWLottiAllocazioni_tblEoWLotti]
