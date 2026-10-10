SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniLotti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdArticolo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataApertura] [date] NULL,
	[DataChiusura] [date] NULL,
	[QuantitaMax] [decimal](18, 2) NULL,
	[Disabilitato] [bit] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblMagazziniLotti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMagazziniLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniLotti_tblMagazziniArticoli] FOREIGN KEY([IdArticolo])
REFERENCES [dbo].[tblMagazziniArticoli] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniLotti] CHECK CONSTRAINT [FK_tblMagazziniLotti_tblMagazziniArticoli]
GO

ALTER TABLE [dbo].[tblMagazziniLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniLotti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniLotti] CHECK CONSTRAINT [FK_tblMagazziniLotti_tblSedi]
GO
