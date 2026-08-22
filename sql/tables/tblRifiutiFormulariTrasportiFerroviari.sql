SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiFormulariTrasportiFerroviari](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Treno] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Tratta] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Rid] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiFormulariTrasportiFerroviari] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiFormulariTrasportiFerroviari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulariTrasportiFerroviari_tblRifiutiFormulari] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiFormulari] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulariTrasportiFerroviari] CHECK CONSTRAINT [FK_tblRifiutiFormulariTrasportiFerroviari_tblRifiutiFormulari]