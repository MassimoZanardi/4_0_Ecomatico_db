SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiLimitiEer](
	[IdLimite] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiLimitiEer] PRIMARY KEY CLUSTERED 
(
	[IdLimite] ASC,
	[IdEer] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiLimitiEer]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimitiEer_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimitiEer] CHECK CONSTRAINT [FK_tblRifiutiLimitiEer_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblRifiutiLimitiEer]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimitiEer_tblRifiutiLimiti] FOREIGN KEY([IdLimite])
REFERENCES [dbo].[tblRifiutiLimiti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimitiEer] CHECK CONSTRAINT [FK_tblRifiutiLimitiEer_tblRifiutiLimiti]
GO
