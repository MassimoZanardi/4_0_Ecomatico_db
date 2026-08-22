SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiOperazioniRegistro](
	[Id] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[OperazioneAuto] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IsRentri] [bit] NULL,
	[IsFormulario] [bit] NULL,
	[IsIntegrazioneFir] [bit] NULL,
	[IsProduttore] [bit] NULL,
	[IsTrasportatore] [bit] NULL,
	[IsDestinatario] [bit] NULL,
	[IsIntermediario] [bit] NULL,
	[IsAttivitaRs] [bit] NULL,
	[IsEsito] [bit] NULL,
	[IsAttivitaProvenienza] [bit] NULL,
	[IsMateriale] [bit] NULL,
	[IsStoccaggioIstantaneo] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiOperazioniRegistro] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistro]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniRegistro_tblRifiutiOperazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistro] CHECK CONSTRAINT [FK_tblRifiutiOperazioniRegistro_tblRifiutiOperazioni]
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistro]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniRegistro_tblRifiutiOperazioniRegistro] FOREIGN KEY([OperazioneAuto])
REFERENCES [dbo].[tblRifiutiOperazioniRegistro] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistro] CHECK CONSTRAINT [FK_tblRifiutiOperazioniRegistro_tblRifiutiOperazioniRegistro]