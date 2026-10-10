SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblIdCancellati](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSessione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Data] [smalldatetime] NULL,
	[DataEccezione] [smalldatetime] NULL,
 CONSTRAINT [PK_tblIdCancellati] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdSessione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblIdCancellati]  WITH CHECK ADD  CONSTRAINT [FK_tblIdCancellati_tblId] FOREIGN KEY([Id])
REFERENCES [dbo].[tblId] ([Id])
GO

ALTER TABLE [dbo].[tblIdCancellati] CHECK CONSTRAINT [FK_tblIdCancellati_tblId]
GO

ALTER TABLE [dbo].[tblIdCancellati]  WITH CHECK ADD  CONSTRAINT [FK_tblIdCancellati_tblSessioni] FOREIGN KEY([IdSessione])
REFERENCES [dbo].[tblSessioni] ([Id])
GO

ALTER TABLE [dbo].[tblIdCancellati] CHECK CONSTRAINT [FK_tblIdCancellati_tblSessioni]
GO
