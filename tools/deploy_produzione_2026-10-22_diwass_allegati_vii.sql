/*
Deploy produzione 2026-10-22 - Modulo DIWASS: Allegato VII (Diwass > Allegati VII)

Richiede gli script DIWASS precedenti dello stesso giorno (credenziali, operatori). Rieseguibile. Eseguire con
sqlcmd -f 65001 -I (oppure da SSMS) sul DB 4_0_ecomatico. App e hub 1_0_DiwassApi da pubblicare insieme.

1. Codifiche DIWASS dei rifiuti: tblDiwassCodiciRifiuti (codici ufficiali Basel A e B, OCSE, allegati IIIA e IIIB) e
   tblDiwassCodiciRifiutiEer (codici suggeriti per EER), come tools/diwass_codici_rifiuti.sql.
2. Tabelle dell'Allegato VII: tblDiwassAllegatiVii, tblDiwassAllegatiViiSoggetti, tblDiwassCodiciRifiutiUsati,
   tblDiwassFirmeRuoli; funzione DWA (Allegati VII DIWASS, assegnabile agli utenti standard), pagina DWA, menu AL3 in
   cima all'area Diwass (Operatori e Credenziali dopo).
3. Funzioni ufnDiwassAllegatiVii_* e SP uspDiwassAllegatiVii_* (creazione da registrazione o da zero, scheda,
   salvataggio, elenco ed esportazione, cancellazione, dati e controlli per l'invio, esito, select).
4. uspSYS_del_SedeInterna/SedeEsterna/Registro/RifiutiMovimentiCascade (solo uso tecnico): chiavi esterne nuove.
   Regole D5 in docs/regole/diwass.md (repo app).
*/

-- ===== 1. Codifiche DIWASS dei rifiuti
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.tblDiwassCodiciRifiuti', 'U') IS NULL
	CREATE TABLE dbo.tblDiwassCodiciRifiuti (
		Lista VARCHAR(10) NOT NULL,
		Codice NVARCHAR(20) NOT NULL,
		Descrizione NVARCHAR(2000) NULL,
		CONSTRAINT PK_tblDiwassCodiciRifiuti PRIMARY KEY CLUSTERED (Lista ASC, Codice ASC)
	);
GO
IF OBJECT_ID('dbo.tblDiwassCodiciRifiutiEer', 'U') IS NULL
	CREATE TABLE dbo.tblDiwassCodiciRifiutiEer (
		IdEer CHAR(6) NOT NULL,
		Lista VARCHAR(10) NOT NULL,
		Codice NVARCHAR(20) NOT NULL,
		Pos TINYINT NULL,
		CONSTRAINT PK_tblDiwassCodiciRifiutiEer PRIMARY KEY CLUSTERED (IdEer ASC, Lista ASC, Codice ASC),
		CONSTRAINT FK_tblDiwassCodiciRifiutiEer_tblRifiutiEer FOREIGN KEY (IdEer) REFERENCES dbo.tblRifiutiEer (Id),
		CONSTRAINT FK_tblDiwassCodiciRifiutiEer_tblDiwassCodiciRifiuti FOREIGN KEY (Lista, Codice) REFERENCES dbo.tblDiwassCodiciRifiuti (Lista, Codice)
	);
