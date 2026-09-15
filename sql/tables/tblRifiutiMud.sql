SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMud](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeLegale] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeUnitaLocale] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Data] [date] NULL,
	[Anno] [int] NULL,
	[DataGenerazione] [smalldatetime] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiMud] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMud]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMud_tblSedi_IdSede] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMud] CHECK CONSTRAINT [FK_tblRifiutiMud_tblSedi_IdSede]
GO

ALTER TABLE [dbo].[tblRifiutiMud]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMud_tblSedi_IdSedeLegale] FOREIGN KEY([IdSedeLegale])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMud] CHECK CONSTRAINT [FK_tblRifiutiMud_tblSedi_IdSedeLegale]
GO

ALTER TABLE [dbo].[tblRifiutiMud]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMud_tblSedi_IdSedeUnitaLocale] FOREIGN KEY([IdSedeUnitaLocale])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMud] CHECK CONSTRAINT [FK_tblRifiutiMud_tblSedi_IdSedeUnitaLocale]
GO
