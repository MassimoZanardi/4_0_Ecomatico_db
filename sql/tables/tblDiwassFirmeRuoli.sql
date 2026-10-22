SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassFirmeRuoli](
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Ruolo] [varchar](100) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblDiwassFirmeRuoli] PRIMARY KEY CLUSTERED 
(
	[IdUtente] ASC,
	[IdAziendaInterna] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassFirmeRuoli]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassFirmeRuoli_tblSediInterne] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSediInterne] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassFirmeRuoli] CHECK CONSTRAINT [FK_tblDiwassFirmeRuoli_tblSediInterne]
GO

ALTER TABLE [dbo].[tblDiwassFirmeRuoli]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassFirmeRuoli_tblUtenti] FOREIGN KEY([IdUtente])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassFirmeRuoli] CHECK CONSTRAINT [FK_tblDiwassFirmeRuoli_tblUtenti]
GO
