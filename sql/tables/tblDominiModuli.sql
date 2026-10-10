SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDominiModuli](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdModulo] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblDominiModuli] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdModulo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDominiModuli]  WITH CHECK ADD  CONSTRAINT [FK_tblDominiModuli_tblDomini] FOREIGN KEY([Id])
REFERENCES [dbo].[tblDomini] ([Id])
GO

ALTER TABLE [dbo].[tblDominiModuli] CHECK CONSTRAINT [FK_tblDominiModuli_tblDomini]
GO

ALTER TABLE [dbo].[tblDominiModuli]  WITH CHECK ADD  CONSTRAINT [FK_tblDominiModuli_tblModuli] FOREIGN KEY([IdModulo])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblDominiModuli] CHECK CONSTRAINT [FK_tblDominiModuli_tblModuli]
GO
