SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriCredenziali](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCertificato] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAccreditamento] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdRentri] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRentriCredenziali] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RentriCredenziali_IdDominio_Lock] ON [dbo].[tblRentriCredenziali]
(
	[IdDominio] ASC,
	[Lock] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriCredenziali_tblDomini] FOREIGN KEY([IdDominio])
REFERENCES [dbo].[tblDomini] ([Id])
GO

ALTER TABLE [dbo].[tblRentriCredenziali] CHECK CONSTRAINT [FK_tblRentriCredenziali_tblDomini]
GO

ALTER TABLE [dbo].[tblRentriCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriCredenziali_tblRentriAccreditamenti] FOREIGN KEY([IdAccreditamento])
REFERENCES [dbo].[tblRentriAccreditamenti] ([Id])
GO

ALTER TABLE [dbo].[tblRentriCredenziali] CHECK CONSTRAINT [FK_tblRentriCredenziali_tblRentriAccreditamenti]
GO

ALTER TABLE [dbo].[tblRentriCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriCredenziali_tblRentriCertificati] FOREIGN KEY([IdCertificato])
REFERENCES [dbo].[tblRentriCertificati] ([Id])
GO

ALTER TABLE [dbo].[tblRentriCredenziali] CHECK CONSTRAINT [FK_tblRentriCredenziali_tblRentriCertificati]
GO
