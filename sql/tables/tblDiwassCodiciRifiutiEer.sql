SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassCodiciRifiutiEer](
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NOT NULL,
	[Lista] [varchar](10) COLLATE Latin1_General_CI_AS NOT NULL,
	[Codice] [nvarchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblDiwassCodiciRifiutiEer] PRIMARY KEY CLUSTERED 
(
	[IdEer] ASC,
	[Lista] ASC,
	[Codice] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiEer]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassCodiciRifiutiEer_tblDiwassCodiciRifiuti] FOREIGN KEY([Lista], [Codice])
REFERENCES [dbo].[tblDiwassCodiciRifiuti] ([Lista], [Codice])
GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiEer] CHECK CONSTRAINT [FK_tblDiwassCodiciRifiutiEer_tblDiwassCodiciRifiuti]
GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiEer]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassCodiciRifiutiEer_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiEer] CHECK CONSTRAINT [FK_tblDiwassCodiciRifiutiEer_tblRifiutiEer]
GO
