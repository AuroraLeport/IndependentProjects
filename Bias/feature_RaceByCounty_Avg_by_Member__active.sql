/******************* 
CREATOR: AURORA LEPORT
DATE: 7/7/2021
PURPOSE: Creating a probability of race for members for all active participants
  -- geolocation comes from Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d
  -- script is first preprocessing in SQL to include columns necessary for R to predict Race
  -- race probability us calculated in R, RaceFeature_Depression.R, and returns a .csv file
  -- table is uploaded to SQL with predictions for further preprocessing
  -- preprocess script is run in sql to get average predicted probability across members with multiple rows and create binary columns

TABELS USED:
Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d

see: https://www.policymap.com/maps
				 Zip
			/	Tract  \
		   /	Block	\
		  /		Address  \
*******************/ 

SELECT COUNT(*) FROM Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d 
WHERE tract_FIPS IS NULL OR tract_FIPS = 'NA' ---1223

SELECT COUNT(*) FROM Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d  
WHERE CodeMaster_Block IS NULL ---95,114

--=============================================================================
-- components necessary to create race function
--=============================================================================

--=============================================================================
--------- Clean County
--- county code will be based on tract_FIPS, which for some members, is a many to one (see 
--- Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d) for more detail. 
--=============================================================================

DROP TABLE IF EXISTS #Cleaned_tractFIPS
;
SELECT PartyKey_active, FinalMember_Address_active, Zipcode, tract_FIPS, CodeMaster_Block 
INTO #Cleaned_tractFIPS
FROM Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d 
WHERE (tract_FIPS IS NOT NULL ---12,383
OR tract_FIPS <> 'NA')
;

SELECT COUNT(DISTINCT PartyKey_active) FROM Datalogy.ds.SVI2018US_to_ZIPTRACT062019_to_FinalMemberAddress_UPDATE__active_360d ---1,457,837
SELECT COUNT(DISTINCT PartyKey_active) FROM #Cleaned_tractFIPS; --1,456,692


--=============================================================================
-- Race Components County Level
--=============================================================================
DROP TABLE IF EXISTS #TEMP_Race_Components_County
;
SELECT 
	DISTINCT 
	  M.PartyKey
	, MemberFirstName
	, MemberLastName AS surname
	, CAST(Demo_active.Age_at_Prediction AS INT) AS age
	, CASE 
		WHEN Demo_active.Gender = 'M' THEN 0
		WHEN Demo_active.Gender = 'F' THEN 1
	ELSE NULL
	END AS sex
	, COALESCE(FM.State, S.ST_ABBR) AS state
	, RIGHT(LEFT(tract_FIPS, 5),3) AS county
INTO #TEMP_Race_Components_County
FROM Datalogy.ppl.active_members AS M
	LEFT JOIN
	BatchImportABCBS.dbo.FinalMember AS FM
		ON
		FM.PartyKey = M.PartyKey
	LEFT JOIN
	#Cleaned_tractFIPS AS BlockFIPS  ---293,167
		ON
		M.PartyKey = BlockFIPS.PartyKey_active
	LEFT JOIN
	Datalogy.ppl.feature_Demographics__active AS Demo_active
		ON
		M.PartyKey = Demo_active.PartyKey
	LEFT JOIN
	(SELECT ST_ABBR, IIF(LEN(CAST(FIPS AS bigint))=10, '0'+CAST(CAST(FIPS AS bigint) AS varchar(20)), CAST(CAST(FIPS AS bigint) AS varchar(20))) AS FIPS 
	 FROM Datalogy.ds.SVI2018_US) AS S --> FIPS aka tract is unique per row
		ON
		 BlockFIPS.tract_FIPS = S.FIPS
WHERE (tract_FIPS IS NOT NULL AND tract_FIPS <> 'NA' AND Demo_active.Gender IS NOT NULL AND Demo_active.Age_at_Prediction IS NOT NULL)
; ---1,491,221

----check
SELECT * FROM #TEMP_Race_Components_County WHERE age IS NULL ---594
SELECT * FROM #TEMP_Race_Components_County WHERE surname IS NULL
SELECT * FROM #TEMP_Race_Components_County WHERE sex IS NULL
SELECT * FROM #TEMP_Race_Components_County WHERE county = 'NA'
SELECT * FROM #TEMP_Race_Components_County WHERE STATE IS NULL 
SELECT * FROM #TEMP_Race_Components_County WHERE STATE = '??' 
SELECT * FROM #TEMP_Race_Components_County WHERE STATE = 'VI' 
SELECT * FROM #TEMP_Race_Components_County WHERE county = '010' 

