SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriFirmeCredenziali](
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCredenziale] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[CredentialsId] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DeviceIdentifier] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataBoarding] [datetime2](0) NULL,
	[Lock] [tinyint] NULL
 CONSTRAINT [PK_tblRentriFirmeCredenziali] PRIMARY KEY CLUSTERED
(
	[IdUtente] ASC,
	[IdCredenziale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeCredenziali_tblUtenti] FOREIGN KEY([IdUtente])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali] CHECK CONSTRAINT [FK_tblRentriFirmeCredenziali_tblUtenti]
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeCredenziali_tblRentriCredenziali] FOREIGN KEY([IdCredenziale])
REFERENCES [dbo].[tblRentriCredenziali] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali] CHECK CONSTRAINT [FK_tblRentriFirmeCredenziali_tblRentriCredenziali]
GO