GO
MERGE dbo.tblDiwassCodiciRifiuti AS t
USING (VALUES
('basel_a', N'A1010', N'Metal wastes and waste consisting of alloys of any of the following: Antimony, Arsenic, Beryllium, Cadmium, Lead, Mercury, Selenium, Tellurium, Thallium, but excluding such wastes specifically listed on list B.'),
('basel_a', N'A1020', N'Waste having as constituents or contaminants, excluding metal waste in massive form, any of the following (see list in Annex)'),
('basel_a', N'A1030', N'Wastes having as constituents or contaminants any of the following: Arsenic; arsenic compounds, Mercury; mercury compounds, Thallium; thallium compounds'),
('basel_a', N'A1040', N'Wastes having as constituents any of the following: Metal carbonyls, Hexavalent chromium compounds'),
('basel_a', N'A1050', N'Galvanic sludges'),
('basel_a', N'A1060', N'Waste liquors from the pickling of metals'),
('basel_a', N'A1070', N'Leaching residues from zinc processing, dust and sludges such as jarosite, hematite, etc.'),
('basel_a', N'A1080', N'Waste zinc residues not included on list B, containing lead and cadmium in concentrations sufficient to exhibit Annex III characteristics'),
('basel_a', N'A1090', N'Ashes from the incineration of insulated copper wire'),
('basel_a', N'A1100', N'Dusts and residues from gas cleaning systems of copper smelters'),
('basel_a', N'A1110', N'Spent electrolytic solutions from copper electrorefining and electrowinning operations'),
('basel_a', N'A1120', N'Waste sludges, excluding anode slimes, from electrolyte purification systems in copper electrorefining and electrowinning operations'),
('basel_a', N'A1130', N'Spent etching solutions containing dissolved copper'),
('basel_a', N'A1140', N'Waste cupric chloride and copper cyanide catalysts'),
('basel_a', N'A1150', N'Precious metal ash from incineration of printed circuit boards not included on list B[1]'),
('basel_a', N'A1160', N'Waste lead-acid batteries, whole or crushed'),
('basel_a', N'A1170', N'Unsorted waste batteries excluding mixtures of only list B batteries. Waste batteries not specified on list B containing Annex I constituents to an extent to render them hazardous'),
('basel_a', N'A1180', N'Waste electrical and electronic assemblies or scrap[2] (see details in Annex) (note the related entry on list B B1110)[3]'),
('basel_a', N'A1181', N'Electrical and electronic waste (note the related entry Y49 in List A of Part 3 in Annex V)'),
('basel_a', N'A1190', N'Waste metal cables coated or insulated with plastics containing or contaminated with coal tar, PCB[4], lead, cadmium, other organohalogen compounds or other Annex I constituents to an extent that they exhibit Annex III characteristics.'),
('basel_a', N'A2010', N'Glass waste from cathode-ray tubes and other activated glasses'),
('basel_a', N'A2020', N'Waste inorganic fluorine compounds in the form of liquids or sludges but excluding such wastes specified on list B'),
('basel_a', N'A2030', N'Waste catalysts but excluding such wastes specified on list B'),
('basel_a', N'A2040', N'Waste gypsum arising from chemical industry processes, when containing Annex I constituents to the extent that it exhibits an Annex III hazardous characteristic (note the related entry on list B B2080)'),
('basel_a', N'A2050', N'Waste asbestos (dusts and fibres)'),
('basel_a', N'A2060', N'Coal-fired power plant fly-ash containing Annex I substances in concentrations sufficient to exhibit Annex III characteristics (note the related entry on list B B2050)'),
('basel_a', N'A3010', N'Waste from the production or processing of petroleum coke and bitumen'),
('basel_a', N'A3020', N'Waste mineral oils unfit for their originally intended use'),
('basel_a', N'A3030', N'Wastes that contain, consist of or are contaminated with leaded anti-knock compound sludges'),
('basel_a', N'A3040', N'Waste thermal (heat transfer) fluids'),
('basel_a', N'A3050', N'Wastes from production, formulation and use of resins, latex, plasticizers, glues/adhesives excluding such wastes specified on list B (note the related entry on list B B4020)'),
('basel_a', N'A3060', N'Waste nitrocellulose'),
('basel_a', N'A3070', N'Waste phenols, phenol compounds including chlorophenol in the form of liquids or sludges'),
('basel_a', N'A3080', N'Waste ethers not including those specified on list B'),
('basel_a', N'A3090', N'Waste leather dust, ash, sludges and flours when containing hexavalent chromium compounds or biocides (note the related entry on list B B3100)'),
('basel_a', N'A3100', N'Waste paring and other waste of leather or of composition leather not suitable for the manufacture of leather articles containing hexavalent chromium compounds or biocides (note the related entry on list B B3090)'),
('basel_a', N'A3110', N'Fellmongery wastes containing hexavalent chromium compounds or biocides or infectious substances (note the related entry on list B B3110)'),
('basel_a', N'A3120', N'Fluff - light fraction from shredding'),
('basel_a', N'A3130', N'Waste organic phosphorous compounds'),
('basel_a', N'A3140', N'Waste non-halogenated organic solvents but excluding such wastes specified on list B'),
('basel_a', N'A3150', N'Waste halogenated organic solvents'),
('basel_a', N'A3160', N'Waste halogenated or unhalogenated non-aqueous distillation residues arising from organic solvent recovery operations'),
('basel_a', N'A3170', N'Wastes arising from the production of aliphatic halogenated hydrocarbons (such as chloromethane, dichloro-ethane, vinyl chloride, vinylidene chloride, allyl chloride and epichlorhydrin)'),
('basel_a', N'A3180', N'Wastes, substances and articles containing, consisting of or contaminated with PCB, PCT, PCN or PBB, or any other polybrominated analogues of these compounds, at a concentration level of 50 mg/kg or more[1]'),
('basel_a', N'A3190', N'Waste tarry residues (excluding asphalt cements) arising from refining, distillation and any pyrolitic treatment of organic materials'),
('basel_a', N'A3200', N'Bituminous material (asphalt waste) from road construction and maintenance, containing tar (note the related entry on list B, B2130)'),
('basel_a', N'A3210', N'Plastic waste, including mixtures of such waste, containing or contaminated with Annex I constituents, to an extent that it exhibits an Annex III characteristic (note the related entry B3011, in list B of this Part, and entry Y48, in list A of Part 3)'),
('basel_a', N'A4010', N'Wastes from the production, preparation and use of pharmaceutical products but excluding such wastes specified on list B'),
('basel_a', N'A4020', N'Clinical and related wastes; that is wastes arising from medical, nursing, dental, veterinary, or similar practices, and wastes generated in hospitals or other facilities during the investigation or treatment of patients, or research projects'),
('basel_a', N'A4030', N'Wastes from the production, formulation and use of biocides and phytopharmaceuticals, including waste pesticides and herbicides which are off-specification, outdated,[1] or unfit for their originally intended use'),
('basel_a', N'A4040', N'Wastes from the manufacture, formulation and use of wood-preserving chemicals[2]'),
('basel_a', N'A4050', N'Wastes that contain, consist of or are contaminated with any of the following: Inorganic cyanides, excepting precious-metal-bearing residues in solid form containing traces of inorganic cyanides, Organic cyanides'),
('basel_a', N'A4060', N'Waste oils/water, hydrocarbons/water mixtures, emulsions'),
('basel_a', N'A4070', N'Wastes from the production, formulation and use of inks, dyes, pigments, paints, lacquers, varnish excluding any such waste specified on list B (note the related entry on list B B4010)'),
('basel_a', N'A4080', N'Wastes of an explosive nature (but excluding such wastes specified on list B)'),
('basel_a', N'A4090', N'Waste acidic or basic solutions, other than those specified in the corresponding entry on list B (note the related entry on list B B2120)'),
('basel_a', N'A4100', N'Wastes from industrial pollution control devices for cleaning of industrial off-gases but excluding such wastes specified on list B'),
('basel_a', N'A4110', N'Wastes that contain, consist of or are contaminated with any of the following: Any congenor of polychlorinated dibenzo-furan, Any congenor of polychlorinated dibenzo-dioxin'),
('basel_a', N'A4120', N'Wastes that contain, consist of or are contaminated with peroxides'),
('basel_a', N'A4130', N'Waste packages and containers containing Annex I substances in concentrations sufficient to exhibit Annex III hazard characteristics'),
('basel_a', N'A4140', N'Waste consisting of or containing off specification or outdated[3] chemicals corresponding to Annex I categories and exhibiting Annex III hazard characteristics'),
('basel_a', N'A4150', N'Waste chemical substances arising from research and development or teaching activities which are not identified and/or are new and whose effects on human health and/or the environment are not known'),
('basel_a', N'A4160', N'Spent activated carbon not included on list B (note the related entry on list B B2060)'),
('basel_a', N'Y46', N'Wastes collected from households'),
('basel_a', N'Y47', N'Residues arising from the incineration of household wastes'),
('basel_a', N'Y48', N'Categories of waste requiring special consideration: Plastic wastes - non-hazardous'),
('basel_a', N'Y49', N'Electrical and electronic waste - non-hazardous'),
('basel_b', N'B1010', N'Metal and metal-alloy wastes in metallic, non-dispersible form. See list of metals in Annex IX List B'),
('basel_b', N'B1020', N'Clean, uncontaminated metal scrap, including alloys, in bulk finished form (sheet, plate, beams, rods, etc), of: Antimony scrap, Beryllium scrap, Cadmium scrap, Lead scrap (but excluding lead-acid batteries), Selenium scrap, Tellurium scrap'),
('basel_b', N'B1030', N'Refractory metals containing residues'),
('basel_b', N'B1031', N'Molybdenum, tungsten, titanium, tantalum, niobium and rhenium metal and metal alloy wastes in metallic dispersible form (metal powder), excluding such wastes as specified in list A under entry A1050, Galvanic sludges'),
('basel_b', N'B1040', N'Scrap assemblies from electrical power generation not contaminated with lubricating oil, PCB or PCT to an extent to render them hazardous'),
('basel_b', N'B1050', N'Mixed non-ferrous metal, heavy fraction scrap, not containing Annex I materials in concentrations sufficient to exhibit Annex III characteristics[1]'),
('basel_b', N'B1060', N'Waste selenium and tellurium in metallic elemental form including powder'),
('basel_b', N'B1070', N'Waste of copper and copper alloys in dispersible form, unless they contain Annex I constituents to an extent that they exhibit Annex III characteristics'),
('basel_b', N'B1080', N'Zinc ash and residues including zinc alloys residues in dispersible form unless containing Annex I constituents in concentration such as to exhibit Annex III characteristics or exhibiting hazard characteristic H4.3[2]'),
('basel_b', N'B1090', N'Waste batteries conforming to a specification, excluding those made with lead, cadmium or mercury'),
('basel_b', N'B1100', N'Metal-bearing wastes arising from melting, smelting and refining of metals. See list in Annex'),
('basel_b', N'B1110', N'Electrical and electronic assemblies. See details in Annex'),
('basel_b', N'B1115', N'Waste metal cables coated or insulated with plastics, not included in list A1190, excluding those destined for Annex IVA operations or any other disposal operations involving, at any stage, uncontrolled thermal processes, such as open-burning.'),
('basel_b', N'B1120', N'Spent catalysts excluding liquids used as catalysts, containing any of: Transition metals, excluding waste catalysts (spent catalysts, liquid used catalysts or other catalysts) on list A (see Annex) and Lanthanides (rare earth metals) (see Annex).'),
('basel_b', N'B1130', N'Cleaned spent precious-metal-bearing catalysts'),
('basel_b', N'B1140', N'Precious-metal-bearing residues in solid form which contain traces of inorganic cyanides'),
('basel_b', N'B1150', N'Precious metals and alloy wastes (gold, silver, the platinum group, but not mercury) in a dispersible, non-liquid form with appropriate packaging and labelling'),
('basel_b', N'B1160', N'Precious-metal ash from the incineration of printed circuit boards (note the related entry on list A A1150)'),
('basel_b', N'B1170', N'Precious-metal ash from the incineration of photographic film'),
('basel_b', N'B1180', N'Waste photographic film containing silver halides and metallic silver'),
('basel_b', N'B1190', N'Waste photographic paper containing silver halides and metallic silver'),
('basel_b', N'B1200', N'Granulated slag arising from the manufacture of iron and steel'),
('basel_b', N'B1210', N'Slag arising from the manufacture of iron and steel including slags as a source of TiO2 and vanadium'),
('basel_b', N'B1220', N'Slag from zinc production, chemically stabilized, having a high iron content (above 20%) and processed according to industrial specifications (e.g., DIN 4301) mainly for construction'),
('basel_b', N'B1230', N'Mill scaling arising from the manufacture of iron and steel'),
('basel_b', N'B1240', N'Copper oxide mill-scale'),
('basel_b', N'B1250', N'Waste end-of-life motor vehicles, containing neither liquids nor other hazardous components'),
('basel_b', N'B2010', N'Wastes from mining operations in non-dispersible form (see list in Annex)'),
('basel_b', N'B2020', N'Glass waste in non-dispersible form: Cullet and other waste and scrap of glass except for glass from cathode-ray tubes and other activated glasses'),
('basel_b', N'B2030', N'Ceramic wastes in non-dispersible form: Cermet wastes and scrap (metal ceramic composites), Ceramic based fibres not elsewhere specified or included'),
('basel_b', N'B2040', N'Other wastes containing principally inorganic constituents (See list in Annex)'),
('basel_b', N'B2050', N'Coal-fired power plant fly-ash, not included on list A (note the related entry on list A A2060)'),
('basel_b', N'B2060', N'Spent activated carbon not containing any Annex I constituents to an extent they exhibit Annex III characteristics (note the related entry on list A, A4160)'),
('basel_b', N'B2070', N'Calcium fluoride sludge'),
('basel_b', N'B2080', N'Waste gypsum arising from chemical industry processes not included on list A (note the related entry on list A A2040)'),
('basel_b', N'B2090', N'Waste anode butts from steel or aluminium production made of petroleum coke or bitumen and cleaned to normal industry specifications (excluding anode butts from chlor alkali electrolyses and from metallurgical industry)'),
('basel_b', N'B2100', N'Waste hydrates of aluminium and waste alumina and residues from alumina production excluding such materials used for gas cleaning, flocculation or filtration processes'),
('basel_b', N'B2110', N'Bauxite residue (“red mud”) (pH moderated to less than 11.5)'),
('basel_b', N'B2120', N'Waste acidic or basic solutions with a pH greater than 2 and less than 11.5, which are not corrosive or otherwise hazardous (note the related entry on list A A4090)'),
('basel_b', N'B2130', N'Bituminous material (asphalt waste) from road construction and maintenance, not containing tar[1] (note the related entry on list A, A3200)'),
('basel_b', N'B3010', N'Solid plastic waste: Plastic or mixed plastic materials: Scrap plastic of non-halogenated polymers and co-polymers, Cured waste resins or condensation products , Fluorinated polymer wastes[2] (see lists and details in Annex)'),
('basel_b', N'B3011', N'Plastic waste (note the related entry A3210, in list A of this Part, and entry Y48, in list A of Part 3)'),
('basel_b', N'B3020', N'Paper, paperboard and paper product wastes. The following materials, provided they are not mixed with hazardous wastes: See list in Annex'),
('basel_b', N'B3026', N'The following waste from the pre-treatment of composite packaging for liquids, not containing Annex I materials in concentrations sufficient to exhibit Annex III characteristics: — Non-separable plastic fraction — Non-separable plastic-aluminium fraction'),
('basel_b', N'B3027', N'Self-adhesive label laminate waste containing raw materials used in label material production'),
('basel_b', N'B3030', N'Textile wastes (see details in Annex)'),
('basel_b', N'B3035', N'Waste textile floor coverings, carpets'),
('basel_b', N'B3040', N'Rubber wastes. The following materials, provided they are not mixed with other wastes: Waste and scrap of hard rubber (e.g., ebonite), Other rubber wastes (excluding such wastes specified elsewhere)'),
('basel_b', N'B3050', N'Untreated cork and wood waste: Wood waste and scrap, whether or not agglomerated in logs, briquettes, pellets or similar forms, Cork waste: crushed, granulated or ground cork'),
('basel_b', N'B3060', N'Wastes arising from agro-food industries provided it is not infectious (see list in Annex)'),
('basel_b', N'B3065', N'Waste edible fats and oils of animal or vegetable origin (e.g. frying oils), provided they do not exhibit an Annex III characteristic'),
('basel_b', N'B3070', N'The following wastes: Waste of human hair, Waste straw, Deactivated fungus mycelium from penicillin production to be used as animal feed'),
('basel_b', N'B3080', N'Waste parings and scrap of rubber'),
('basel_b', N'B3090', N'Paring and other wastes of leather or of composition leather not suitable for the manufacture of leather articles, excluding leather sludges, not containing hexavalent chromium compounds and biocides (note the related entry on list A A3100)'),
('basel_b', N'B3100', N'Leather dust, ash, sludges or flours not containing hexavalent chromium compounds or biocides (note the related entry on list A A3090)'),
('basel_b', N'B3110', N'Fellmongery wastes not containing hexavalent chromium compounds or biocides or infectious substances (note the related entry on list A A3110)'),
('basel_b', N'B3120', N'Wastes consisting of food dyes'),
('basel_b', N'B3130', N'Waste polymer ethers and waste non-hazardous monomer ethers incapable of forming peroxides'),
('basel_b', N'B3140', N'Waste pneumatic tyres, excluding those destined for Annex IVA operations'),
('basel_b', N'B4010', N'Wastes consisting mainly of water-based/latex paints, inks and hardened varnishes not containing organic solvents, heavy metals or biocides to an extent to render them hazardous (note the related entry on list A A4070)'),
('basel_b', N'B4020', N'Wastes from production, formulation and use of resins, latex, plasticizers, glues/adhesives, not listed on list A, free of solvents and other contaminants to an extent that they do not exhibit Annex III characteristics'),
('basel_b', N'B4030', N'Used single-use cameras, with batteries not included on list A'),
('oecd', N'GB040', N'Slags from precious metals and copper processing for further refining'),
('oecd', N'GC010', N'Electrical assemblies consisting only of metals or alloys.'),
('oecd', N'GC020', N'Electronic scrap (e.g. printed circuit boards, electronic components, wire, etc.) and reclaimed electronic components suitable for base and precious metal recovery.'),
('oecd', N'GC030', N'Vessels and other floating structures for breaking up, properly emptied of any cargo and other materials arising from the operation of the vessel which may have been classified as a dangerous substance or waste'),
('oecd', N'GC050', N'Spent Fluid Catalytic Cracking (FCC) Catalysts (e.g.: aluminium oxide, zeolites)'),
('oecd', N'GE020', N'Glass fibre wastes'),
('oecd', N'GF010', N'Ceramic wastes which have been fired after shaping, including ceramic vessels (before and/or after use)'),
('oecd', N'GG030', N'Bottom ash and slag tap from coal fired power plants'),
('oecd', N'GG040', N'Coal fired power plants fly ash'),
('oecd', N'GH013', N'Polymers of vinyl chloride'),
('oecd', N'GN010', N'Waste of pigs’, hogs’ or boars’ bristles and hair or of badger hair and other brush making hair'),
('oecd', N'GN020', N'Horsehair waste, whether or not put up as a layer with or without supporting material'),
('oecd', N'GN030', N'Waste of skins and other parts of birds, with their feathers or down, of feathers and parts of feathers (whether or not with trimmed edges) and down, not further worked than cleaned, disinfected or treated for preservation'),
('oecd', N'AA010', N'Dross, scalings and other wastes from the manufacture of iron and steel'),
('oecd', N'AA060', N'Vanadium ashes and residues'),
('oecd', N'AA190', N'Magnesium waste and scrap that is flammable, pyrophoric or emits, upon contact with water, flammable gases in dangerous quantities'),
('oecd', N'AB030', N'Wastes from non-cyanide based systems which arise from surface treatment of metals'),
('oecd', N'AB070', N'Sands used in foundry operations'),
('oecd', N'AB120', N'Inorganic halide compounds, not elsewhere specified or included'),
('oecd', N'AB130', N'Used blasting grit'),
('oecd', N'AB150', N'Unrefined calcium sulphite and calcium sulphate from flue gas desulphurisation (FGD)'),
('oecd', N'AC060', N'Hydraulic fluids'),
('oecd', N'AC070', N'Brake fluids'),
('oecd', N'AC080', N'Antifreeze fluids'),
('oecd', N'AC150', N'Chlorofluorocarbons'),
('oecd', N'AC160', N'Halons'),
('oecd', N'AC170', N'Treated cork and wood wastes'),
('oecd', N'AC250', N'Surface active agents (surfactants)'),
('oecd', N'AC260', N'Liquid pig manure; faeces'),
('oecd', N'AC270', N'Sewage sludge'),
('oecd', N'AC300', N'Plastic waste, including mixtures of such wastes, containing or contaminated with Annex I constituents, to an extent that it exhibits an Annex III characteristic (note the related entry EU3011 in part I of Annex III, and the related entry EU48 in part I)'),
('oecd', N'AD090', N'Wastes from production, formulation and use of reprographic and photographic chemicals and materials not elsewhere specified or included'),
('oecd', N'AD100', N'Wastes from non-cyanide based systems which arise from surface treatment of plastics'),
('oecd', N'AD120', N'Ion exchange resins'),
('oecd', N'AD150', N'Naturally occurring organic material used as a filter medium (such as bio-filters)'),
('oecd', N'RB020', N'Ceramic based fibres of physico-chemical characteristics similar to those of asbestos.'),
('wsr_a3a', N'IIIA.2.a', N'“mixtures of wastes classified under Basel entries B1010 and B1050”'),
('wsr_a3a', N'IIIA.2.b', N'“mixtures of wastes classified under Basel entries B1010 and B1070”'),
('wsr_a3a', N'IIIA.2.c', N'“mixtures of wastes classified under Basel entries B3040 and B3080”'),
('wsr_a3a', N'IIIA.2.d', N'“mixtures of wastes classified under (OECD) entry GB040 and under Basel entry B1100 restricted to hard zinc spelter, zinc-containing drosses, aluminium skimmings (or skims) excluding salt slag and wastes of refractory linings, including crucibles, originating from copper smelting”'),
('wsr_a3a', N'IIIA.2.e', N'“mixtures of wastes classified under (OECD) entry GB040, under Basel entry B1070 and under Basel entry B1100 restricted to wastes of refractory linings, including crucibles, originating from copper smelting”'),
('wsr_a3a', N'IIIA.3.a', N'“mixtures of wastes classified under Basel entry B1010”'),
('wsr_a3a', N'IIIA.3.b', N'“mixtures of wastes classified under Basel entry B2010”'),
('wsr_a3a', N'IIIA.3.c', N'“mixtures of wastes classified under Basel entry B2030”'),
('wsr_a3a', N'IIIA.3.d', N'“mixtures of wastes classified under Basel entry B3020 restricted to unbleached paper or paperboard or of corrugated paper or paperboard, other paper or paperboard, made mainly of bleached chemical pulp, not coloured in the mass, paper or paperboard made mainly of mechanical pulp (for example, newspapers, journals and similar printed matter)”'),
('wsr_a3a', N'IIIA.3.e', N'“mixtures of wastes classified under Basel entry B3030”'),
('wsr_a3a', N'IIIA.3.f', N'“mixtures of wastes classified under Basel entry B3040”'),
('wsr_a3a', N'IIIA.3.g', N'“mixtures of wastes classified under Basel entry B3050”'),
('wsr_a3a', N'IIIA.4.a', N'“mixtures of wastes classified under entry EU3011 and listed under the indent referring to non-halogenated polymers”'),
('wsr_a3a', N'IIIA.4.b', N'“mixtures of wastes classified under entry EU3011 and listed under the indent referring to cured resins or condensation products”'),
('wsr_a3a', N'IIIA.4.c', N'“mixtures of wastes classified under entry EU3011 and listed under ‘perfluoroalkoxy alkanes’”'),
('wsr_a3b', N'BEU04', N'Composite packaging consisting of mainly paper and some plastic, not containing residues and not covered by Basel entry B3020'),
('wsr_a3b', N'BEU05', N'Clean biodegradable waste from agriculture, horticulture, forestry, gardens, parks and cemeteries')
) AS s (Lista, Codice, Descrizione)
ON t.Lista = s.Lista AND t.Codice = s.Codice
WHEN MATCHED AND ISNULL(t.Descrizione, N'') <> ISNULL(s.Descrizione, N'') THEN UPDATE SET Descrizione = s.Descrizione
WHEN NOT MATCHED BY TARGET THEN INSERT (Lista, Codice, Descrizione) VALUES (s.Lista, s.Codice, s.Descrizione);
GO
MERGE dbo.tblDiwassCodiciRifiutiEer AS t
USING (
	SELECT v.IdEer, v.Lista, v.Codice, v.Pos
	FROM (VALUES
('150101', 'basel_b', N'B3020', 1),
('150102', 'basel_b', N'B3011', 1),
('150103', 'basel_b', N'B3050', 1),
('150104', 'basel_b', N'B1010', 1),
('150105', 'wsr_a3b', N'BEU04', 1),
('150107', 'basel_b', N'B2020', 1),
('150109', 'basel_b', N'B3030', 1),
('030105', 'basel_b', N'B3050', 1),
('040222', 'basel_b', N'B3030', 1),
('070213', 'basel_b', N'B3011', 1),
('120101', 'basel_b', N'B1010', 1),
('120103', 'basel_b', N'B1010', 1),
('120105', 'basel_b', N'B3011', 1),
('160103', 'basel_b', N'B3140', 1),
('160117', 'basel_b', N'B1010', 1),
('160118', 'basel_b', N'B1010', 1),
('160119', 'basel_b', N'B3011', 1),
('160120', 'basel_b', N'B2020', 1),
('160214', 'basel_b', N'B1110', 1),
('160214', 'oecd', N'GC020', 2),
('170201', 'basel_b', N'B3050', 1),
('170202', 'basel_b', N'B2020', 1),
('170203', 'basel_b', N'B3011', 1),
('170401', 'basel_b', N'B1010', 1),
('170402', 'basel_b', N'B1010', 1),
('170403', 'basel_b', N'B1020', 1),
('170404', 'basel_b', N'B1010', 1),
('170405', 'basel_b', N'B1010', 1),
('170406', 'basel_b', N'B1010', 1),
('170407', 'basel_b', N'B1010', 1),
('170411', 'basel_b', N'B1115', 1),
('191001', 'basel_b', N'B1010', 1),
('191002', 'basel_b', N'B1010', 1),
('191201', 'basel_b', N'B3020', 1),
('191202', 'basel_b', N'B1010', 1),
('191203', 'basel_b', N'B1010', 1),
('191204', 'basel_b', N'B3011', 1),
('191204', 'basel_b', N'B3080', 2),
('191205', 'basel_b', N'B2020', 1),
('191207', 'basel_b', N'B3050', 1),
('191208', 'basel_b', N'B3030', 1),
('200101', 'basel_b', N'B3020', 1),
('200102', 'basel_b', N'B2020', 1),
('200110', 'basel_b', N'B3030', 1),
('200111', 'basel_b', N'B3030', 1),
('200138', 'basel_b', N'B3050', 1),
('200139', 'basel_b', N'B3011', 1),
('200140', 'basel_b', N'B1010', 1)
	) v (IdEer, Lista, Codice, Pos)
	INNER JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
	INNER JOIN dbo.tblDiwassCodiciRifiuti c ON v.Lista = c.Lista AND v.Codice = c.Codice
) AS s
ON t.IdEer = s.IdEer AND t.Lista = s.Lista AND t.Codice = s.Codice
WHEN MATCHED AND ISNULL(t.Pos, 0) <> s.Pos THEN UPDATE SET Pos = s.Pos
WHEN NOT MATCHED BY TARGET THEN INSERT (IdEer, Lista, Codice, Pos) VALUES (s.IdEer, s.Lista, s.Codice, s.Pos);
GO

