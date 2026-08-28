SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblPagine](
	[Id] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdFunzione] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Url] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblPagine] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblPagine]  WITH CHECK ADD  CONSTRAINT [FK_tblPagine_tblFunzioni] FOREIGN KEY([IdFunzione])
REFERENCES [dbo].[tblFunzioni] ([Id])
GO

ALTER TABLE [dbo].[tblPagine] CHECK CONSTRAINT [FK_tblPagine_tblFunzioni]