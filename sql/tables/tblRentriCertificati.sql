SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriCertificati](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRentri] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataScadenza] [date] NULL,
	[Lock] [tinyint] NULL
 CONSTRAINT [PK_tblRentriCertificati] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriCertificati]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriCertificati_tblDomini] FOREIGN KEY([IdDominio])
REFERENCES [dbo].[tblDomini] ([Id])
GO

ALTER TABLE [dbo].[tblRentriCertificati] CHECK CONSTRAINT [FK_tblRentriCertificati_tblDomini]
GO