-- ===== 2. Struttura e configurazione
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Allegato VII (documento della spedizione di rifiuti della lista verde, DIWASS). Chi organizza la spedizione è
-- l'azienda interna (IdAziendaInterna), con la sua credenziale DIWASS. Bozza in Ecomatico finché Stato è NULL;
-- dopo l'invio Numero e Stato sono quelli di DIWASS (ANNOUNCED, MOVING, RECEIVED, COMPLETED, CANCELLED, TAKE_BACK)
IF OBJECT_ID('dbo.tblDiwassAllegatiVii', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblDiwassAllegatiVii (
		Id CHAR(16) NOT NULL,
		IdAziendaInterna CHAR(16) NOT NULL,
		IdRegistrazione CHAR(16) NULL,
		Numero VARCHAR(50) NULL,
		Stato VARCHAR(20) NULL,
		DataInvio SMALLDATETIME NULL,
		DataStato SMALLDATETIME NULL,
		TipoDestinazione CHAR(1) NULL,
		DataSpedizione DATE NULL,
		Quantita DECIMAL(18, 5) NULL,
		UnitaQuantita CHAR(1) NULL,
		Contenitore VARCHAR(100) NULL,
		LuogoPartenza VARCHAR(300) NULL,
		ResponsabileNome VARCHAR(100) NULL,
		ResponsabileTelefono VARCHAR(50) NULL,
		ResponsabileEmail VARCHAR(100) NULL,
		IdEer CHAR(6) NULL,
		Descrizione VARCHAR(500) NULL,
		CodiceDoganale VARCHAR(50) NULL,
		IdNazioneSpedizione CHAR(3) NULL,
		IdNazioneDestinazione CHAR(3) NULL,
		IdNazioneTransito1 CHAR(3) NULL,
		IdNazioneTransito2 CHAR(3) NULL,
		IdAttivita CHAR(2) NULL,
		ListaCodice VARCHAR(10) NULL,
		Codice NVARCHAR(20) NULL,
		FirmaNome VARCHAR(100) NULL,
		FirmaRuolo VARCHAR(100) NULL,
		FirmaEmail VARCHAR(100) NULL,
		FirmaData DATETIME2(0) NULL,
		ProduttoreFirmaNome VARCHAR(100) NULL,
		ProduttoreFirmaRuolo VARCHAR(100) NULL,
		ProduttoreFirmaData DATETIME2(0) NULL,
		Note VARCHAR(500) NULL,
		Lock TINYINT NULL,
		DaInviare BIT NULL,
		CONSTRAINT PK_tblDiwassAllegatiVii PRIMARY KEY CLUSTERED (Id ASC),
		CONSTRAINT FK_tblDiwassAllegatiVii_tblSediInterne FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id),
		CONSTRAINT FK_tblDiwassAllegatiVii_tblRifiutiRegistrazioni FOREIGN KEY (IdRegistrazione) REFERENCES dbo.tblRifiutiRegistrazioni (Id),
		CONSTRAINT FK_tblDiwassAllegatiVii_tblRifiutiEer FOREIGN KEY (IdEer) REFERENCES dbo.tblRifiutiEer (Id),
		CONSTRAINT FK_tblDiwassAllegatiVii_tblRifiutiAttivitaRecuperoSmaltimento FOREIGN KEY (IdAttivita) REFERENCES dbo.tblRifiutiAttivitaRecuperoSmaltimento (Id),
		CONSTRAINT FK_tblDiwassAllegatiVii_tblDiwassCodiciRifiuti FOREIGN KEY (ListaCodice, Codice) REFERENCES dbo.tblDiwassCodiciRifiuti (Lista, Codice)
	);
	CREATE NONCLUSTERED INDEX IX_DiwassAllegatiVii_IdAziendaInterna_Lock ON dbo.tblDiwassAllegatiVii (IdAziendaInterna ASC, Lock ASC);
	CREATE NONCLUSTERED INDEX IX_DiwassAllegatiVii_IdRegistrazione ON dbo.tblDiwassAllegatiVii (IdRegistrazione ASC);
END
GO
-- Soggetti dell'Allegato VII: Ruolo O chi organizza (l'azienda), P produttore, D destinatario, I impianto di recupero
-- o laboratorio, T trasportatore (Pos 1..3). PartyUuid è l'identificativo del soggetto nel documento DIWASS (PartyUUID)
IF OBJECT_ID('dbo.tblDiwassAllegatiViiSoggetti', 'U') IS NULL
	CREATE TABLE dbo.tblDiwassAllegatiViiSoggetti (
		Id CHAR(16) NOT NULL,
		Ruolo CHAR(1) NOT NULL,
		Pos TINYINT NOT NULL,
		IdSede CHAR(16) NOT NULL,
		PartyUuid UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_tblDiwassAllegatiViiSoggetti_PartyUuid DEFAULT (NEWID()),
		ContattoNome VARCHAR(100) NULL,
		ContattoTelefono VARCHAR(50) NULL,
		ContattoEmail VARCHAR(100) NULL,
		MezzoTrasporto CHAR(1) NULL,
		ImpiantoIntermedio BIT NULL,
		NomeRiservato BIT NULL,
		MotivoRiservatezza VARCHAR(500) NULL,
		CONSTRAINT PK_tblDiwassAllegatiViiSoggetti PRIMARY KEY CLUSTERED (Id ASC, Ruolo ASC, Pos ASC),
		CONSTRAINT FK_tblDiwassAllegatiViiSoggetti_tblDiwassAllegatiVii FOREIGN KEY (Id) REFERENCES dbo.tblDiwassAllegatiVii (Id),
		CONSTRAINT FK_tblDiwassAllegatiViiSoggetti_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id)
	);
GO
-- Ultimo codice internazionale usato per un EER dall'azienda e ultimo ruolo di firma dell'utente per l'azienda:
-- proposti nei nuovi Allegati VII
IF OBJECT_ID('dbo.tblDiwassCodiciRifiutiUsati', 'U') IS NULL
	CREATE TABLE dbo.tblDiwassCodiciRifiutiUsati (
		IdAziendaInterna CHAR(16) NOT NULL,
		IdEer CHAR(6) NOT NULL,
		Lista VARCHAR(10) NOT NULL,
		Codice NVARCHAR(20) NOT NULL,
		Data SMALLDATETIME NOT NULL,
		CONSTRAINT PK_tblDiwassCodiciRifiutiUsati PRIMARY KEY CLUSTERED (IdAziendaInterna ASC, IdEer ASC),
		CONSTRAINT FK_tblDiwassCodiciRifiutiUsati_tblSediInterne FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id),
		CONSTRAINT FK_tblDiwassCodiciRifiutiUsati_tblDiwassCodiciRifiuti FOREIGN KEY (Lista, Codice) REFERENCES dbo.tblDiwassCodiciRifiuti (Lista, Codice)
	);
GO
IF OBJECT_ID('dbo.tblDiwassFirmeRuoli', 'U') IS NULL
	CREATE TABLE dbo.tblDiwassFirmeRuoli (
		IdUtente CHAR(16) NOT NULL,
		IdAziendaInterna CHAR(16) NOT NULL,
		Ruolo VARCHAR(100) NOT NULL,
		CONSTRAINT PK_tblDiwassFirmeRuoli PRIMARY KEY CLUSTERED (IdUtente ASC, IdAziendaInterna ASC),
		CONSTRAINT FK_tblDiwassFirmeRuoli_tblUtenti FOREIGN KEY (IdUtente) REFERENCES dbo.tblUtenti (Id),
		CONSTRAINT FK_tblDiwassFirmeRuoli_tblSediInterne FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id)
	);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'DWA')
	INSERT INTO dbo.tblFunzioni (Id, Nome, [Master], Admin, Attiva) VALUES ('DWA', 'Allegati VII DIWASS', 0, 0, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'DWS' AND IdFunzione = 'DWA')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('DWS', 'DWA');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'DWA')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('DWA', 'DWA', 'Allegati VII', 'allegati-vii');
-- Allegati VII prima di Operatori e Credenziali (lavoro quotidiano in cima)
UPDATE dbo.tblMenu SET Pos = 1 WHERE Id = 'AL2';
UPDATE dbo.tblMenu SET Pos = 2 WHERE Id = 'AL1';
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AL3')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AL3', 'AL0', NULL, 'DWA', 0);
GO

IF COL_LENGTH('dbo.tblDiwassAllegatiVii', 'DaInviare') IS NULL
	ALTER TABLE dbo.tblDiwassAllegatiVii ADD DaInviare BIT NULL;
GO
-- ===== 3. ufnDiwassAllegatiVii_get_StatoDescrizione
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stato dell'Allegato VII in italiano: NULL = bozza in Ecomatico, gli altri sono gli stati di DIWASS
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_StatoDescrizione] (
	@Stato VARCHAR(20))
RETURNS VARCHAR(50)
WITH SCHEMABINDING
AS
BEGIN
	RETURN CASE @Stato
		WHEN 'ANNOUNCED' THEN 'Annunciato'
		WHEN 'MOVING' THEN 'In viaggio'
		WHEN 'RECEIVED' THEN 'Ricevuto'
		WHEN 'COMPLETED' THEN 'Completato'
		WHEN 'CANCELLED' THEN 'Annullato'
		WHEN 'TAKE_BACK' THEN 'Ripresa'
		ELSE ISNULL(@Stato, 'Bozza')
	END;
END;
GO

