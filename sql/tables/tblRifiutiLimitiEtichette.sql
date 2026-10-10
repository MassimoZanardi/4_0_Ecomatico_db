SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiLimitiEtichette](
	[IdLimite] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiLimitiEtichette] PRIMARY KEY CLUSTERED 
(
	[IdLimite] ASC,
	[IdEtichetta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiLimitiEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimitiEtichette_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimitiEtichette] CHECK CONSTRAINT [FK_tblRifiutiLimitiEtichette_tblEtichette]
GO

ALTER TABLE [dbo].[tblRifiutiLimitiEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimitiEtichette_tblRifiutiLimiti] FOREIGN KEY([IdLimite])
REFERENCES [dbo].[tblRifiutiLimiti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimitiEtichette] CHECK CONSTRAINT [FK_tblRifiutiLimitiEtichette_tblRifiutiLimiti]
GO
