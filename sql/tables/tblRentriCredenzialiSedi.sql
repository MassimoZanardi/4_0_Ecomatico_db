SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriCredenzialiSedi](
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCredenziale] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRentri] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [tinyint] NULL
 CONSTRAINT [PK_tblRentriCredenzialiSedi] PRIMARY KEY CLUSTERED 
(
	[IdSede] ASC,
	[IdCredenziale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriCredenzialiSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriCredenzialiSedi_tblRentriCredenziali] FOREIGN KEY([IdCredenziale])
REFERENCES [dbo].[tblRentriCredenziali] ([Id])
GO

ALTER TABLE [dbo].[tblRentriCredenzialiSedi] CHECK CONSTRAINT [FK_tblRentriCredenzialiSedi_tblRentriCredenziali]
GO

ALTER TABLE [dbo].[tblRentriCredenzialiSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriCredenzialiSedi_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRentriCredenzialiSedi] CHECK CONSTRAINT [FK_tblRentriCredenzialiSedi_tblSedi]
GO

