SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiFormulariTrasportiMarittimi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nave] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Imdg] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiFormulariTrasportiMarittimi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiFormulariTrasportiMarittimi]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulariTrasportiMarittimi_tblRifiutiFormulari] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiFormulari] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulariTrasportiMarittimi] CHECK CONSTRAINT [FK_tblRifiutiFormulariTrasportiMarittimi_tblRifiutiFormulari]