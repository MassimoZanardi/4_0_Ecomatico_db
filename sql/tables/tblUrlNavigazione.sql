SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblUrlNavigazione](
	[IdSessione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
	[UrlPartenza] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
	[UrlDestinazione] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblUrlNavigazione] PRIMARY KEY CLUSTERED 
(
	[IdSessione] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblUrlNavigazione]  WITH CHECK ADD  CONSTRAINT [FK_tblUrlNavigazione_tblSessioni] FOREIGN KEY([IdSessione])
REFERENCES [dbo].[tblSessioni] ([Id])
GO

ALTER TABLE [dbo].[tblUrlNavigazione] CHECK CONSTRAINT [FK_tblUrlNavigazione_tblSessioni]
GO
