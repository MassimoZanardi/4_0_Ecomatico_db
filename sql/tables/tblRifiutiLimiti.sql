SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiLimiti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Valore] [decimal](18, 2) NULL,
	[Riferimento] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Intervallo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
	[VerificaPerRegistro] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiLimiti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiLimiti_IdSede_Lock] ON [dbo].[tblRifiutiLimiti]
(
	[IdSede] ASC,
	[Lock] ASC
)
INCLUDE([IdRegistro]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiLimiti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimiti_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimiti] CHECK CONSTRAINT [FK_tblRifiutiLimiti_tblRifiutiRegistri]
GO

ALTER TABLE [dbo].[tblRifiutiLimiti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiLimiti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiLimiti] CHECK CONSTRAINT [FK_tblRifiutiLimiti_tblSedi]
GO
