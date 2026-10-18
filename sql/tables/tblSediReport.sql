SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblSediReport](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdLayout] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Intestazione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Piepagina] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[IntestazioneColore] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[IntestazioneFontSize] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[IntestazioneAllineamento] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[PiepaginaColore] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[PiepaginaFontSize] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[PiepaginaAllineamento] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Logo] [varbinary](max) NULL,
 CONSTRAINT [PK_tblSediReport] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblSediReport]  WITH CHECK ADD  CONSTRAINT [FK_tblSediReport_tblReportLayout] FOREIGN KEY([IdLayout])
REFERENCES [dbo].[tblReportLayout] ([Id])
GO

ALTER TABLE [dbo].[tblSediReport] CHECK CONSTRAINT [FK_tblSediReport_tblReportLayout]
GO

ALTER TABLE [dbo].[tblSediReport]  WITH CHECK ADD  CONSTRAINT [FK_tblSediReport_tblSedi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblSediReport] CHECK CONSTRAINT [FK_tblSediReport_tblSedi]
GO
