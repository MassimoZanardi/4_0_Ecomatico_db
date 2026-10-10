SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblModuliRelazioni](
	[Id] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdParent] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblModuliRelazioni_1] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdParent] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblModuliRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblModuliRelazioni_tblModuli_Id] FOREIGN KEY([Id])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblModuliRelazioni] CHECK CONSTRAINT [FK_tblModuliRelazioni_tblModuli_Id]
GO

ALTER TABLE [dbo].[tblModuliRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblModuliRelazioni_tblModuli_IdParent] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblModuliRelazioni] CHECK CONSTRAINT [FK_tblModuliRelazioni_tblModuli_IdParent]
GO
