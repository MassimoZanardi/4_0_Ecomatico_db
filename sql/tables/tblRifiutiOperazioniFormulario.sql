SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiOperazioniFormulario](
	[Id] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IsRentri] [bit] NULL,
	[IsProduttore] [bit] NULL,
	[IsTrasportatore] [bit] NULL,
	[IsDestinatario] [bit] NULL,
	[IsIntermediario] [bit] NULL,
	[IsAttivitaRs] [bit] NULL,
	[IsVerificaQuantita] [bit] NULL,
	[IsEsito] [bit] NULL,
	[IsVeicoloFuoriUso] [bit] NULL,
	[IsRifiutoAnalisi] [bit] NULL,
	[IsAttivitaProvenienza] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiOperazioniFormulario] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiOperazioniFormulario]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniFormulario_tblRifiutiOperazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniFormulario] CHECK CONSTRAINT [FK_tblRifiutiOperazioniFormulario_tblRifiutiOperazioni]