SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiOperazioni](
	[Id] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Operazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Codice] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[IsRentri] [bit] NULL,
	[ProduttoreSede] [bit] NULL,
	[TrasportatoreSede] [bit] NULL,
	[DestinatarioSede] [bit] NULL,
	[IntermediarioSede] [bit] NULL,
	[Pos] [tinyint] NULL,
	[OperazioneAuto] [char](1) COLLATE Latin1_General_CI_AS NULL,
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
	[IsRentriAccettazione] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiOperazioni] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiOperazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioni_tblRifiutiOperazioni] FOREIGN KEY([OperazioneAuto])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioni] CHECK CONSTRAINT [FK_tblRifiutiOperazioni_tblRifiutiOperazioni]