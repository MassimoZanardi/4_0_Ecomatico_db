SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriRegistri](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRentri] [char](16) COLLATE Latin1_General_CI_AS NULL
 CONSTRAINT [PK_tblRentriRegistri] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriRegistri_tblRifiutiRegistri] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRentriRegistri] CHECK CONSTRAINT [FK_tblRentriRegistri_tblRifiutiRegistri]
GO