DROP TABLE IF EXISTS Datalogy.aleport.Race_Components_County;
SELECT * 
INTO Datalogy.aleport.Race_Components_County
FROM #TEMP_Race_Components_County
WHERE state <> '??' AND state <> 'VI'
; --1490868

SELECT COUNT(DISTINCT PartyKey) FROM Datalogy.ppl.active_members; ---1,597,930
SELECT COUNT(DISTINCT PartyKey) FROM #TEMP_Race_Components_County; ---1455572
SELECT COUNT(DISTINCT PartyKey) FROM Datalogy.aleport.Race_Components_County; ---1,455,406
SELECT COUNT(PartyKey) FROM Datalogy.aleport.Race_Components_County; ---1490865
SELECT DISTINCT state FROM Datalogy.aleport.Race_Components_County; --52

--=============================================================================
-- Preprocess in R to add probability race
-- insert into SQL server as Datalogy.aleport.PredictedRaceCounty_ActiveMembers
-- Continue Preprocessing steps here
-- Probabilities were imputed for 71971 surnames that could not be matched to Census list.
--=============================================================================
SELECT COUNT(*) FROM Datalogy.ppl.active_members; --1597930
SELECT COUNT(*) FROM Datalogy.aleport.PredictedRaceCounty_ActiveMembers; --1,490,865
SELECT COUNT(DISTINCT PartyKey) FROM Datalogy.aleport.PredictedRaceCounty_ActiveMembers; --1455406

-- How many members have many geolocations? -- the results of these will need to be averaged
DROP TABLE IF EXISTS #TEMP_MultipleGeo
;
SELECT PartyKey, COUNT(PartyKey) AS Count_Geos
INTO #TEMP_MultipleGeo
FROM Datalogy.aleport.PredictedRaceCounty_ActiveMembers 
GROUP BY PartyKey
HAVING COUNT(PartyKey) > 1
; ---29,802

-- Some members have duplicate rows due to first/last names that are typos. Will take distinct on partykey + predicted probs
DROP TABLE IF EXISTS #Cleaned_PredictedRaceCounty_ActiveMembers
;
SELECT 
DISTINCT
	 PartyKey
	,pred_whi
    ,pred_bla
    ,pred_his
    ,pred_asi
    ,pred_oth
INTO #Cleaned_PredictedRaceCounty_ActiveMembers
FROM Datalogy.aleport.PredictedRaceCounty_ActiveMembers
; --1,483,688

SELECT COUNT(*) FROM #Cleaned_PredictedRaceCounty_ActiveMembers --1,483,688
SELECT COUNT(DISTINCT PartyKey) FROM #Cleaned_PredictedRaceCounty_ActiveMembers--1,455,406

--DROP TABLE IF EXISTS #TEMP_MultipleGeo;
--SELECT PartyKey, COUNT(PartyKey) AS Count_Geos
--INTO #TEMP_MultipleGeo
--FROM #Cleaned_PredictedRaceCounty_ActiveMembers
--GROUP BY PartyKey
--HAVING COUNT(PartyKey) > 1
--; ---23,240


