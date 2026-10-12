SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRigheDettagli](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAliquotaIva] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdConto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Descrizione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiRigheDettagli] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRigheDettagli]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheDettagli_tblAliquoteIva] FOREIGN KEY([IdAliquotaIva])
REFERENCES [dbo].[tblAliquoteIva] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli] CHECK CONSTRAINT [FK_tblImportiRigheDettagli_tblAliquoteIva]
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheDettagli_tblFattureConti] FOREIGN KEY([IdConto])
REFERENCES [dbo].[tblFattureConti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli] CHECK CONSTRAINT [FK_tblImportiRigheDettagli_tblFattureConti]
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheDettagli_tblImportiRighe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImportiRighe] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli] CHECK CONSTRAINT [FK_tblImportiRigheDettagli_tblImportiRighe]
GO
