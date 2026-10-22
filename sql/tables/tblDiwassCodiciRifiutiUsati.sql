SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassCodiciRifiutiUsati](
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NOT NULL,
	[Lista] [varchar](10) COLLATE Latin1_General_CI_AS NOT NULL,
	[Codice] [nvarchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[Data] [smalldatetime] NOT NULL,
 CONSTRAINT [PK_tblDiwassCodiciRifiutiUsati] PRIMARY KEY CLUSTERED 
(
	[IdAziendaInterna] ASC,
	[IdEer] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiUsati]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassCodiciRifiutiUsati_tblDiwassCodiciRifiuti] FOREIGN KEY([Lista], [Codice])
REFERENCES [dbo].[tblDiwassCodiciRifiuti] ([Lista], [Codice])
GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiUsati] CHECK CONSTRAINT [FK_tblDiwassCodiciRifiutiUsati_tblDiwassCodiciRifiuti]
GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiUsati]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassCodiciRifiutiUsati_tblSediInterne] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSediInterne] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassCodiciRifiutiUsati] CHECK CONSTRAINT [FK_tblDiwassCodiciRifiutiUsati_tblSediInterne]
GO
