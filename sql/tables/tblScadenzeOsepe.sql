SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblScadenzeOsepe](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdOsepe] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblScadenzeOsepe] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdOsepe] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblScadenzeOsepe]  WITH CHECK ADD  CONSTRAINT [FK_tblScadenzeOsepe_tblOsepe] FOREIGN KEY([IdOsepe])
REFERENCES [dbo].[tblOsepe] ([Id])
GO

ALTER TABLE [dbo].[tblScadenzeOsepe] CHECK CONSTRAINT [FK_tblScadenzeOsepe_tblOsepe]
GO

ALTER TABLE [dbo].[tblScadenzeOsepe]  WITH CHECK ADD  CONSTRAINT [FK_tblScadenzeOsepe_tblScadenze] FOREIGN KEY([Id])
REFERENCES [dbo].[tblScadenze] ([Id])
GO

ALTER TABLE [dbo].[tblScadenzeOsepe] CHECK CONSTRAINT [FK_tblScadenzeOsepe_tblScadenze]