SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[tblEoWLotti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdMagazzino] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataApertura] [date] NULL,
	[DataChiusura] [date] NULL,
	[QuantitaMax] [int] NULL,
	[Disabilitato] [bit] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblEoWLotti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [dbo].[tblEoWLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLotti_tblEoWMagazzini] FOREIGN KEY([IdMagazzino])
REFERENCES [dbo].[tblEoWMagazzini] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLotti] CHECK CONSTRAINT [FK_tblEoWLotti_tblEoWMagazzini]
GO

ALTER TABLE [dbo].[tblEoWLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLotti_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLotti] CHECK CONSTRAINT [FK_tblEoWLotti_tblRifiutiMateriali]
GO

ALTER TABLE [dbo].[tblEoWLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLotti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLotti] CHECK CONSTRAINT [FK_tblEoWLotti_tblSedi]
