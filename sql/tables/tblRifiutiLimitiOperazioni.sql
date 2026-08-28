SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiLimitiOperazioni](
	[IdLimite] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiLimitiOperazioni] PRIMARY KEY CLUSTERED
(
	[IdLimite] ASC,
	[IdOperazione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiLimitiOperazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimitiOperazioni_tblRifiutiLimiti] FOREIGN KEY([IdLimite])
REFERENCES [dbo].[tblRifiutiLimiti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimitiOperazioni] CHECK CONSTRAINT [FK_tblRifiutiLimitiOperazioni_tblRifiutiLimiti]
GO

ALTER TABLE [dbo].[tblRifiutiLimitiOperazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimitiOperazioni_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimitiOperazioni] CHECK CONSTRAINT [FK_tblRifiutiLimitiOperazioni_tblRifiutiOperazioni]