------------------------------------------------------------------------------------------------------------------------------------
-- Approach:
--    Average the stats across distinct rows per PartyKey
--
DROP TABLE IF EXISTS Datalogy.ppl.PredictedRaceCounty_ActiveMembers_Avg3_by_Member__active
;
SELECT 
	  PartyKey
	, AVG(CAST(pred_whi AS FLOAT)) AS pred_whi_avg
    , AVG(CAST(pred_bla AS FLOAT)) AS pred_bla_avg
    , AVG(CAST(pred_his AS FLOAT)) AS pred_his_avg
    , AVG(CAST(pred_asi AS FLOAT)) AS pred_asi_avg
    , AVG(CAST(pred_oth AS FLOAT)) AS pred_oth_avg
	, IIF(    AVG(CAST(pred_whi AS FLOAT)) > AVG(CAST(pred_bla AS FLOAT))
	      AND AVG(CAST(pred_whi AS FLOAT)) > AVG(CAST(pred_his AS FLOAT))
		  AND AVG(CAST(pred_whi AS FLOAT)) > AVG(CAST(pred_asi AS FLOAT))
		  AND AVG(CAST(pred_whi AS FLOAT)) > AVG(CAST(pred_oth AS FLOAT)), 1, 0) AS white
	, IIF(    AVG(CAST(pred_bla AS FLOAT)) > AVG(CAST(pred_whi AS FLOAT))
	      AND AVG(CAST(pred_bla AS FLOAT)) > AVG(CAST(pred_his AS FLOAT))
		  AND AVG(CAST(pred_bla AS FLOAT)) > AVG(CAST(pred_asi AS FLOAT))
		  AND AVG(CAST(pred_bla AS FLOAT)) > AVG(CAST(pred_oth AS FLOAT)), 1, 0) AS black
	, IIF(    AVG(CAST(pred_his AS FLOAT)) > AVG(CAST(pred_bla AS FLOAT))
	      AND AVG(CAST(pred_his AS FLOAT)) > AVG(CAST(pred_whi AS FLOAT))
		  AND AVG(CAST(pred_his AS FLOAT)) > AVG(CAST(pred_asi AS FLOAT))
		  AND AVG(CAST(pred_his AS FLOAT)) > AVG(CAST(pred_oth AS FLOAT)), 1, 0) AS hispanic
	, IIF(    AVG(CAST(pred_asi AS FLOAT)) > AVG(CAST(pred_bla AS FLOAT))
	      AND AVG(CAST(pred_asi AS FLOAT)) > AVG(CAST(pred_his AS FLOAT))
		  AND AVG(CAST(pred_asi AS FLOAT)) > AVG(CAST(pred_whi AS FLOAT))
		  AND AVG(CAST(pred_asi AS FLOAT)) > AVG(CAST(pred_oth AS FLOAT)), 1, 0) AS asian
	, IIF(    AVG(CAST(pred_oth AS FLOAT)) > AVG(CAST(pred_bla AS FLOAT))
	      AND AVG(CAST(pred_oth AS FLOAT)) > AVG(CAST(pred_his AS FLOAT))
		  AND AVG(CAST(pred_oth AS FLOAT)) > AVG(CAST(pred_asi AS FLOAT))
		  AND AVG(CAST(pred_oth AS FLOAT)) > AVG(CAST(pred_whi AS FLOAT)), 1, 0) AS other
INTO Datalogy.ppl.PredictedRaceCounty_ActiveMembers_Avg3_by_Member__active
FROM #Cleaned_PredictedRaceCounty_ActiveMembers
GROUP BY PartyKey
;

SELECT COUNT(DISTINCT PartyKey) FROM Datalogy.ppl.active_members; ---1597930
SELECT COUNT(*) FROM Datalogy.ppl.PredictedRaceCounty_ActiveMembers_Avg3_by_Member__active --1455406
SELECT COUNT(DISTINCT PartyKey) FROM Datalogy.ppl.PredictedRaceCounty_ActiveMembers_Avg3_by_Member__active --1455406

SELECT 
	  COUNT(M.PartyKey)
	, SUM(M.white)* 100.0 /		COUNT(M.PartyKey) AS percent_white
	, SUM(M.black)* 100.0 /		COUNT(M.PartyKey) AS percent_black
	, SUM(M.hispanic)* 100.0 /  COUNT(M.PartyKey) AS percent_hispanic
	, SUM(M.asian)* 100.0 /		COUNT(M.PartyKey) AS percent_asian
	, SUM(M.other)* 100.0 /		COUNT(M.PartyKey) AS percent_other
FROM Datalogy.ppl.PredictedRaceCounty_ActiveMembers_Avg3_by_Member__active AS M
JOIN
	Datalogy.ppl.active_members_DepressionAnxietyTrain1819TwoYearTarget_Elig720d_NoPrevAnxiety AS D 
		ON
		M.PartyKey = D.PartyKey
;
-- (No column name)		percent_white	percent_black	percent_hispanic	percent_asian	percent_other
-- ALL ACTIVE: 1455406	78.022558653736	9.391331353587	10.066538134376		2.392871817211	0.116462347963
-- DEPRESSION: 295176	79.383147681383	9.159281242377	9.313426565845		2.057077811204	0.076903271268