-- ===== 3. ufnDiwassAllegatiVii_get_SedeCollegata
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sede da indicare nell'Allegato VII per una sede di Ecomatico: la sede stessa se è collegata a DIWASS, altrimenti
-- la sua azienda se collegata (Sostituita = 1: sul documento comparirà l'azienda, docs/regole/diwass.md D4.2).
-- Nessuna riga se né la sede né l'azienda sono collegate. Solo operatori con il ruolo WSR nuovo o valido
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_SedeCollegata] (
	@IdSede CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT TOP 1
		IdSede = c.Id,
		Sostituita = c.Sostituita
	FROM (
		SELECT
			o.Id,
			Sostituita = CAST(0 AS BIT),
			Ordine = 0
		FROM dbo.tblDiwassOperatori o
		WHERE
			o.Id = @IdSede
			AND o.Stato IN ('NEW', 'VALID')
		UNION ALL
		SELECT
			o.Id,
			Sostituita = CAST(1 AS BIT),
			Ordine = 1
		FROM
			dbo.tblSedi s
			INNER JOIN dbo.tblDiwassOperatori o ON s.IdParent = o.Id
		WHERE
			s.Id = @IdSede
			AND o.Stato IN ('NEW', 'VALID')
	) c
	ORDER BY c.Ordine
);
GO

-- ===== 3. ufnDiwassAllegatiVii_get_Contatto
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Contatto proposto per un soggetto dell'Allegato VII (obbligatorio su DIWASS): la prima persona attiva della sede e il
-- primo telefono e la prima email tra i recapiti della sede
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_Contatto] (
	@IdSede CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		Nome = (
			SELECT TOP 1 p.NomeCompleto
			FROM dbo.tblPersone p
			WHERE
				p.IdSede = @IdSede
				AND p.Lock = 0
				AND ISNULL(p.Disabilitata, 0) = 0
			ORDER BY p.NomeCompleto
		),
		Telefono = (
			SELECT TOP 1 r.Valore
			FROM dbo.tblSediRecapiti r
			WHERE
				r.Id = @IdSede
				AND r.IdRecapito LIKE 'T%'
				AND r.Valore IS NOT NULL
			ORDER BY r.IdRecapito
		),
		Email = (
			SELECT TOP 1 r.Valore
			FROM dbo.tblSediRecapiti r
			WHERE
				r.Id = @IdSede
				AND r.IdRecapito LIKE 'M%'
				AND r.Valore IS NOT NULL
			ORDER BY r.IdRecapito
		)
);
GO

-- ===== 3. uspDiwassAllegatiVii_del
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancella un Allegato VII: solo le bozze, mai uno già inviato a DIWASS (si annulla su DIWASS)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: un @Id mai esistito è trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDiwassAllegatiVii
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN
			-- Controlla il permesso sul record (titolarità): azienda del contesto
			DECLARE @lock INT;
			DECLARE @stato VARCHAR(20);
			SELECT
				@lock = a.Lock,
				@stato = a.Stato
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione;

			IF @lock IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
			IF @stato IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un Allegato VII inviato a DIWASS non si cancella: annullarlo su DIWASS';
				GOTO BRANCH_END;
			END

			-- ── CASO 1: bozza salvata (Lock = 0) → soft delete ─────────────────────
			IF @lock = 0
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblDiwassAllegatiVii
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Allegato VII non trovato o già eliminato';
						GOTO BRANCH_END;
					END

					IF @Reset = 1
						DELETE dbo.tblIdCancellati
						WHERE IdSessione = @IdSessione;
					ELSE
						DELETE dbo.tblIdCancellati
						WHERE Id = @Id;

					INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
					VALUES (@Id, @IdSessione, GETDATE());
				COMMIT TRANSACTION;

				EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
			END

			-- ── CASO 2: nuovo mai salvato (Lock = 2) → hard delete ─────────────────
			ELSE IF @lock = 2
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblDiwassAllegatiViiSoggetti
					WHERE Id = @Id;
					DELETE dbo.tblDiwassAllegatiVii
					WHERE Id = @Id;
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;
					DELETE dbo.tblIdLog
					WHERE Id = @Id;
					DELETE dbo.tblId
					WHERE Id = @Id;
				COMMIT TRANSACTION;
			END

			-- ── CASO 3: Lock in stato non gestito ───────────────────────────────────
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''Allegato VII è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
				GOTO BRANCH_END;
			END
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

-- ===== 3. uspDiwassAllegatiVii_del_Undo
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_del_Undo]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblDiwassAllegatiVii i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

-- ===== 3. uspDiwassAllegatiVii_get
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'Allegato VII (i soggetti in uspDiwassAllegatiVii_get_Soggetti). Modificabile: bozza o annunciato su
-- DIWASS (dopo la partenza DIWASS non ammette modifiche)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND a.Lock <= 2
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			a.IdAziendaInterna,
			AziendaNome = s.NomeCompleto,
			a.IdRegistrazione,
			RegistrazioneNumero = r.Numero,
			RegistrazioneData = r.Data,
			a.Numero,
			a.Stato,
			StatoDescrizione = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			Modificabile = CAST(IIF(a.Stato IS NULL OR a.Stato = 'ANNOUNCED', 1, 0) AS BIT),
			a.DaInviare,
			a.DataInvio,
			a.DataStato,
			a.TipoDestinazione,
			a.DataSpedizione,
			a.Quantita,
			a.UnitaQuantita,
			a.Contenitore,
			a.LuogoPartenza,
			a.ResponsabileNome,
			a.ResponsabileTelefono,
			a.ResponsabileEmail,
			a.IdEer,
			EerNome = e.Nome,
			a.Descrizione,
			a.CodiceDoganale,
			a.IdNazioneSpedizione,
			a.IdNazioneDestinazione,
			a.IdNazioneTransito1,
			a.IdNazioneTransito2,
			a.IdAttivita,
			Codice = IIF(a.Codice IS NULL, NULL, a.ListaCodice + '|' + a.Codice),
			a.FirmaNome,
			a.FirmaRuolo,
			a.FirmaEmail,
			a.FirmaData,
			a.ProduttoreFirmaNome,
			a.ProduttoreFirmaRuolo,
			a.ProduttoreFirmaData,
			a.Note,
			a.Lock
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSedi s ON a.IdAziendaInterna = s.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON a.IdRegistrazione = r.Id
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
		WHERE a.Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_get_Codici_SelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Codici internazionali del rifiuto per l'Allegato VII (Id = "lista|codice"): prima i suggeriti per l'EER
