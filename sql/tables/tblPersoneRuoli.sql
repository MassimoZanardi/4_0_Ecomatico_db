SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblPersoneRuoli](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRuolo] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[DataInizio] [date] NULL,
	[DataFine] [date] NULL,
 CONSTRAINT [PK_tblPersoneRuoli] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdRuolo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblPersoneRuoli]  WITH CHECK ADD  CONSTRAINT [FK_tblPersoneRuoli_tblPersone] FOREIGN KEY([Id])
REFERENCES [dbo].[tblPersone] ([Id])
GO

ALTER TABLE [dbo].[tblPersoneRuoli] CHECK CONSTRAINT [FK_tblPersoneRuoli_tblPersone]
GO

ALTER TABLE [dbo].[tblPersoneRuoli]  WITH CHECK ADD  CONSTRAINT [FK_tblPersoneRuoli_tblRuoli] FOREIGN KEY([IdRuolo])
REFERENCES [dbo].[tblRuoli] ([Id])
GO

ALTER TABLE [dbo].[tblPersoneRuoli] CHECK CONSTRAINT [FK_tblPersoneRuoli_tblRuoli]
GO
