SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiOperazioni](
	[Id] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Operazione] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Codice] [varchar](5) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Nome] [varchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IsRentri] [bit] NULL,
	[ProduttoreSede] [bit] NULL,
	[TrasportatoreSede] [bit] NULL,
	[DestinatarioSede] [bit] NULL,
	[IntermediarioSede] [bit] NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiOperazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