-- (tblDiwassCodiciRifiutiEer), poi tutti gli altri della lista verde (Basel B, OCSE G.., allegati IIIA e IIIB: i codici OCSE A..
-- e R.. sono della lista ambra, fuori dall'Allegato VII)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Codici_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdSelected NVARCHAR(40) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST('' AS NVARCHAR(40)),
				[Text] = CAST(N'(Selezionare)' AS NVARCHAR(300)),
				Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
				Gruppo = 0,
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi: suggeriti (Gruppo 1) e altri (Gruppo 2)

			SELECT
				Id = CAST(c.Lista + '|' + c.Codice AS NVARCHAR(40)),
				[Text] = CAST(IIF(g.IdEer IS NULL, N'', N'★ ') + c.Codice + N' - ' + LEFT(c.Descrizione, 200) AS NVARCHAR(300)),
				Selected = CAST(IIF(c.Lista + '|' + c.Codice = @IdSelected, 1, 0) AS BIT),
				Gruppo = IIF(g.IdEer IS NULL, 2, 1),
				Pos = ISNULL(g.Pos, 0)
			FROM
				dbo.tblDiwassCodiciRifiuti c
				LEFT JOIN dbo.tblDiwassCodiciRifiutiEer g ON c.Lista = g.Lista AND c.Codice = g.Codice AND g.IdEer = @IdEer
			WHERE
				(c.Lista IN ('basel_b', 'wsr_a3a', 'wsr_a3b') OR (c.Lista = 'oecd' AND c.Codice LIKE 'G%'))
				OR c.Lista + '|' + c.Codice = @IdSelected
		)
		SELECT
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Gruppo, Pos, Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_get_Esportazione
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Allegati VII: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassAllegatiVii_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassAllegatiVii_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Numero DIWASS] = a.Numero,
			[Stato] = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato) + IIF(a.DaInviare = 1, ' - modifiche da inviare a DIWASS', ''),
			[Data della spedizione] = a.DataSpedizione,
			[EER] = e.Nome,
			[Codice internazionale] = a.Codice,
			[Descrizione] = a.Descrizione,
			[Quantità] = a.Quantita,
			[Unità] = IIF(a.UnitaQuantita = 'M', 'm³', 't'),
			[Destinatario] = d.NomeCompleto,
			[Paese di spedizione] = ns.Nome,
			[Paese di destinazione] = n.Nome,
			[Inviato il] = a.DataInvio
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni s ON a.IdAziendaInterna = s.IdAzienda
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti x ON a.Id = x.Id AND x.Ruolo = 'D' AND x.Pos = 1
			LEFT JOIN dbo.tblSedi d ON x.IdSede = d.Id
			LEFT JOIN dbo.tblNazioni n ON a.IdNazioneDestinazione = n.Id
			LEFT JOIN dbo.tblNazioni ns ON a.IdNazioneSpedizione = ns.Id
		WHERE
			s.Id = @IdSessione
			AND a.Lock = 0
			AND
				(
				@Stato IS NULL
				OR
					(
					@Stato = 'B'
					AND a.Stato IS NULL
					)
				OR a.Stato = @Stato
				)
			AND
				(
				@Search IS NULL
				OR a.Numero LIKE '%' + @Search + '%'
				OR a.Descrizione LIKE '%' + @Search + '%'
				OR e.Nome LIKE '%' + @Search + '%'
				OR d.NomeCompleto LIKE '%' + @Search + '%'
				)
		ORDER BY a.DataSpedizione DESC, a.Id DESC
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_get_Invio
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati dell'Allegato VII da mandare all'hub DIWASS (JSON) per @Operazione: I invio, A aggiornamento, N annullamento,
-- S lettura dello stato. Per I e A controlla che il documento sia completo e restituisce in un solo messaggio tutto
-- quello che manca. La firma di chi organizza è dell'utente della sessione (nome, email) con il ruolo della scheda.
-- Restituisce rtn = JSON (assegnato a variabile, così non viene spezzato in più righe)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Invio]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Operazione CHAR(1) = NULL,
	@Motivo VARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(2000) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @Motivo = dbo.ufnStringhe_get_SenzaSpazi(@Motivo, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL OR ISNULL(@Operazione, '') NOT IN ('I', 'A', 'N', 'S')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri non validi';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF IIF(@Operazione = 'S', 1, 2) > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		DECLARE @stato VARCHAR(20);
		DECLARE @numero VARCHAR(50);
		DECLARE @lock TINYINT;
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente,
			@stato = a.Stato,
			@numero = a.Numero,
			@lock = a.Lock
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL OR @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto: salvarlo prima dell''invio';
			GOTO BRANCH_END;
		END

		-- Stato ammesso per l'operazione
		IF @Operazione = 'I' AND @stato IS NOT NULL
			SET @returnMessage = 'L''Allegato VII è già stato inviato a DIWASS';
		ELSE IF @Operazione IN ('A', 'N') AND ISNULL(@stato, '') <> 'ANNOUNCED'
			SET @returnMessage = IIF(@stato IS NULL,
				'L''Allegato VII non è ancora stato inviato a DIWASS',
				'L''Allegato VII è ' + LOWER(dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(@stato)) + ' su DIWASS: non si può più ' + IIF(@Operazione = 'A', 'modificare', 'annullare'));
		ELSE IF @Operazione = 'S' AND @numero IS NULL
			SET @returnMessage = 'L''Allegato VII non è ancora stato inviato a DIWASS';
		ELSE IF @Operazione = 'N' AND @Motivo IS NULL
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
		IF @returnMessage IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			GOTO BRANCH_END;
		END

		-- Credenziale DIWASS dell'azienda
		DECLARE @idCredenziale CHAR(16) = (
			SELECT IdDiwass
			FROM dbo.tblDiwassCredenziali
			WHERE
				IdAziendaInterna = @idAzienda
				AND Lock = 0
		);
		IF @idCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda non ha una credenziale DIWASS: chiedere all''amministratore di crearla in Diwass > Credenziali';
			GOTO BRANCH_END;
		END

		-- Firma: utente della sessione
		DECLARE @firmaNome VARCHAR(100);
		DECLARE @firmaEmail VARCHAR(100);
		SELECT
			@firmaNome = NULLIF(LTRIM(RTRIM(ISNULL(Nome, '') + ' ' + ISNULL(Cognome, ''))), ''),
			@firmaEmail = Email
		FROM dbo.tblUtenti
		WHERE Id = @idUtente;

		-- Completezza (invio e aggiornamento)
		IF @Operazione IN ('I', 'A')
		BEGIN
			DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Testo NVARCHAR(200));

			INSERT INTO @mancanti (Testo)
			SELECT x.Testo
			FROM
				dbo.tblDiwassAllegatiVii a
				CROSS APPLY (
					VALUES
						(IIF(a.DataSpedizione IS NULL, N'data della spedizione', NULL)),
						(IIF(ISNULL(a.Quantita, 0) <= 0, N'quantità', NULL)),
						(IIF(a.LuogoPartenza IS NULL, N'luogo di partenza', NULL)),
						(IIF(a.ResponsabileNome IS NULL OR a.ResponsabileTelefono IS NULL OR a.ResponsabileEmail IS NULL, N'nome, telefono ed email del responsabile del luogo di partenza', NULL)),
						(IIF(a.IdEer IS NULL, N'codice EER', NULL)),
						(IIF(a.Codice IS NULL, N'codice internazionale del rifiuto (Basel, OCSE)', NULL)),
						(IIF(a.Descrizione IS NULL, N'descrizione usuale del rifiuto', NULL)),
						(IIF(a.IdAttivita IS NULL, N'operazione di recupero', NULL)),
						(IIF(a.IdNazioneSpedizione IS NULL OR a.IdNazioneDestinazione IS NULL, N'paesi di spedizione e di destinazione', NULL)),
						(IIF(a.FirmaRuolo IS NULL, N'ruolo di chi firma', NULL)),
						(IIF(@firmaNome IS NULL OR @firmaEmail IS NULL, N'nome ed email dell''utente che firma (Impostazioni > Utenti)', NULL))
				) x (Testo)
			WHERE
				a.Id = @Id
				AND x.Testo IS NOT NULL;

			-- Operazione di recupero: deve essere una R (spedizioni della lista verde)
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblDiwassAllegatiVii a
					INNER JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON a.IdAttivita = r.Id
				WHERE
					a.Id = @Id
					AND r.Codice NOT LIKE 'R%'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'operazione di recupero (R1-R13), non di smaltimento');

			-- Soggetti obbligatori
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassOperatori
			WHERE
				Id = @idAzienda
				AND Stato IN ('NEW', 'VALID')
			)
				INSERT INTO @mancanti (Testo) VALUES (N'collegamento a DIWASS dell''azienda che organizza (Diwass > Operatori)');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'D'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'destinatario');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'I'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'impianto di recupero o laboratorio');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'T'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'almeno un trasportatore');

			INSERT INTO @mancanti (Testo)
			SELECT N'contatto (nome, telefono ed email) di ' + s.NomeCompleto
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
			WHERE
				x.Id = @Id
				AND
					(
					x.ContattoNome IS NULL
					OR x.ContattoTelefono IS NULL
					OR x.ContattoEmail IS NULL
					);

			INSERT INTO @mancanti (Testo)
			SELECT N'collegamento a DIWASS di ' + s.NomeCompleto
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
				LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id AND o.Stato IN ('NEW', 'VALID')
			WHERE
				x.Id = @Id
				AND x.Ruolo <> 'O'
				AND o.Id IS NULL;

			IF EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'P'
			)
				AND EXISTS (
					SELECT 1
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND
							(
							ProduttoreFirmaNome IS NULL
							OR ProduttoreFirmaRuolo IS NULL
							OR ProduttoreFirmaData IS NULL
							)
				)
				INSERT INTO @mancanti (Testo) VALUES (N'conferma del produttore (nome, ruolo e data)');

			IF EXISTS (SELECT 1
			FROM @mancanti)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = LEFT(N'Per inviare l''Allegato VII a DIWASS completare: '
					+ STUFF((SELECT N'; ' + Testo
					FROM @mancanti ORDER BY Pos FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), 2000);
				GOTO BRANCH_END;
			END
		END

		DECLARE @json NVARCHAR(MAX) = (
			SELECT
				idCredenziale = @idCredenziale,
				numero = a.Numero,
				arrangerIsProducer = CAST(IIF(EXISTS (SELECT 1
				FROM dbo.tblDiwassAllegatiViiSoggetti p
				WHERE
					p.Id = a.Id
					AND p.Ruolo = 'P'
				), 0, 1) AS BIT),
				tipoDestinazione = a.TipoDestinazione,
				dataSpedizione = a.DataSpedizione,
				quantita = a.Quantita,
				unitaQuantita = a.UnitaQuantita,
				contenitore = a.Contenitore,
				luogoPartenza = a.LuogoPartenza,
				responsabileNome = a.ResponsabileNome,
				responsabileTelefono = a.ResponsabileTelefono,
				responsabileEmail = a.ResponsabileEmail,
				-- Elenco europeo dei rifiuti nel formato DIWASS ("15 01 01", con l'asterisco se pericoloso)
				eer = LEFT(a.IdEer, 2) + ' ' + SUBSTRING(a.IdEer, 3, 2) + ' ' + RIGHT(a.IdEer, 2) + IIF(e.Pericoloso = 1, '*', ''),
				listaCodice = a.ListaCodice,
				codice = a.Codice,
				descrizione = a.Descrizione,
				operazione = r.Codice,
				codiceDoganale = a.CodiceDoganale,
				paeseSpedizione = a.IdNazioneSpedizione,
				paeseDestinazione = a.IdNazioneDestinazione,
				paeseTransito1 = a.IdNazioneTransito1,
				paeseTransito2 = a.IdNazioneTransito2,
				firmaNome = @firmaNome,
				firmaRuolo = a.FirmaRuolo,
				firmaEmail = @firmaEmail,
				produttoreFirmaNome = a.ProduttoreFirmaNome,
				produttoreFirmaRuolo = a.ProduttoreFirmaRuolo,
				produttoreFirmaData = a.ProduttoreFirmaData,
				motivo = @Motivo,
				soggetti = (
					SELECT
						ruolo = x.Ruolo,
						pos = x.Pos,
						operatorInternalId = o.OperatorInternalId,
						partyUuid = x.PartyUuid,
						contattoNome = x.ContattoNome,
						contattoTelefono = x.ContattoTelefono,
						contattoEmail = x.ContattoEmail,
						mezzoTrasporto = x.MezzoTrasporto,
						impiantoIntermedio = ISNULL(x.ImpiantoIntermedio, 0),
						nomeRiservato = ISNULL(x.NomeRiservato, 0),
						motivoRiservatezza = x.MotivoRiservatezza
					FROM
						dbo.tblDiwassAllegatiViiSoggetti x
						LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
					WHERE x.Id = a.Id
					ORDER BY x.Ruolo, x.Pos
					FOR JSON PATH
				)
			FROM
				dbo.tblDiwassAllegatiVii a
				LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON a.IdAttivita = r.Id
			WHERE a.Id = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

		SELECT rtn = @json;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_get_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Allegati VII: documenti dell'azienda del contesto (chi organizza la spedizione), dal più recente
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda del contesto (senza azienda nessuna riga). @Stato: B = bozze, altrimenti lo stato DIWASS
		SELECT
			a.Id,
			StatoValore = CASE
				WHEN a.Stato IS NULL OR a.DaInviare = 1 THEN 1
				WHEN a.Stato IN ('CANCELLED', 'TAKE_BACK') THEN 2
				ELSE 0
			END,
			StatoDescrizione = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato)
				+ IIF(a.DaInviare = 1, ' - modifiche da inviare a DIWASS', ''),
			a.Numero,
			a.Stato,
			StatoNome = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato),
			a.DataSpedizione,
			EerNome = e.Nome,
			a.Descrizione,
			DestinatarioNome = d.NomeCompleto,
			PaeseDestinazione = n.Nome,
			a.Quantita,
			a.UnitaQuantita,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni s ON a.IdAziendaInterna = s.IdAzienda
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti x ON a.Id = x.Id AND x.Ruolo = 'D' AND x.Pos = 1
			LEFT JOIN dbo.tblSedi d ON x.IdSede = d.Id
			LEFT JOIN dbo.tblNazioni n ON a.IdNazioneDestinazione = n.Id
		WHERE
			s.Id = @IdSessione
			AND a.Lock = 0
			AND
				(
				@Stato IS NULL
				OR
					(
					@Stato = 'B'
					AND a.Stato IS NULL
					)
				OR a.Stato = @Stato
				)
			AND
				(
				@Search IS NULL
				OR a.Numero LIKE '%' + @Search + '%'
				OR a.Descrizione LIKE '%' + @Search + '%'
				OR e.Nome LIKE '%' + @Search + '%'
				OR d.NomeCompleto LIKE '%' + @Search + '%'
				)
		ORDER BY a.DataSpedizione DESC, a.Id DESC
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_get_Soggetti
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Soggetti dell'Allegato VII con il loro operatore DIWASS (Ruolo O chi organizza, P produttore, D destinatario,
-- I impianto, T trasportatore)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Soggetti]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassAllegatiVii a
				INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			x.Ruolo,
			x.Pos,
			x.IdSede,
			SedeNome = s.NomeCompleto,
			o.OperatorInternalId,
			OperatoreNome = o.Nome,
			x.ContattoNome,
			x.ContattoTelefono,
			x.ContattoEmail,
			x.MezzoTrasporto,
			x.ImpiantoIntermedio,
			x.NomeRiservato,
			x.MotivoRiservatezza
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
		WHERE x.Id = @Id
		ORDER BY x.Ruolo, x.Pos;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_get_Soggetti_SelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Soggetti proponibili in un Allegato VII: sedi del contesto o condivise (ufnDiwassOperatori_get_SediBySessione_List)
-- collegate a DIWASS con il ruolo WSR nuovo o valido. @IdSelected resta in elenco anche se nel frattempo non lo è più
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Soggetti_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), REPLICATE('0', 16));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi per Id e Pos

			SELECT
				s.Id,
				[Text] = CAST(ISNULL(p.NomeCompleto + ' - ', '') + s.NomeCompleto + ' (' + s.IndirizzoCompleto + ')' AS VARCHAR(400)),
				Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v
				INNER JOIN dbo.tblSedi s ON v.Id = s.Id
				INNER JOIN dbo.tblDiwassOperatori o ON s.Id = o.Id
				LEFT JOIN dbo.tblSedi p ON s.IdParent = p.Id
			WHERE
				o.Stato IN ('NEW', 'VALID')
				OR s.Id = @IdSelected
		)
		SELECT
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_ins
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo Allegato VII (bozza, Lock = 2 finché non si salva) dell'azienda del contesto, che è chi organizza la
-- spedizione. Con @IdRegistrazione (Trasporto transfrontaliero = Allegato VII) lo compila dalla registrazione e dal
-- suo movimento: soggetti collegati a DIWASS (la sede o, se non collegata, la sua azienda), quantità in tonnellate o
-- m³, data, EER, operazione R, codice internazionale (ultimo usato dall'azienda per l'EER o il primo suggerito),
-- paesi e luogo di partenza. Restituisce Id e gli avvisi da mostrare (sedi sostituite o non collegate)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_ins]
	@IdSessione CHAR(16) = NULL,
	@IdRegistrazione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = IdAzienda,
			@idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda che organizza la spedizione';
			GOTO BRANCH_END;
		END

		-- Dati della registrazione e del suo movimento (solo dell'azienda del contesto e con Allegato VII)
		DECLARE @idMovimento CHAR(16);
		DECLARE @idProduttore CHAR(16);
		DECLARE @idDestinatario CHAR(16);
		DECLARE @quantita DECIMAL(18, 5);
		DECLARE @unitaQuantita CHAR(1);
		DECLARE @dataSpedizione DATE;
		DECLARE @idEer CHAR(6);
		DECLARE @descrizione VARCHAR(500);
		DECLARE @idAttivita CHAR(2);

		IF @IdRegistrazione IS NOT NULL
		BEGIN
			DECLARE @tipoTransfrontaliero CHAR(1);
			SELECT
				@idMovimento = m.Id,
				@tipoTransfrontaliero = r.IdTrasportoTransfrontalieroTipo,
				@idProduttore = m.IdSedeProduttoreDetentore,
				@idDestinatario = m.IdSedeDestinatario,
				@quantita = CASE m.IdUnitaMisura
					WHEN 'KG' THEN m.Quantita / 1000
					WHEN 'TN' THEN m.Quantita
					WHEN 'LT' THEN m.Quantita / 1000
					WHEN 'MC' THEN m.Quantita
				END,
				@unitaQuantita = CASE m.IdUnitaMisura
					WHEN 'LT' THEN 'M'
					WHEN 'MC' THEN 'M'
					ELSE 'T'
				END,
				@dataSpedizione = ISNULL(CAST(m.DataInizioTrasporto AS DATE), r.Data),
				@idEer = m.IdEer,
				@descrizione = ISNULL(m.EerDescrizione, e.Descrizione),
				@idAttivita = IIF(a.Codice LIKE 'R%', m.IdAttivita, NULL)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			WHERE
				r.Id = @IdRegistrazione
				AND r.Lock < 2
				AND s.IdAziendaInterna = @idAzienda;

			IF @idMovimento IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione non trovata nell''azienda del contesto';
				GOTO BRANCH_END;
			END
			IF ISNULL(@tipoTransfrontaliero, '') <> 'D'
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione non ha il trasporto transfrontaliero con Allegato VII';
				GOTO BRANCH_END;
			END
		END

		-- Una registrazione ha un solo Allegato VII non annullato: se c'è già, si apre quello
		DECLARE @esistente CHAR(16) = (
			SELECT TOP 1 Id
			FROM dbo.tblDiwassAllegatiVii
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND Lock = 0
				AND ISNULL(Stato, '') <> 'CANCELLED'
		);
		IF @esistente IS NOT NULL
		BEGIN
			SELECT
				Id = @esistente,
				Avvisi = N'La registrazione ha già un Allegato VII: è stato aperto quello';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @avvisi NVARCHAR(MAX) = N'';

		-- Soggetti da indicare: sede collegata a DIWASS o, se non collegata, la sua azienda
		DECLARE @soggetti TABLE (Ruolo CHAR(1), Pos TINYINT, IdSedeOrigine CHAR(16), Mezzo CHAR(1));
		IF @idMovimento IS NOT NULL
		BEGIN
			INSERT INTO @soggetti (Ruolo, Pos, IdSedeOrigine, Mezzo)
			VALUES ('P', 1, @idProduttore, NULL), ('D', 1, @idDestinatario, NULL), ('I', 1, @idDestinatario, NULL);

			INSERT INTO @soggetti (Ruolo, Pos, IdSedeOrigine, Mezzo)
			SELECT
				'T',
				t.Pos + 1,
				z.IdSede,
				CASE t.IdTipo
					WHEN 'T' THEN 'T'
					WHEN 'N' THEN 'S'
					ELSE 'R'
				END
			FROM
				dbo.tblRifiutiMovimentiTrasportatori t
				INNER JOIN dbo.tblRifiutiAutorizzazioni z ON t.IdAutorizzazione = z.Id
			WHERE
				t.Id = @idMovimento
				AND t.Pos BETWEEN 0 AND 2;
		END

		DECLARE @collegati TABLE (Ruolo CHAR(1), Pos TINYINT, IdSede CHAR(16), Sostituita BIT, IdSedeOrigine CHAR(16), Mezzo CHAR(1));
		INSERT INTO @collegati (Ruolo, Pos, IdSede, Sostituita, IdSedeOrigine, Mezzo)
		SELECT x.Ruolo, x.Pos, c.IdSede, c.Sostituita, x.IdSedeOrigine, x.Mezzo
		FROM
			@soggetti x
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_SedeCollegata(x.IdSedeOrigine) c
		WHERE x.IdSedeOrigine IS NOT NULL;

		-- Il produttore che coincide con chi organizza non si indica (arrangerIsProducer)
		DELETE @collegati
		WHERE
			Ruolo = 'P'
			AND IdSede = @idAzienda;

		SELECT @avvisi = @avvisi + CASE x.Ruolo
				WHEN 'P' THEN N'Produttore'
				WHEN 'D' THEN N'Destinatario'
				WHEN 'I' THEN N'Impianto'
				ELSE N'Trasportatore ' + CAST(x.Pos AS NVARCHAR(1))
			END + N': ' + s.NomeCompleto + IIF(x.IdSede IS NULL,
				N' non è collegato a DIWASS (Diwass > Operatori), indicarlo prima dell''invio. ',
				N' non è collegato a DIWASS, è indicata la sua azienda. ')
		FROM
			@collegati x
			INNER JOIN dbo.tblSedi s ON x.IdSedeOrigine = s.Id
		WHERE
			x.IdSede IS NULL
			OR x.Sostituita = 1;

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDiwassOperatori
		WHERE
			Id = @idAzienda
			AND Stato IN ('NEW', 'VALID')
		)
			SET @avvisi = @avvisi + N'L''azienda che organizza la spedizione non è collegata a DIWASS (Diwass > Operatori). ';

		-- Codice internazionale: ultimo usato dall'azienda per l'EER, altrimenti il primo suggerito
		DECLARE @listaCodice VARCHAR(10);
		DECLARE @codice NVARCHAR(20);
		SELECT
			@listaCodice = Lista,
			@codice = Codice
		FROM dbo.tblDiwassCodiciRifiutiUsati
		WHERE
			IdAziendaInterna = @idAzienda
			AND IdEer = @idEer;
		IF @codice IS NULL
			SELECT TOP 1
				@listaCodice = Lista,
				@codice = Codice
			FROM dbo.tblDiwassCodiciRifiutiEer
			WHERE IdEer = @idEer
			ORDER BY Pos;

		-- Paesi e luogo di partenza dalle sedi del produttore (o dell'azienda) e del destinatario
		DECLARE @idSedePartenza CHAR(16) = ISNULL(@idProduttore, @idAzienda);
		DECLARE @luogoPartenza VARCHAR(300) = (SELECT LEFT(IndirizzoCompleto, 300)
		FROM dbo.tblSedi
		WHERE Id = @idSedePartenza);
		DECLARE @idNazioneSpedizione CHAR(3) = (
			SELECT TOP 1 i.IdNazione
			FROM
				dbo.tblSediIndirizzi si
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			WHERE si.Id = @idSedePartenza);
		DECLARE @idNazioneDestinazione CHAR(3) = (
			SELECT TOP 1 i.IdNazione
			FROM
				dbo.tblSediIndirizzi si
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			WHERE si.Id = @idDestinatario);
		DECLARE @interim BIT = IIF(EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento
			WHERE
				Id = @idAttivita
				AND Codice IN ('R12', 'R13')
		), 1, 0);

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblDiwassAllegatiVii (
				Id, IdAziendaInterna, IdRegistrazione, TipoDestinazione, DataSpedizione, Quantita, UnitaQuantita,
				LuogoPartenza, IdEer, Descrizione, IdNazioneSpedizione, IdNazioneDestinazione, IdAttivita,
				ListaCodice, Codice, FirmaRuolo, Lock)
			SELECT
				@returnId, @idAzienda, @IdRegistrazione, 'R', @dataSpedizione, @quantita, ISNULL(@unitaQuantita, 'T'),
				@luogoPartenza, @idEer, LEFT(@descrizione, 500), @idNazioneSpedizione, @idNazioneDestinazione, @idAttivita,
				@listaCodice, @codice, f.Ruolo, 2
			FROM (SELECT x = 1) d
			LEFT JOIN dbo.tblDiwassFirmeRuoli f ON f.IdUtente = @idUtente AND f.IdAziendaInterna = @idAzienda;

			-- Chi organizza: l'azienda, con il contatto dell'utente che compila
			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail)
			SELECT
				@returnId,
				'O',
				1,
				@idAzienda,
			LEFT(LTRIM(RTRIM(ISNULL(u.Nome, '') + ' ' + ISNULL(u.Cognome, ''))), 100),
				c.Telefono,
				u.Email
			FROM
				dbo.tblUtenti u
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(@idAzienda) c
			WHERE u.Id = @idUtente;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato)
			SELECT
				@returnId,
				x.Ruolo,
				x.Pos,
				x.IdSede,
				c.Nome,
				c.Telefono,
				c.Email,
				x.Mezzo,
				IIF(x.Ruolo = 'I', @interim, NULL),
				IIF(x.Ruolo = 'I', 0, NULL)
			FROM
				@collegati x
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(x.IdSede) c
			WHERE x.IdSede IS NOT NULL;
		COMMIT TRANSACTION;

		SELECT
			Id = @returnId,
			Avvisi = NULLIF(LTRIM(RTRIM(@avvisi)), N'');

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

