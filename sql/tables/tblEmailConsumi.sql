SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modulo Email (EML): email contate nella quota, per dominio e giorno. Creata da tools/email_modulo.sql
CREATE TABLE [dbo].[tblEmailConsumi](
	[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Giorno] [date] NOT NULL,
	[Numero] [int] NOT NULL,
 CONSTRAINT [PK_tblEmailConsumi] PRIMARY KEY CLUSTERED ([IdDominio] ASC, [Giorno] ASC)
) ON [PRIMARY]
GO
