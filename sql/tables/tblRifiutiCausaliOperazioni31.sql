SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiCausaliOperazioni31](
	[IdCausale] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiCausaliOperazioni31] PRIMARY KEY CLUSTERED 
(
	[IdCausale] ASC,
	[IdOperazione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiCausaliOperazioni31]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiCausaliOperazioni31_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiCausaliOperazioni31] CHECK CONSTRAINT [FK_tblRifiutiCausaliOperazioni31_tblRifiutiOperazioni]
GO
