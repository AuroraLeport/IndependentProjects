/******************* 
CREATOR: AURORA LEPORT
DATE: 9/17/2021
PURPOSE: Classifying NDC codes using Enhanced Therapeutic Classification (ETC) 
see: https://docs.fdbhealth.com/display/CCDOCUS/Classifications+General+Reference

NOTE:
FDB.dbo.RETCTBL0_ETC_ID is based on a hierarchy (ETC_HIERARCHY_LEVEL) with parents at ETC_PARENT_ETC_ID = 0
and leaves at ETC_ULTIMATE_CHILD_IND = 1.

NOTE:
There can be multiple etc_ids per NDC code if you do not include 
WHERE ETC_COMMON_USE_IND = 1 AND ETC_DEFAULT_USE_IND = 1
e.g.
SELECT * FROM FDB.dbo.RETCNDC0_ETC_NDC WHERE NDC IN ('00590001571', '00590002518')

NDC				ETC_ID	ETC_COMMON_USE_IND	ETC_DEFAULT_USE_IND
00590001571		221		1					1
00590001571		2530	0					0
00590002518		221		1					1
00590002518		2530	0					0

FDB.dbo.RETCNDC0_ETC_NDC holds all the NDC codes for ETC_ULTIMATE_CHILD_IND = 1
******/

--- how many ndc codes are there in finalrx that are not in etc library?
--- 90.7% of the codes exist
SELECT COUNT(DISTINCT NDCCode) FROM BatchImportABCBS.dbo.FinalRX; ---70,234
SELECT COUNT(DISTINCT NDC) FROM FDB.dbo.RETCNDC0_ETC_NDC; ---450,288

--- NDC in Final Rx not in ETC crosswalk
DROP TABLE IF EXISTS #TEMP
;
SELECT DISTINCT NDCCode, AHFSCode
INTO #TEMP
FROM BatchImportABCBS.dbo.FinalRX A
	LEFT JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON A.NDCCode = B.NDC
WHERE B.NDC IS NULL
; ---6,493


SELECT
	  NDC
	, A.ETC_ID
	, Map_NDCCode.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_FORMULARY_LEVEL_IND
    , A.ETC_PRESENTATION_SEQNO
FROM 
	FDB.dbo.RETCTBL0_ETC_ID AS A
	LEFT JOIN
	FDB.dbo.RETCNDC0_ETC_NDC AS Map_NDCCode
		ON
		A.ETC_ID = Map_NDCCode.ETC_ID
WHERE
	ETC_COMMON_USE_IND = 1 AND ETC_DEFAULT_USE_IND = 1 AND ETC_ULTIMATE_CHILD_IND = 1
ORDER BY	
	A.ETC_ID
 
--=============================================================================
-- root classifications
-- pick the root class that seems realted to the disease of interest
--=============================================================================

SELECT 
	  ETC_ID
    , ETC_NAME
    , ETC_ULTIMATE_CHILD_IND
    , ETC_DRUG_CONCEPT_LINK_IND
    , ETC_PARENT_ETC_ID
    , ETC_FORMULARY_LEVEL_IND
    , ETC_PRESENTATION_SEQNO
    , ETC_ULTIMATE_PARENT_ETC_ID
    , ETC_HIERARCHY_LEVEL
    , ETC_SORT_NUMBER
    , ETC_RETIRED_IND
    , ETC_RETIRED_DATE
FROM 
	FDB.dbo.RETCTBL0_ETC_ID
WHERE 
	ETC_PARENT_ETC_ID = 0
ORDER BY 
	ETC_PRESENTATION_SEQNO
;

-- ETC_ID	ETC_NAME
-- 2553		Cardiovascular Therapy Agents
-- 120		Endocrine

-- 2584 Central Nervous System Agents