-- ===== 3. uspDiwassAllegatiVii_upd
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva l'Allegato VII (bozza o già annunciato su DIWASS: in quel caso le modifiche restano da inviare, DaInviare = 1).
-- @Soggetti è l'elenco JSON dei soggetti ([{ruolo, pos, idSede, contattoNome, contattoTelefono, contattoEmail,
-- mezzoTrasporto, impiantoIntermedio, nomeRiservato, motivoRiservatezza}]): sostituisce quelli salvati. I controlli di
-- completezza sono all'invio (uspDiwassAllegatiVii_get_Invio): qui solo quelli che rendono il dato incoerente
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@TipoDestinazione CHAR(1) = NULL,
	@DataSpedizione DATE = NULL,
	@Quantita DECIMAL(18, 5) = NULL,
	@UnitaQuantita CHAR(1) = NULL,
	@Contenitore VARCHAR(100) = NULL,
	@LuogoPartenza VARCHAR(300) = NULL,
	@ResponsabileNome VARCHAR(100) = NULL,
	@ResponsabileTelefono VARCHAR(50) = NULL,
	@ResponsabileEmail VARCHAR(100) = NULL,
	@IdEer CHAR(6) = NULL,
	@Descrizione VARCHAR(500) = NULL,
	@CodiceDoganale VARCHAR(50) = NULL,
	@IdNazioneSpedizione CHAR(3) = NULL,
	@IdNazioneDestinazione CHAR(3) = NULL,
	@IdNazioneTransito1 CHAR(3) = NULL,
	@IdNazioneTransito2 CHAR(3) = NULL,
	@IdAttivita CHAR(2) = NULL,
	@Codice NVARCHAR(40) = NULL,
	@FirmaRuolo VARCHAR(100) = NULL,
	@ProduttoreFirmaNome VARCHAR(100) = NULL,
	@ProduttoreFirmaRuolo VARCHAR(100) = NULL,
	@ProduttoreFirmaData DATETIME2(0) = NULL,
	@Note VARCHAR(500) = NULL,
	@Soggetti NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(400) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @TipoDestinazione = ISNULL(NULLIF(LTRIM(RTRIM(@TipoDestinazione)), ''), 'R');
		SET @UnitaQuantita = ISNULL(NULLIF(LTRIM(RTRIM(@UnitaQuantita)), ''), 'T');
		SET @Contenitore = dbo.ufnStringhe_get_SenzaSpazi(@Contenitore, 0, 1);
		SET @LuogoPartenza = dbo.ufnStringhe_get_SenzaSpazi(@LuogoPartenza, 0, 1);
		SET @ResponsabileNome = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileNome, 0, 1);
		SET @ResponsabileTelefono = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileTelefono, 0, 1);
		SET @ResponsabileEmail = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileEmail, 0, 1);
		SET @IdEer = NULLIF(NULLIF(LTRIM(RTRIM(@IdEer)), ''), '000000');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @CodiceDoganale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceDoganale, 0, 1);
		SET @IdNazioneSpedizione = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneSpedizione)), ''), '000');
		SET @IdNazioneDestinazione = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneDestinazione)), ''), '000');
		SET @IdNazioneTransito1 = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneTransito1)), ''), '000');
		SET @IdNazioneTransito2 = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneTransito2)), ''), '000');
		SET @IdAttivita = NULLIF(NULLIF(LTRIM(RTRIM(@IdAttivita)), ''), '00');
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');
		SET @FirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@FirmaRuolo, 0, 1);
		SET @ProduttoreFirmaNome = dbo.ufnStringhe_get_SenzaSpazi(@ProduttoreFirmaNome, 0, 1);
		SET @ProduttoreFirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@ProduttoreFirmaRuolo, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF @TipoDestinazione NOT IN ('R', 'L') OR @UnitaQuantita NOT IN ('T', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Tipo di destinazione o unità della quantità non validi';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NOT NULL AND @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @stato VARCHAR(20);
		DECLARE @nazioneSpedizioneAttuale CHAR(3);
		DECLARE @nazioneDestinazioneAttuale CHAR(3);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@stato = a.Stato,
			@nazioneSpedizioneAttuale = a.IdNazioneSpedizione,
			@nazioneDestinazioneAttuale = a.IdNazioneDestinazione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock <= 2
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END
		IF @stato IS NOT NULL AND @stato <> 'ANNOUNCED'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII è ' + LOWER(dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(@stato)) + ' su DIWASS: non si può più modificare';
			GOTO BRANCH_END;
		END
		-- Su DIWASS i paesi coinvolti non si cambiano dopo l'annuncio
		IF @stato = 'ANNOUNCED'
			AND (ISNULL(@IdNazioneSpedizione, '') <> ISNULL(@nazioneSpedizioneAttuale, '')
				OR ISNULL(@IdNazioneDestinazione, '') <> ISNULL(@nazioneDestinazioneAttuale, ''))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dopo l''invio a DIWASS i paesi di spedizione e di destinazione non si possono cambiare';
			GOTO BRANCH_END;
		END

		-- Codice internazionale nel formato "lista|codice" della select
		DECLARE @listaCodice VARCHAR(10) = NULL;
		DECLARE @codiceRifiuto NVARCHAR(20) = NULL;
		IF @Codice IS NOT NULL
		BEGIN
			SET @listaCodice = LEFT(@Codice, CHARINDEX('|', @Codice + '|') - 1);
			SET @codiceRifiuto = NULLIF(SUBSTRING(@Codice, CHARINDEX('|', @Codice + '|') + 1, 20), '');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassCodiciRifiuti
			WHERE
				Lista = @listaCodice
				AND Codice = @codiceRifiuto
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Codice internazionale del rifiuto non valido';
				GOTO BRANCH_END;
			END
		END

		-- Soggetti
		DECLARE @elenco TABLE (
			Ruolo CHAR(1) NOT NULL,
			Pos TINYINT NOT NULL,
			IdSede CHAR(16) NULL,
			ContattoNome VARCHAR(100) NULL,
			ContattoTelefono VARCHAR(50) NULL,
			ContattoEmail VARCHAR(100) NULL,
			MezzoTrasporto CHAR(1) NULL,
			ImpiantoIntermedio BIT NULL,
			NomeRiservato BIT NULL,
			MotivoRiservatezza VARCHAR(500) NULL,
			PRIMARY KEY (Ruolo, Pos)
		);
		INSERT INTO @elenco (Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
		SELECT
			j.ruolo,
			j.pos,
			NULLIF(NULLIF(LTRIM(RTRIM(j.idSede)), ''), REPLICATE('0', 16)),
			NULLIF(LTRIM(RTRIM(j.contattoNome)), ''),
			NULLIF(LTRIM(RTRIM(j.contattoTelefono)), ''),
			NULLIF(LTRIM(RTRIM(j.contattoEmail)), ''),
			NULLIF(LTRIM(RTRIM(j.mezzoTrasporto)), ''),
			j.impiantoIntermedio,
			j.nomeRiservato,
			NULLIF(LTRIM(RTRIM(j.motivoRiservatezza)), '')
		FROM OPENJSON(ISNULL(@Soggetti, N'[]'))
		WITH (
			ruolo CHAR(1),
			pos TINYINT,
			idSede CHAR(16),
			contattoNome VARCHAR(100),
			contattoTelefono VARCHAR(50),
			contattoEmail VARCHAR(100),
			mezzoTrasporto CHAR(1),
			impiantoIntermedio BIT,
			nomeRiservato BIT,
			motivoRiservatezza VARCHAR(500)
		) j;

		-- Le righe senza sede (casella lasciata su "Selezionare") non si salvano
		DELETE @elenco
		WHERE IdSede IS NULL;

		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo NOT IN ('O', 'P', 'D', 'I', 'T')
			OR Pos NOT BETWEEN 1 AND 3
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ruolo o posizione dei soggetti non validi';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo = 'T'
			AND ISNULL(MezzoTrasporto, '') NOT IN ('R', 'T', 'S', 'A', 'W')
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il mezzo di trasporto di ogni trasportatore';
			GOTO BRANCH_END;
		END

		-- Chi organizza è sempre l'azienda dell'Allegato VII
		DELETE @elenco
		WHERE
			Ruolo = 'O'
			AND IdSede <> @idAzienda;
		IF NOT EXISTS (SELECT 1
		FROM @elenco
		WHERE Ruolo = 'O')
			INSERT INTO @elenco (Ruolo, Pos, IdSede)
			VALUES ('O', 1, @idAzienda);

		-- Ogni soggetto deve essere visibile nel contesto e collegato a DIWASS con il ruolo WSR nuovo o valido
		DECLARE @nonCollegato VARCHAR(200) = (
			SELECT TOP 1 s.NomeCompleto
			FROM
				@elenco x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
				LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id AND o.Stato IN ('NEW', 'VALID')
				LEFT JOIN dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v ON x.IdSede = v.Id
			WHERE
				x.Ruolo <> 'O'
				AND
					(
					o.Id IS NULL
					OR v.Id IS NULL
					)
		);
		IF @nonCollegato IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto ' + @nonCollegato + ' non è collegato a DIWASS (Diwass > Operatori)';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo = 'I'
			AND NomeRiservato = 1
			AND MotivoRiservatezza IS NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare perché il nome dell''impianto è riservato';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblDiwassAllegatiVii
			SET
				TipoDestinazione = @TipoDestinazione,
				DataSpedizione = @DataSpedizione,
				Quantita = @Quantita,
				UnitaQuantita = @UnitaQuantita,
				Contenitore = @Contenitore,
				LuogoPartenza = @LuogoPartenza,
				ResponsabileNome = @ResponsabileNome,
				ResponsabileTelefono = @ResponsabileTelefono,
				ResponsabileEmail = @ResponsabileEmail,
				IdEer = @IdEer,
				Descrizione = @Descrizione,
				CodiceDoganale = @CodiceDoganale,
				IdNazioneSpedizione = @IdNazioneSpedizione,
				IdNazioneDestinazione = @IdNazioneDestinazione,
				IdNazioneTransito1 = @IdNazioneTransito1,
				IdNazioneTransito2 = @IdNazioneTransito2,
				IdAttivita = @IdAttivita,
				ListaCodice = @listaCodice,
				Codice = @codiceRifiuto,
				FirmaRuolo = @FirmaRuolo,
				ProduttoreFirmaNome = @ProduttoreFirmaNome,
				ProduttoreFirmaRuolo = @ProduttoreFirmaRuolo,
				ProduttoreFirmaData = @ProduttoreFirmaData,
				Note = @Note,
				DaInviare = IIF(@stato = 'ANNOUNCED', 1, NULL),
				Lock = 0
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allegato VII non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Soggetti: l'identificativo del soggetto nel documento (PartyUuid) resta finché non cambia la sede
			DELETE x
			FROM dbo.tblDiwassAllegatiViiSoggetti x
			WHERE
				x.Id = @Id
				AND NOT EXISTS ( SELECT 1 FROM @elenco n WHERE n.Ruolo = x.Ruolo AND n.Pos = x.Pos AND n.IdSede = x.IdSede );

			UPDATE x
			SET
				ContattoNome = n.ContattoNome,
				ContattoTelefono = n.ContattoTelefono,
				ContattoEmail = n.ContattoEmail,
				MezzoTrasporto = n.MezzoTrasporto,
				ImpiantoIntermedio = n.ImpiantoIntermedio,
				NomeRiservato = n.NomeRiservato,
				MotivoRiservatezza = n.MotivoRiservatezza
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN @elenco n ON x.Ruolo = n.Ruolo AND x.Pos = n.Pos AND x.IdSede = n.IdSede
			WHERE x.Id = @Id;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
			SELECT @Id, n.Ruolo, n.Pos, n.IdSede, n.ContattoNome, n.ContattoTelefono, n.ContattoEmail, n.MezzoTrasporto, n.ImpiantoIntermedio, n.NomeRiservato, n.MotivoRiservatezza
			FROM @elenco n
			WHERE NOT EXISTS ( SELECT 1 FROM dbo.tblDiwassAllegatiViiSoggetti x WHERE x.Id = @Id AND x.Ruolo = n.Ruolo AND x.Pos = n.Pos );
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 3. uspDiwassAllegatiVii_upd_Invio
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Esito di un'operazione su DIWASS (@Operazione come uspDiwassAllegatiVii_get_Invio): I invio riuscito (numero DIWASS,
-- stato Annunciato, firma; ricorda codice internazionale per l'EER e ruolo di firma dell'utente), A aggiornamento
-- riuscito, N annullamento riuscito, S stato letto da DIWASS
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd_Invio]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Operazione CHAR(1) = NULL,
	@Numero VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@FirmaNome VARCHAR(100) = NULL,
	@FirmaEmail VARCHAR(100) = NULL,
	@FirmaData DATETIME2(0) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');

		IF @Id IS NULL OR @IdSessione IS NULL OR ISNULL(@Operazione, '') NOT IN ('I', 'A', 'N', 'S')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri non validi';
			GOTO BRANCH_END;
		END
		IF (@Operazione = 'I' AND @Numero IS NULL) OR (@Operazione = 'S' AND @Stato IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Risposta di DIWASS senza numero o stato del documento';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF IIF(@Operazione = 'S', 1, 2) > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblDiwassAllegatiVii
			SET
				Numero = IIF(@Operazione = 'I', @Numero, Numero),
				Stato = CASE @Operazione WHEN 'I' THEN 'ANNOUNCED' WHEN 'N' THEN 'CANCELLED' WHEN 'S' THEN @Stato ELSE Stato END,
				DataInvio = IIF(@Operazione = 'I', GETDATE(), DataInvio),
				DataStato = GETDATE(),
				DaInviare = IIF(@Operazione IN ('I', 'A'), NULL, DaInviare),
				FirmaNome = IIF(@Operazione IN ('I', 'A'), @FirmaNome, FirmaNome),
				FirmaEmail = IIF(@Operazione IN ('I', 'A'), @FirmaEmail, FirmaEmail),
				FirmaData = IIF(@Operazione IN ('I', 'A'), @FirmaData, FirmaData)
			WHERE Id = @Id;

			IF @Operazione IN ('I', 'A')
			BEGIN
				-- Proposte per i prossimi Allegati VII: codice internazionale per l'EER e ruolo di firma dell'utente
				MERGE dbo.tblDiwassCodiciRifiutiUsati AS t
				USING (
					SELECT IdAziendaInterna, IdEer, ListaCodice, Codice
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND IdEer IS NOT NULL
						AND Codice IS NOT NULL
				) AS s
				ON t.IdAziendaInterna = s.IdAziendaInterna AND t.IdEer = s.IdEer
				WHEN MATCHED THEN UPDATE
				SET
					Lista = s.ListaCodice,
					Codice = s.Codice,
					Data = GETDATE() WHEN NOT MATCHED THEN INSERT (IdAziendaInterna, IdEer, Lista, Codice, Data) VALUES (s.IdAziendaInterna, s.IdEer, s.ListaCodice, s.Codice, GETDATE());

				MERGE dbo.tblDiwassFirmeRuoli AS t
				USING (
					SELECT IdUtente = @idUtente, IdAziendaInterna, FirmaRuolo
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND FirmaRuolo IS NOT NULL
				) AS s
				ON t.IdUtente = s.IdUtente AND t.IdAziendaInterna = s.IdAziendaInterna
				WHEN MATCHED THEN UPDATE
				SET Ruolo = s.FirmaRuolo WHEN NOT MATCHED THEN INSERT (IdUtente, IdAziendaInterna, Ruolo) VALUES (s.IdUtente, s.IdAziendaInterna, s.FirmaRuolo);
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

-- ===== 4. uspSYS_del_SedeInternaCascade
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: lotti/allocazioni/magazzini specifici EoW di proprietà della sede (solo sedi
        -- interne, IdSede diretto su tutte e tre le tabelle) - vedi project_eow_module_design in
        -- memoria persistente.
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWAllocazioni FROM dbo.tblEoWAllocazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti hanno IdSede = sede
        -- operativa (può essere una sede figlia diversa dall'Azienda) - vedi project_magazzino
        -- in memoria persistente.
        SELECT Id INTO #MagArticoli FROM dbo.tblMagazziniArticoli WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagLotti FROM dbo.tblMagazziniLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagMovimenti FROM dbo.tblMagazziniMovimenti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa e Fatturazione: schede dell'azienda (o sul soggetto, se nella cascata),
        -- banche/casse e aliquote IVA proprie dell'azienda
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Schede amministratore dell'azienda (o su un soggetto della cascata)
        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture dell'azienda (o di una scheda della cascata) e conti dell'azienda
        SELECT Id INTO #Fatture FROM dbo.tblFatture
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);
        SELECT Id INTO #FattureConti FROM dbo.tblFattureConti WHERE IdSede IN (SELECT Id FROM #Sedi);        SELECT Id INTO #BancheCasse FROM dbo.tblBancheCasse WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #AliquoteIva FROM dbo.tblAliquoteIva WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Dichiarazioni MUD dell'azienda o che citano una sede della cascata
        SELECT Id INTO #RifiutiMud FROM dbo.tblRifiutiMud
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdSedeLegale IN (SELECT Id FROM #Sedi) OR IdSedeUnitaLocale IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblDiwassCredenziali.IdAziendaInterna: credenziale DIWASS dell'azienda interna, con la sua riga nell'hub
        SELECT Id, IdDiwass INTO #DiwassCredenziali FROM dbo.tblDiwassCredenziali WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che potrebbero essere
        -- cancellati (quelli dell'azienda o delle sue banche e casse, e quelli che coprono rate di
        -- queste fatture), raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche
        -- rate di altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti
        -- che alla fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #PagamentiCandidati FROM (
            SELECT Id FROM dbo.tblPagamenti
            WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi)
            UNION
            SELECT rp.IdPagamento FROM dbo.tblFattureRatePagamenti rp
            WHERE rp.IdRata IN (SELECT Id FROM #FattureRate)
        ) x;

        -- Offerte e contratti: importi (con le righe) e offerte o contratti dell'azienda, o di una
        -- scheda cliente della cascata
        SELECT Id INTO #Importi FROM dbo.tblImporti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #ImportiRighe FROM dbo.tblImportiRighe WHERE IdImporto IN (SELECT Id FROM #Importi);
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, conti, aliquote,
            -- etichette, tipi e sedi cancellati più sotto. I documenti fatturabili (registrazioni,
            -- movimenti di magazzino, servizi) hanno lo stesso Id del documento
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #MagMovimenti)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdImporto IN (SELECT Id FROM #Importi)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti
            WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti) OR IdImporto IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblImportiRigheDettagli WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRighe WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRifiuti WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiMagazzino WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiServizi WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImporti WHERE Id IN (SELECT Id FROM #Importi);
            -- Importi di ALTRE aziende che citano una sede, un'etichetta, un tipo, un conto o
            -- un'aliquota della cascata (non previsto dalle regole): perdono solo il collegamento
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdSedePartenza = NULL WHERE IdSedePartenza IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdSedeInterna = NULL WHERE IdSedeInterna IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino di ALTRE aziende su un articolo della cascata (non previsto): perdono l'articolo
            DELETE FROM dbo.tblImportiRigheMagazzino WHERE IdArticolo IN (SELECT Id FROM #MagArticoli);
            -- Righe di listino di ALTRE aziende su una persona o un oggetto della cascata (condivisi): perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);
            UPDATE dbo.tblImportiRigheDettagli SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            UPDATE dbo.tblImportiRigheDettagli SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE CASCADE).
            -- Va fatta prima della Gestione EoW: le righe EoW di scarico referenziano tblEoWLotti.
            -- Relazioni carico/scarico in entrambi i versi (righe della sede, dei suoi movimenti o
            -- dei suoi lotti): FK NO_ACTION su Id e IdParent verso tblMagazziniMovimentiRighe.
            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
            INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
            WHERE r.IdSede IN (SELECT Id FROM #Sedi) OR r.IdMovimento IN (SELECT Id FROM #MagMovimenti) OR r.IdLotto IN (SELECT Id FROM #MagLotti);

            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
            INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
            WHERE
                re.IdSede IN (SELECT Id FROM #Sedi)
                OR re.IdMovimento IN (SELECT Id FROM #MagMovimenti)
                OR re.IdLotto IN (SELECT Id FROM #EoWLotti)
                OR rel.IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdSede IN (SELECT Id FROM #Sedi)
                OR IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi)
                OR IdMovimento IN (SELECT Id FROM #MagMovimenti);

            DELETE FROM dbo.tblMagazziniMovimentiRighe
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniMovimentiRigheEoW
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniMovimenti WHERE Id IN (SELECT Id FROM #MagMovimenti);
            DELETE FROM dbo.tblMagazziniLotti WHERE Id IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniArticoli WHERE Id IN (SELECT Id FROM #MagArticoli);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni sottostanti, per rispettare
            -- la FK di tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK
            -- composta con IdLotto - non azzerabile, la riga di collegamento va sempre rimossa,
            -- anche quando referenzia una Registrazione di questa sede legata a un Lotto di un'altra:
            -- stesso motivo dell'OR su #RifiutiRegistrazioni). I lotti/allocazioni EoW di questa sede
            -- vengono invece cancellati per intero (non azzerati) perché sono risorse di proprietà
            -- esclusiva della sede stessa, non condivise con altre sedi.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni
            WHERE IdLotto        IN (SELECT Id FROM #EoWLotti)
               OR IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWLottiAllocazioni
            WHERE IdLotto      IN (SELECT Id FROM #EoWLotti)
               OR IdAllocazione IN (SELECT Id FROM #EoWAllocazioni);
            DELETE FROM dbo.tblEoWLotti       WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWAllocazioni WHERE Id IN (SELECT Id FROM #EoWAllocazioni);

            -- tblEoWLotti.IdMagazzino (nullable, nessun vincolo strutturale che lo leghi allo stesso
            -- IdSede del Lotto) può referenziare un Magazzino di questa sede anche da un Lotto esterno
            -- alla cascata - i Lotti di questa sede sono già stati cancellati sopra, quindi qui restano
            -- solo eventuali riferimenti esterni: azzerati, non cancellati (stessa logica "UPDATE=NULL
            -- dove possibile" delle risorse condivise più sotto).
            DECLARE @eoWLottiScollegati INT;
            UPDATE dbo.tblEoWLotti SET IdMagazzino = NULL WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
            SET @eoWLottiScollegati = @@ROWCOUNT;
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- Allegati VII DIWASS delle aziende cancellate (con i soggetti), soggetti delle sedi cancellate negli altri
            -- Allegati VII, codici e ruoli di firma ricordati per le aziende
            SELECT Id INTO #DiwassAllegatiVii FROM dbo.tblDiwassAllegatiVii WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiVii WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii);
            DELETE FROM dbo.tblDiwassCodiciRifiutiUsati WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassFirmeRuoli WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            -- Dichiarazioni MUD: registri della dichiarazione (FK su tblRifiutiMud e su
            -- tblRifiutiRegistri), poi la dichiarazione
            DELETE FROM dbo.tblRifiutiMudRegistri
            WHERE Id IN (SELECT Id FROM #RifiutiMud) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiMud WHERE Id IN (SELECT Id FROM #RifiutiMud);

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Anagrafica estesa e Fatturazione: prima le schede, che referenziano banche/casse e
            -- aliquote; le schede di ALTRE aziende che usano un'aliquota o una banca di questa
            -- (non previsto dalle regole) perdono solo il collegamento
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);
            UPDATE dbo.tblClientiFornitori SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            UPDATE dbo.tblClientiFornitori SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            -- Conti: le righe di ALTRE aziende che li usano (non previsto dalle regole) perdono solo il
            -- collegamento, come per banche/casse e aliquote
            UPDATE dbo.tblFattureRigheImporti SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureConti WHERE Id IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureDatiFiscali WHERE Id IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblFattureRigheImporti SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            UPDATE dbo.tblFatture SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblFattureRatePagamenti
            WHERE IdPagamento IN (SELECT Id FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi));
            DELETE FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi);            DELETE FROM dbo.tblBancheCasse WHERE Id IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblAliquoteIva WHERE Id IN (SELECT Id FROM #AliquoteIva);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediReport WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            -- tblDiwassCredenziali prima di tblSediInterne (FK su IdAziendaInterna), con la riga dell'hub 1_0_diwass
            DELETE FROM [1_0_diwass]..tblCredenziali WHERE Id IN (SELECT IdDiwass FROM #DiwassCredenziali);
            DELETE FROM dbo.tblDiwassCredenziali WHERE Id IN (SELECT Id FROM #DiwassCredenziali);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #MagArticoli
                UNION SELECT Id FROM #MagLotti
                UNION SELECT Id FROM #MagMovimenti
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #FattureConti
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #Importi
                UNION SELECT Id FROM #ImportiRighe
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #BancheCasse
                UNION SELECT Id FROM #AliquoteIva
                UNION SELECT Id FROM #RifiutiMud
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWAllocazioni
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #DiwassCredenziali
                UNION SELECT Id FROM #DiwassAllegatiVii
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Allocazioni EoW rimosse: ', (SELECT COUNT(*) FROM #EoWAllocazioni), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ' (Lotti esterni scollegati: ', @eoWLottiScollegati, ')', ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;

-- ===== 4. uspSYS_del_SedeEsternaCascade
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeEsternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'E')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede esterna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + eventuali sotto-sedi collegate tramite tblSedi.IdParent (es. altre
        -- sedi/filiali dello stesso cliente/fornitore esterno), a qualunque profondità. A
        -- differenza di una sede interna, da una sede esterna NON si scende mai tramite
        -- IdAziendaInterna (punta sempre in alto verso la sede interna che la gestisce, mai verso
        -- un'altra sede da cancellare) né tramite tblSediEsterne.IdSedeInterna (stesso concetto).
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT s.Id
            FROM dbo.tblSedi s
            INNER JOIN #Sedi c ON s.IdParent = c.Id
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = s.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). Stessa struttura
        -- generica di uspSYS_del_SedeInternaCascade: tutte queste tabelle referenziano tblSedi.Id
        -- indipendentemente dal tipo (interna/esterna), anche se in pratica per una sede esterna
        -- oggi solo Autorizzazioni e Movimenti risultano popolati (verificato). Gestione EoW esclusa:
        -- i Magazzini EoW sono di sede interna (confermato dall'utente), una sede esterna non ne ha
        -- di propri - può però avere un proprio Registro/Registrazioni referenziati da movimenti EoW
        -- di un magazzino interno, gestiti più sotto.
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa: schede cliente/fornitore sul soggetto
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori WHERE IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture delle schede cliente/fornitore del soggetto
        SELECT Id INTO #Fatture FROM dbo.tblFatture WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti* non è mai popolato per una sede esterna (i Limiti si possono creare
        -- solo su sedi interne, confermato dall'utente): a differenza di uspSYS_del_SedeInternaCascade,
        -- qui non serve raccoglierlo/cancellarlo.

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe sono giunzioni a chiave composita verso risorse condivise
        -- a livello di Dominio (tblAree), non di proprietà della sede: si cancellano solo le righe
        -- di giunzione, mai tblAree stessa.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che coprono le loro
        -- rate, raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche rate di
        -- altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti che alla
        -- fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT DISTINCT rp.IdPagamento AS Id INTO #PagamentiCandidati
        FROM dbo.tblFattureRatePagamenti rp
        WHERE rp.IdRata IN (SELECT Id FROM #FattureRate);

        -- Offerte e contratti: offerte e contratti delle schede cliente del soggetto
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, etichette, tipi e
            -- sedi cancellati più sotto. I documenti fatturabili (registrazioni, servizi) hanno lo
            -- stesso Id del documento. Gli importi dei contratti cancellati restano all'azienda
            -- interna, senza contratto
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            -- Importi che citano una sede, un'etichetta o un tipo della cascata: perdono solo la variabile
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino su una persona o un oggetto della cascata: perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: questa sede esterna non ha lotti/allocazioni EoW propri (che referenziano
            -- solo Sede Interna), ma le sue Registrazioni possono essere referenziate da
            -- tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK composta con
            -- IdLotto) - non azzerabile come il vecchio tblEoWMovimenti.IdRegistrazione (nullable),
            -- va rimossa la riga di collegamento; il Lotto di una sede interna resta intatto.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiViiSoggetti.IdSede: le sedi cancellate escono dagli Allegati VII DIWASS
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            -- In pratica un Registro RENTRI appartiene sempre a una sede interna, ma la SP resta
            -- generica per coerenza con la raccolta #RifiutiRegistri già fatta sopra.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata (stessa logica
            -- ibrida di uspSYS_del_SedeInternaCascade: UPDATE=NULL dove la colonna è nullable,
            -- DELETE della riga di giunzione dove è NOT NULL).
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
            -- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
            -- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne). Il DDT viene rimosso,
            -- il movimento di magazzino della sede interna resta.
            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi);

            -- Anagrafica estesa: schede cliente/fornitore sul soggetto
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);

            -- Anagrafica estesa: schede amministratore del soggetto con i loro amministrati, e il
            -- soggetto tolto dagli amministrati delle altre schede
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree non toccata)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare). In pratica associata solo a sedi interne, ma la SP resta generica
            -- per lo stesso motivo della raccolta #RifiutiRegistri sopra.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: il vincolo
            -- auto-referenziato IdParent è verificato a fine istruzione (non riga per riga), quindi
            -- non si blocca da solo anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;

-- ===== 4. uspSYS_del_RegistroCascade
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_RegistroCascade
    @IdRegistro CHAR(16)    = NULL,
    @Conferma   VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
        SET @Conferma   = NULLIF(LTRIM(RTRIM(@Conferma)),   '');

        IF @IdRegistro IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistri WHERE Id = @IdRegistro)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il registro indicato non esiste';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). A differenza di
        -- una sede, un registro non possiede etichette/autorizzazioni proprie (sono risorse della
        -- sede, non del registro): non vengono quindi mai toccate da questa SP, solo scollegate
        -- dalle proprie righe di giunzione (che appartengono ai record cancellati, non alla
        -- risorsa condivisa).
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro = @IdRegistro;
        SELECT Id INTO #RifiutiMovimenti FROM dbo.tblRifiutiMovimenti WHERE IdRegistro = @IdRegistro;
        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette           WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi  WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: il registro non ha più alcun legame con lotti/allocazioni EoW (che
            -- referenziano solo Sede+Materiale), ma le sue Registrazioni in cancellazione possono
            -- essere referenziate da tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL,
            -- parte della PK composta con IdLotto) - non azzerabile, va rimossa la riga di collegamento.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiRegistrazioniRelazioni.IdParent è NOT NULL: una registrazione di un ALTRO
            -- registro (non in cancellazione) può avere come genitore una registrazione di questo
            -- registro. Non essendo azzerabile, la riga di relazione va cancellata anche quando
            -- appartiene a quell'altra registrazione - perde il collegamento e la relativa
            -- Quantita/Pos. Stessa logica "UPDATE=NULL dove possibile, DELETE dove NOT NULL"
            -- applicata alle risorse condivise di uspSYS_del_SedeInternaCascade.
            DECLARE @relazioniEsterneRimosse INT = (
                SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioniRelazioni
                WHERE IdParent IN (SELECT Id FROM #RifiutiRegistrazioni)
                  AND Id NOT IN (SELECT Id FROM #RifiutiRegistrazioni)
            );
            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRifiutiLimiti.IdRegistro è nullable e il Limite appartiene alla Sede (non al
            -- Registro, non toccato da questa SP): cancellando solo il Registro il Limite resta
            -- valido, perde solo lo scoping specifico al registro (torna a valere sull'intera sede).
            DECLARE @limitiScollegati INT;
            UPDATE dbo.tblRifiutiLimiti SET IdRegistro = NULL WHERE IdRegistro = @IdRegistro;
            SET @limitiScollegati = @@ROWCOUNT;

            -- tblRentriRegistri è 1:1 a chiave condivisa (Id NOT NULL, nessun ON DELETE CASCADE):
            -- va rimosso prima, altrimenti la DELETE sottostante fallisce per violazione FK.
            DELETE FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro;

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id = @IdRegistro;

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT @IdRegistro
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #RifiutiMovimenti),
            ', Modelli rimossi: ', (SELECT COUNT(*) FROM #RifiutiModelli),
            ', Formulari rimossi: ', (SELECT COUNT(*) FROM #RifiutiFormulari),
            ', Registrazioni rimosse: ', (SELECT COUNT(*) FROM #RifiutiRegistrazioni),
            '. Relazioni di altre registrazioni scollegate: ', @relazioniEsterneRimosse,
            '. Limiti rifiuti scollegati dal registro: ', @limitiScollegati, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;

-- ===== 4. uspSYS_del_RifiutiMovimentiCascade
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_RifiutiMovimentiCascade
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Conferma = dbo.ufnStringhe_get_SenzaSpazi(@Conferma, 0, 1);

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        SELECT Id INTO #tm FROM dbo.tblRifiutiMovimenti;
        SELECT Id INTO #tr FROM dbo.tblRifiutiRegistrazioni;
        SELECT Id INTO #tf FROM dbo.tblRifiutiFormulari;

        BEGIN TRANSACTION;
            DELETE dbo.tblRifiutiRegistrazioniRelazioni  WHERE Id       IN (SELECT Id FROM #tr) OR IdParent IN (SELECT Id FROM #tr);
            DELETE dbo.tblRifiutiMovimentiClassiPericolo WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiTrasportatori  WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiDestinatari    WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiIntermediari   WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiMovimentiProduttori     WHERE Id       IN (SELECT Id FROM #tm);
            DELETE dbo.tblRifiutiFormulariEtichette      WHERE Id       IN (SELECT Id FROM #tf);
            -- Mancanti nell'originale uspRifiutiMovimenti_del_All: sono dettagli 1:1 a chiave
            -- condivisa (Id NOT NULL) di tblRifiutiFormulari, quindi bloccano la DELETE successiva
            -- su tblRifiutiFormulari con un errore FK se anche una sola riga esiste.
            DELETE dbo.tblRifiutiFormulariTrasportiFerroviari WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiFormulariTrasportiMarittimi  WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiFormulariTrasportiTerresti   WHERE Id  IN (SELECT Id FROM #tf);
            DELETE dbo.tblRifiutiRegistrazioniEtichette  WHERE Id       IN (SELECT Id FROM #tr);
            -- Gestione EoW: tblEoWLottiRifiutiRegistrazioni.IdRegistrazione referenzia le
            -- Registrazioni che stanno per essere cancellate ed è NOT NULL (parte della PK
            -- composta con IdLotto) - non azzerabile come il vecchio tblEoWMovimenti.IdRegistrazione
            -- (nullable), va rimossa la riga di collegamento; i Lotti/Allocazioni restano intatti.
            DELETE dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #tr);
            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va svuotata prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se esiste anche una sola rettifica.
            DELETE dbo.tblRentriRegistrazioniRettifiche;
            DELETE dbo.tblRifiutiFormulari;
            -- tblDiwassAllegatiVii.IdRegistrazione: gli Allegati VII restano, perdono la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IS NOT NULL;
            DELETE dbo.tblRifiutiRegistrazioni;
            DELETE dbo.tblRifiutiMovimentiLog;
            DELETE dbo.tblRifiutiMovimenti;
            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #tr) OR Id IN (SELECT Id FROM #tm) OR Id IN (SELECT Id FROM #tf);
        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #tm),
            ', Registrazioni rimosse: ', (SELECT COUNT(*) FROM #tr),
            ', Formulari rimossi: ', (SELECT COUNT(*) FROM #tf), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;

