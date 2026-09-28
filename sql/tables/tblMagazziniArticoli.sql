SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniArticoli](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Codice] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Descrizione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblMagazziniArticoli] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

-- IdSede è scope Azienda (l'Articolo appartiene all'Azienda, non a una singola Sede).
ALTER TABLE [dbo].[tblMagazziniArticoli]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniArticoli_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniArticoli] CHECK CONSTRAINT [FK_tblMagazziniArticoli_tblSedi]
GO

ALTER TABLE [dbo].[tblMagazziniArticoli]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniArticoli_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniArticoli] CHECK CONSTRAINT [FK_tblMagazziniArticoli_tblUnitaMisura]
GO