SELECT 
	  ETC_ID
    , ETC_NAME
    , ETC_ULTIMATE_CHILD_IND
    , ETC_DRUG_CONCEPT_LINK_IND
    , ETC_PARENT_ETC_ID
    , ETC_FORMULARY_LEVEL_IND
    , ETC_PRESENTATION_SEQNO
    , ETC_ULTIMATE_PARENT_ETC_ID
    , ETC_HIERARCHY_LEVEL
    , ETC_SORT_NUMBER
    , ETC_RETIRED_IND
    , ETC_RETIRED_DATE
FROM 
	FDB.dbo.RETCTBL0_ETC_ID
WHERE 
	ETC_PARENT_ETC_ID = 154
--CASE	ETC_PARENT_ETC_ID IN (6721, 604, 541
ORDER BY 
	ETC_PRESENTATION_SEQNO
;

6721	Neuropathic Pain Therapy
604	Migraine Therapy
541	Sedative-Hypnotics
/****** 
grab all etc ids associated with root (ETC_PARENT_ETC_ID) of interest using recursion
in this example we go one up from Endocrine (120) ---> Diabetic Therapy (148)
******/

DROP TABLE IF EXISTS #CTE_Recursion_DiabeticTherapy
;
WITH CTE_Recursion AS (

	SELECT A.ETC_ID
	      ,A.ETC_NAME
	      ,A.ETC_ULTIMATE_CHILD_IND
	      ,A.ETC_DRUG_CONCEPT_LINK_IND
	      ,A.ETC_PARENT_ETC_ID
	      ,A.ETC_FORMULARY_LEVEL_IND
	      ,A.ETC_PRESENTATION_SEQNO
	      ,A.ETC_ULTIMATE_PARENT_ETC_ID
	      ,A.ETC_HIERARCHY_LEVEL
	      ,A.ETC_SORT_NUMBER
	      ,A.ETC_RETIRED_IND
	      ,A.ETC_RETIRED_DATE
	FROM 
		FDB.dbo.RETCTBL0_ETC_ID AS A
		JOIN
		FDB.dbo.RETCTBL0_ETC_ID AS ROOT
			ON
			A.ETC_PARENT_ETC_ID = ROOT.ETC_ID
	WHERE 
		ROOT.ETC_ID IN (154, 5886) ---> from 148 take everything from branches 154 and 5886 to their leaves. From 148 exclude branch 159.
---		ROOT.ETC_ID IN ( 5886)
		AND A.ETC_HIERARCHY_LEVEL = ROOT.ETC_HIERARCHY_LEVEL + 1 ---> anchor (R0)

	UNION ALL

	SELECT A.ETC_ID
	      ,A.ETC_NAME
	      ,A.ETC_ULTIMATE_CHILD_IND
	      ,A.ETC_DRUG_CONCEPT_LINK_IND
	      ,A.ETC_PARENT_ETC_ID
	      ,A.ETC_FORMULARY_LEVEL_IND
	      ,A.ETC_PRESENTATION_SEQNO
	      ,A.ETC_ULTIMATE_PARENT_ETC_ID
	      ,A.ETC_HIERARCHY_LEVEL
	      ,A.ETC_SORT_NUMBER
	      ,A.ETC_RETIRED_IND
	      ,A.ETC_RETIRED_DATE
	FROM 
		FDB.dbo.RETCTBL0_ETC_ID AS A
		JOIN
		CTE_Recursion AS R
			ON
			A.ETC_PARENT_ETC_ID = R.ETC_ID
	WHERE 
		A.ETC_HIERARCHY_LEVEL = R.ETC_HIERARCHY_LEVEL + 1 ---> R1
	)
	SELECT
		   ETC_ID
		 , ETC_NAME
		 , ETC_ULTIMATE_CHILD_IND
		 , ETC_PARENT_ETC_ID
		 , ETC_HIERARCHY_LEVEL
		 , ETC_SORT_NUMBER
	INTO
		#CTE_Recursion_DiabeticTherapy
	FROM	
		CTE_Recursion
	ORDER BY
		  ETC_ULTIMATE_CHILD_IND
		, ETC_HIERARCHY_LEVEL
		, ETC_SORT_NUMBER
;

/****** Script for Selecting all leaves branching from root (now Diabetic Therapy (148))  ******/

--- number of ndc codes per etc_id
SELECT  
	  COUNT(NDC) AS COUNT_NDCCodes
    , A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_FORMULARY_LEVEL_IND
    , A.ETC_PRESENTATION_SEQNO
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_DiabeticTherapy AS R
		ON
		A.ETC_ID = R.ETC_ID
	LEFT JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 
	ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
GROUP BY
	  A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_FORMULARY_LEVEL_IND
    , A.ETC_PRESENTATION_SEQNO
ORDER BY 
	  A.ETC_PARENT_ETC_ID
	, A.ETC_PRESENTATION_SEQNO
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_ULTIMATE_CHILD_IND
;

--- creating etc groups for diabetic therapy
DROP TABLE IF EXISTS Datalogy.ds.ETC_DiabeticTherapy
;
SELECT 
	DISTINCT
	  A.ETC_NAME
	, A.ETC_ID
	, NDC
INTO 
	Datalogy.ds.ETC_DiabeticTherapy
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_DiabeticTherapy AS R
		ON
		A.ETC_ID = R.ETC_ID
	JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 
	ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
;

SELECT COUNT(DISTINCT NDC) FROM Datalogy.ds.ETC_DiabeticTherapy; ---5984
SELECT COUNT(DISTINCT etc_id) FROM Datalogy.ds.ETC_DiabeticTherapy; ---34

/****** 
all etc ids associated with Cardiovascular Therapy Agents 
******/

DROP TABLE IF EXISTS #CTE_Recursion_CardiovascularTherapyAgents
;
WITH CTE_Recursion AS (

	SELECT A.ETC_ID
	      ,A.ETC_NAME
	      ,A.ETC_ULTIMATE_CHILD_IND
	      ,A.ETC_DRUG_CONCEPT_LINK_IND
	      ,A.ETC_PARENT_ETC_ID
	      ,A.ETC_FORMULARY_LEVEL_IND
	      ,A.ETC_PRESENTATION_SEQNO
	      ,A.ETC_ULTIMATE_PARENT_ETC_ID
	      ,A.ETC_HIERARCHY_LEVEL
	      ,A.ETC_SORT_NUMBER
	      ,A.ETC_RETIRED_IND
	      ,A.ETC_RETIRED_DATE
	FROM 
		FDB.dbo.RETCTBL0_ETC_ID AS A
		JOIN
		FDB.dbo.RETCTBL0_ETC_ID AS ROOT
			ON
			A.ETC_PARENT_ETC_ID = ROOT.ETC_ID
	WHERE 
		ROOT.ETC_ID = 2553  ---> take the entire 2553 tree
		AND A.ETC_HIERARCHY_LEVEL = ROOT.ETC_HIERARCHY_LEVEL + 1 ---> anchor (R0)

	UNION ALL

	SELECT A.ETC_ID
	      ,A.ETC_NAME
	      ,A.ETC_ULTIMATE_CHILD_IND
	      ,A.ETC_DRUG_CONCEPT_LINK_IND
	      ,A.ETC_PARENT_ETC_ID
	      ,A.ETC_FORMULARY_LEVEL_IND
	      ,A.ETC_PRESENTATION_SEQNO
	      ,A.ETC_ULTIMATE_PARENT_ETC_ID
	      ,A.ETC_HIERARCHY_LEVEL
	      ,A.ETC_SORT_NUMBER
	      ,A.ETC_RETIRED_IND
	      ,A.ETC_RETIRED_DATE
	FROM 
		FDB.dbo.RETCTBL0_ETC_ID AS A
		JOIN
		CTE_Recursion AS R
			ON
			A.ETC_PARENT_ETC_ID = R.ETC_ID
	WHERE 
		A.ETC_HIERARCHY_LEVEL = R.ETC_HIERARCHY_LEVEL + 1 ---> R1
	)
	SELECT
		   ETC_ID
		 , ETC_NAME
		 , ETC_ULTIMATE_CHILD_IND
		 , ETC_PARENT_ETC_ID
		 , ETC_HIERARCHY_LEVEL
		 , ETC_SORT_NUMBER
	INTO
		#CTE_Recursion_CardiovascularTherapyAgents
	FROM	
		CTE_Recursion
;

/****** Script for Selecting all leaves branching from root  ******/
-- first go through all ETC_NAME associated with root (ETC_PARENT_ETC_ID = 2553)
-- remove any that do not apply

--- number of ndc codes per etc_id
SELECT  
	  COUNT(NDC) AS COUNT_NDCCodes
    , A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_CardiovascularTherapyAgents AS R
		ON
		A.ETC_ID = R.ETC_ID
	LEFT JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 
	ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
--	A.ETC_PARENT_ETC_ID  IN (216, 201, 205, 259, 1257, 3609, 5955, 6228, 6929, 3886) --> Remove any branches that end in leaves that we are not interested in
--	AND A.ETC_ID NOT IN (6022, 6186, 2720, 2721, 2708, 264, 265, 2783, 6903, 4549, 6430, 6551) --> Remove any leaves that we are not interested in
GROUP BY
	  A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
ORDER BY 
	  ETC_PARENT_ETC_ID
	, ETC_HIERARCHY_LEVEL
	, ETC_ULTIMATE_CHILD_IND
;

--- creating etc groups for cardiovascular therapy
DROP TABLE IF EXISTS Datalogy.ds.ETC_CardiovascularTherapyAgents
;
SELECT 
	DISTINCT
	  A.ETC_ID
	, NDC
INTO 
	Datalogy.ds.ETC_CardiovascularTherapyAgents
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_CardiovascularTherapyAgents AS R
		ON
		A.ETC_ID = R.ETC_ID
	JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 
	A.ETC_PARENT_ETC_ID NOT IN (216, 201, 205, 259, 1257, 3609, 5955, 6228, 6929, 3886) --> Remove any branches that end in leaves that we are not interested in
	AND A.ETC_ID NOT IN (6022, 6186, 2720, 2721, 2708, 264, 265, 2783, 6903, 4549, 6430, 6551) --> Remove any leaves that we are not interested in
	AND ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
;
---40,859

SELECT COUNT(DISTINCT NDC) FROM Datalogy.ds.ETC_CardiovascularTherapyAgents; ---39038
SELECT COUNT(DISTINCT etc_id) FROM Datalogy.ds.ETC_CardiovascularTherapyAgents; ---84

/****** 
all etc ids associated with Central Nervous System Agents
******/

DROP TABLE IF EXISTS #CTE_Recursion_CentralNervousSystemAgents
;
WITH CTE_Recursion AS (

	SELECT A.ETC_ID
	      ,A.ETC_NAME
	      ,A.ETC_ULTIMATE_CHILD_IND
	      ,A.ETC_DRUG_CONCEPT_LINK_IND
	      ,A.ETC_PARENT_ETC_ID
	      ,A.ETC_FORMULARY_LEVEL_IND
	      ,A.ETC_PRESENTATION_SEQNO
	      ,A.ETC_ULTIMATE_PARENT_ETC_ID
	      ,A.ETC_HIERARCHY_LEVEL
	      ,A.ETC_SORT_NUMBER
	      ,A.ETC_RETIRED_IND
	      ,A.ETC_RETIRED_DATE
	FROM 
		FDB.dbo.RETCTBL0_ETC_ID AS A
		JOIN
		FDB.dbo.RETCTBL0_ETC_ID AS ROOT
			ON
			A.ETC_PARENT_ETC_ID = ROOT.ETC_ID
	WHERE 
		ROOT.ETC_ID = 6721  ---> take all the branches from this point on
		AND A.ETC_HIERARCHY_LEVEL = ROOT.ETC_HIERARCHY_LEVEL + 1 ---> anchor (R0)

	UNION ALL

	SELECT A.ETC_ID
	      ,A.ETC_NAME
	      ,A.ETC_ULTIMATE_CHILD_IND
	      ,A.ETC_DRUG_CONCEPT_LINK_IND
	      ,A.ETC_PARENT_ETC_ID
	      ,A.ETC_FORMULARY_LEVEL_IND
	      ,A.ETC_PRESENTATION_SEQNO
	      ,A.ETC_ULTIMATE_PARENT_ETC_ID
	      ,A.ETC_HIERARCHY_LEVEL
	      ,A.ETC_SORT_NUMBER
	      ,A.ETC_RETIRED_IND
	      ,A.ETC_RETIRED_DATE
	FROM 
		FDB.dbo.RETCTBL0_ETC_ID AS A
		JOIN
		CTE_Recursion AS R
			ON
			A.ETC_PARENT_ETC_ID = R.ETC_ID
	WHERE 
		A.ETC_HIERARCHY_LEVEL = R.ETC_HIERARCHY_LEVEL + 1 ---> R1
	)
	SELECT
		   ETC_ID
		 , ETC_NAME
		 , ETC_ULTIMATE_CHILD_IND
		 , ETC_PARENT_ETC_ID
		 , ETC_HIERARCHY_LEVEL
		 , ETC_SORT_NUMBER
	INTO
		#CTE_Recursion_CentralNervousSystemAgents
	FROM	
		CTE_Recursion
;

/****** Script for Selecting all leaves branching from root  ******/
-- first go through all ETC_NAME associated with root (ETC_PARENT_ETC_ID = 2584)
-- remove any that do not apply

--- number of ndc codes per etc_id
SELECT  
	 DISTINCT 
	  A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_SORT_NUMBER
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_CentralNervousSystemAgents AS R
		ON
		A.ETC_ID = R.ETC_ID
	LEFT JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 
	ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
ORDER BY 
---	  ETC_PARENT_ETC_ID
--- , ETC_ULTIMATE_CHILD_IND
	 A.ETC_SORT_NUMBER
    , ETC_HIERARCHY_LEVEL
;

SELECT  
	  COUNT(NDC) AS COUNT_NDCCodes
    , A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_FORMULARY_LEVEL_IND
    , A.ETC_PRESENTATION_SEQNO
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_CentralNervousSystemAgents AS R
		ON
		A.ETC_ID = R.ETC_ID
	LEFT JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 
	ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
GROUP BY
	  A.ETC_ID
	, B.ETC_ID
	, A.ETC_NAME
	, A.ETC_ULTIMATE_CHILD_IND
    , A.ETC_PARENT_ETC_ID
    , A.ETC_ULTIMATE_PARENT_ETC_ID
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_FORMULARY_LEVEL_IND
    , A.ETC_PRESENTATION_SEQNO
ORDER BY 
	  A.ETC_PARENT_ETC_ID
	, A.ETC_PRESENTATION_SEQNO
	, A.ETC_HIERARCHY_LEVEL
	, A.ETC_ULTIMATE_CHILD_IND
;


--- creating etc groups for cns agents
DROP TABLE IF EXISTS Datalogy.ds.ETC_CentralNervousSystemAgents
;
SELECT 
	DISTINCT
	  A.ETC_ID
	, NDC
INTO 
	Datalogy.ds.ETC_CentralNervousSystemAgents
FROM 
	FDB.dbo.RETCTBL0_ETC_ID A
	JOIN
	#CTE_Recursion_CentralNervousSystemAgents AS R
		ON
		A.ETC_ID = R.ETC_ID
	JOIN
	FDB.dbo.RETCNDC0_ETC_NDC B
		ON
		A.ETC_ID = B.ETC_ID
WHERE 	
	    ETC_COMMON_USE_IND = 1
	AND ETC_DEFAULT_USE_IND = 1
;