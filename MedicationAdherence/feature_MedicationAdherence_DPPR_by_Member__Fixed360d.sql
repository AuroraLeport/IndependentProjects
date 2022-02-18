/******************* 
CREATOR: AURORA LEPORT
DATE: 9/09/2021
PURPOSE: Formula for Medication Adherence. Daily Polypharmacy Possession Ratio aka DPPR.

It estimates the proportion of time a patient had medication available for use by considering the presence or absence of 
multiple medications on each day in the observation period.

Here we calculated possession rates from refill histories over X months.

DPPR >= 80 is compliant
DPPR < 80 is non compliant

This example includes ETC Codes from:
--- Datalogy.ds.ETC_CardiovascularTherapyAgents
--- Datalogy.ds.ETC_DiabeticTherapy
Dispensed between '2019-01-01' AND '2020-01-01'

* need to have variables named the following: 
-- PartyKey: ID - id of patient
 -- > group - user defined drug group for etc code
-- ServiceDate: supply_date - date of supply
-- MetricDecimalQuantity: quantity - quantity of medication supplied
-- ObservationEndDate: end_date - readmission date (this is the final date used in calculations) 
-- DailyDosage: dose - dose of medication per day
;
Period:
* sort start_dates dataset by ID and start_date, want to find if patient had staggered start dates
* if a patient has staggered start dates then class a new supply start as starting a new period;
* want number of periods by patient and the start date of each new period;

assumptions:
* there should be no repeat supply_dates by group, etc_code and ID; Take the MAX days supply. 
* there should be complete fields for each observation - no missing cells e.g. no missing atc codes;

* Only medications prescribed on a regular basis (> 3 months’ supply) are included. 
i.e. Has at least four dispensing records for each of the etc groups. By doing this, we excluded 
primary non-adherence (ie, patients who obtained a first package but did not start the treatment) and enabled 
patients to build a medication taking habit, considering that 3 months is needed to adopt a new habit (pg 1183
"Operationalization and validation of a novel method to calculate adherence to polypharmacy with refill data from the 
Australian pharmaceutical benefits scheme (PBS) database)"

* Maximal gap can range is assumed to be zero:
The challenge in defining non-persistence in refill databases is to determine the onset of cessation, that is, the last 
gap beyond which medication use ceases. Mathematically, it amounts to setting a specific period of time (or threshold) that 
needs to be exceeded after the supply from the previous refill ends. Therefore, an individual is classified as non-persistent if 
they did not refill a medication within the given time threshold. The value of this maximal gap can range from zero (no 
gaps allowed in medication history) to a specific number of days.
*******************/
--=============================================================================
-- Declare important dates.
--=============================================================================
GO
DECLARE @DaysOfHistory INT = 365;
DECLARE @PredictedOn DATE = '2022-01-01';
DECLARE @HistoryThru DATE = DATEADD(DAY, -1, @PredictedOn); -- 1 day prior to the prediction date
DECLARE @HistoryFrom DATE = DATEADD(DAY, 1-@DaysOfHistory, @HistoryThru); -- 359 days prior to the last day in history 
SELECT @HistoryFrom, @HistoryThru; --2020-01-01	2020-12-31

/*--------------------------------------------------------------------------------------
Note: Same PartyKey, ETC_ID, ServiceDate may have multiple rows 
in FinalRx or #RxServiceClaims if we don't group by these 3 columns.
e.g.
PartyKey = '1134881' and etc_id = '4610' and ServiceDate = '2020-01-30'
PartyKey = '1439375' and etc_id = '6089' and ServiceDate = '2020-03-06'
---PartyKey IN ('3101807','19924','2703371','15994847','3868901','2280748','16140419','1486889','3718678','300445','12815379', '1439375')

-- although the paper the paper states:
	 therapeutic switching and therapeutic duplication should be considered as one medication (no duplication), and changes
	in dosage should be recognised and accounted for. Therapeutic duplication is defined as multiple medication use within the same therapeutic class, 
	and can result from therapeutic augmentation; prescription error must be excluded.
these seem to be duplications in the database and should therefore be removed.
e.g.
2703371	65504008	0100	1811393374	156	67877056105	metFORMIN HCl	2020-05-17	30
2703371	65503640	0100	1811393374	156	00378718505	metFORMIN HCl	2020-05-17	30
- paper: "A method for calculating adherence to polypharmacy from dispensing data records"
Isabelle Arnet � Ivo Abraham � Markus Messerli �Kurt E. Hersberger (2014).

For simplicity we pick the MAX(DaysSupply) for each PartyKey + ETC_ID + ServiceDate.
*/--------------------------------------------------------------------------------------

DROP TABLE IF EXISTS #RxServiceClaims_intermediate
;
	SELECT
		PartyKey
	  , ETC_ID
	  , ServiceDate 
	  , @PredictedOn AS ObservationEndDate
	  , MAX(CAST(DaysSupply AS float)) AS DaysSupply
	INTO
		#RxServiceClaims_intermediate
	FROM
		BatchImportABCBS.dbo.FinalRX AS FinalRx_cleaned
		JOIN
		Datalogy.ds.ETC_DiabeticTherapy AS ETC_DiabeticTherapy
			ON
			FinalRx_cleaned.NDCCode = ETC_DiabeticTherapy.NDC
	WHERE
		(ClaimStatus = '1' OR ClaimStatus IS NULL) 	            --> 
		AND PaidAmount >= 0							            --> 
		AND CAST(DaysSupply AS float) > 0                       --> Same as the filter in generating main Rx features 
		AND LOB IN ('US', 'BH', 'BC', 'BX', 'HA')               -->
		AND (ServiceDate<=@HistoryThru AND DATEADD(DAY, CAST(DaysSupply AS float)-1, ServiceDate)>=@HistoryFrom) --> (360 days prior to @PredictedOn)
		AND CAST(MetricDecimalQuantity AS float) > 0 ----> additional filter for calculating MME) AS FRx
	GROUP BY
		PartyKey
	  , ETC_ID
	  , ServiceDate

UNION   

	SELECT
		PartyKey
	  , ETC_ID
	  , ServiceDate 
	  , @PredictedOn AS ObservationEndDate
	  , MAX(CAST(DaysSupply AS float)) AS DaysSupply
	FROM
		BatchImportABCBS.dbo.FinalRX  AS FinalRx_cleaned
		JOIN
		Datalogy.ds.ETC_CardiovascularTherapyAgents AS ETC_CardiovascularTherapyAgents
			ON
			FinalRx_cleaned.NDCCode = ETC_CardiovascularTherapyAgents.NDC
	WHERE
		(ClaimStatus = '1' OR ClaimStatus IS NULL) 	            --> 
		AND PaidAmount >= 0							            --> 
		AND CAST(DaysSupply AS float) > 0                       --> Same as the filter in generating main Rx features 
		AND LOB IN ('US', 'BH', 'BC', 'BX', 'HA')               -->
		AND (ServiceDate<=@HistoryThru AND DATEADD(DAY, CAST(DaysSupply AS float)-1, ServiceDate)>=@HistoryFrom) --> (360 days prior to @PredictedOn)
		AND CAST(MetricDecimalQuantity AS float) > 0 ----> additional filter for calculating MME) AS FRx
	GROUP BY
		PartyKey
	  , ETC_ID
	  , ServiceDate
;
---distinct partykey: 466,881
select count(distinct partykey) from #RxServiceClaims_intermediate;
/*--------------------------------------------------------------------------------------
Has at least four dispensing records for each of the previously mentioned ATC groups. By doing this, we excluded 
primary non-adherence (ie, patients who obtained a first package but did not start the treatment) and enabled 
patients to build a medication taking habit, considering that 3 months is needed to adopt a new habit (pg 1183
"Operationalization and validation of a novel method to calculate adherence to polypharmacy with refill data from the 
Australian pharmaceutical benefits scheme (PBS) database)"
*/--------------------------------------------------------------------------------------
DROP TABLE IF EXISTS #RxServiceClaims
;
SELECT 
	RxClaims.PartyKey
  , RxClaims.ETC_ID
  , RxClaims.ServiceDate 
  , RxClaims.ObservationEndDate
  , RxClaims.DaysSupply
INTO
	#RxServiceClaims
FROM
	#RxServiceClaims_intermediate AS RxClaims
	LEFT JOIN
	(SELECT 
		  PartyKey
		, ETC_ID
		, COUNT(ETC_ID) AS Count_ECT
	FROM 
		#RxServiceClaims_intermediate
	GROUP BY 
		  PartyKey
		, ETC_ID
	HAVING 
		COUNT(ETC_ID) < 4
	) AS RemoveMembers --> Identify members with less than 4 dispensing records in any drug group
		ON
		RxClaims.PartyKey = RemoveMembers.PartyKey
WHERE RemoveMembers.PartyKey IS NULL --> Exclude members with less than 4 dispensing records
;
---distinct partykey: 193885
select count(distinct partykey) from #RxServiceClaims;
/*--------------------------------------------------------------------------------------
How many members are only prescribed one drug group? 85,797 / 193603 (44.3%)
select partykey, count(distinct etc_id) from #RxServiceClaims group by partykey having count(distinct etc_id) = 1
--------------------------------------------------------------------------------------*/

--=============================================================================
-- Find primary supply date for each theraputic class
-- Introduce Period and Next Period Date
--=============================================================================

-- Find first refill date for each ETC for each member.
DROP TABLE IF EXISTS #FirstRefillDate_per_ETC_PartyKey;
SELECT
	PartyKey
  , ETC_ID
  , ObservationEndDate 
  , MIN(ServiceDate) AS ServiceDate_1st
INTO
	#FirstRefillDate_per_ETC_PartyKey
FROM
	#RxServiceClaims
GROUP BY
	PartyKey
  , ETC_ID
  , ObservationEndDate
;

-- Find primary supply date (i.e. starting date for each period).
DROP TABLE IF EXISTS #PrimarySupplyDates_Period;
SELECT DISTINCT
	PartyKey
  , DENSE_RANK() OVER(Partition by PartyKey ORDER BY ServiceDate_1st) AS Period
  , ServiceDate_1st AS PeriodBeginDate
  , ObservationEndDate
INTO
	#PrimarySupplyDates_Period -- 255777
FROM
	#FirstRefillDate_per_ETC_PartyKey
;

-- creating Next period date 
DROP TABLE IF EXISTS #PrimarySupplyDates_NextPeriod
;
SELECT
	  A.PartyKey
	, A.Period
	, A.PeriodBeginDate AS ServiceDate
	, ISNULL(B.PeriodBeginDate, A.ObservationEndDate) AS NextPeriodDate
	, A.ObservationEndDate
INTO #PrimarySupplyDates_NextPeriod
FROM #PrimarySupplyDates_Period AS A
	LEFT JOIN
	#PrimarySupplyDates_Period AS B
		ON
		A.PartyKey = B.PartyKey
		AND A.Period + 1 = B.Period 
;

-- Identify dummy rows to be added
DROP TABLE IF EXISTS #Dummy_Refills;
SELECT
	Dummy.PartyKey
  , Dummy.ETC_ID
  , Dummy.DummyDate AS ServiceDate
  , Dummy.ObservationEndDate 
  , 0 AS DaysSupply
INTO
	#Dummy_Refills -- 24312 rows
FROM
	(
	SELECT
		F.PartyKey
	  , F.ETC_ID
	  , F.ObservationEndDate
	  , P.PeriodBeginDate AS DummyDate
	FROM
		#FirstRefillDate_per_ETC_PartyKey F
		JOIN
		#PrimarySupplyDates_Period P
			ON
			F.PartyKey = P.PartyKey
			AND F.ServiceDate_1st < P.PeriodBeginDate
	) Dummy        --> Identify 'potential' dummy refill: for each member for each ETC, find all PeriodBeginDate later than ServiceDate_1st
	LEFT JOIN
	#RxServiceClaims R
		ON
		Dummy.PartyKey = R.PartyKey
		AND Dummy.ETC_ID = R.ETC_ID
		AND Dummy.DummyDate = R.ServiceDate
WHERE
	R.PartyKey IS NULL --> Exclude the dummy refill if the ServiceDate already existed for the ETC for the member.
;

-- Union the extra dummy refills with the actual refills
DROP TABLE IF EXISTS #RxServiceClaims_DummyDates;
SELECT	
	U.PartyKey
  , U.ETC_ID
  , U.ServiceDate
  , U.ObservationEndDate
  , U.DaysSupply
  , DENSE_RANK() OVER (PARTITION BY U.PartyKey, U.ETC_ID ORDER BY U.ServiceDate) AS SupplyRank
INTO
	#RxServiceClaims_DummyDates -- 1,431,481
FROM
	(
	SELECT
		PartyKey
	  , ETC_ID
	  , ServiceDate
	  , ObservationEndDate 
	  , DaysSupply	
	FROM
		#RxServiceClaims

	UNION

	SELECT
		PartyKey
	  , ETC_ID
	  , ServiceDate
	  , ObservationEndDate 
	  , DaysSupply	
	FROM
		#Dummy_Refills
	) U
;

/*
-- examples that need "dummy fill":

select * from #PrimarySupplyDates_Period where PartyKey=12797 order by 2
select * from #FirstRefillDate_per_ETC_PartyKey where PartyKey=12797 order by 2
select * from #RxServiceClaims where PartyKey=12797 order by 2, 3
select * from #RxServiceClaims_DummyDates where PartyKey=12797 order by 2, 3

select * from #PrimarySupplyDates_Period where PartyKey=3413080 order by 2
select * from #FirstRefillDate_per_ETC_PartyKey where PartyKey=3413080 order by 2
select * from #RxServiceClaims where PartyKey=3413080 order by 2, 3
select * from #RxServiceClaims_DummyDates where PartyKey=3413080 order by 2, 3

-- examples that don't need 'dummy fill'

select * from #PrimarySupplyDates_Period where PartyKey=13123537 order by 2
select * from #FirstRefillDate_per_ETC_PartyKey where PartyKey=13123537 order by 2
select * from #RxServiceClaims where PartyKey=13123537 order by 2, 3
select * from #RxServiceClaims_DummyDates where PartyKey=13123537 order by 2, 3
*/

--=============================================================================
-- Next Supply Date
-- Time to next supply (days) at nth dispensing
-- diffn: Difference in time to next supply and duration (days) at nth dispensing
--=============================================================================

DROP TABLE IF EXISTS #NextSupplyDate_NoPeriod_RxServiceClaims_DummyDates;
SELECT
	A.PartyKey
  , A.SupplyRank
  , A.ETC_ID
  , A.ServiceDate 
  , ISNULL(B.ServiceDate, A.ObservationEndDate) AS NextSupplyDate
  , A.ObservationEndDate
  , A.DaysSupply
  , DATEDIFF(DAY, A.ServiceDate, ISNULL(B.ServiceDate, A.ObservationEndDate)) AS TimeToNextSupply
  , DATEDIFF(DAY, A.ServiceDate, ISNULL(B.ServiceDate, A.ObservationEndDate)) - A.DaysSupply AS Diff_TimeToNextSupply_DaysSupply
INTO 
	#NextSupplyDate_NoPeriod_RxServiceClaims_DummyDates -- 1431481
FROM 
	#RxServiceClaims_DummyDates AS A
	LEFT JOIN
	#RxServiceClaims_DummyDates AS B
		ON  A.PartyKey = B.PartyKey
		AND A.ETC_ID = B.ETC_ID
		AND A.SupplyRank + 1 = B.SupplyRank 
;

--=============================================================================
-- Period 
-- adding period to main table
--=============================================================================

DROP TABLE IF EXISTS #NextSupplyDate_RxServiceClaims_DummyDates
;
SELECT
	MainTable.PartyKey 
  , MainTable.SupplyRank
  , MainTable.ETC_ID
  , Period
  , MainTable.ServiceDate 	
  , MainTable.NextSupplyDate
  , MainTable.ObservationEndDate
  , MainTable.DaysSupply
  , MainTable.TimeToNextSupply
  , MainTable.Diff_TimeToNextSupply_DaysSupply
INTO #NextSupplyDate_RxServiceClaims_DummyDates
FROM #NextSupplyDate_NoPeriod_RxServiceClaims_DummyDates AS MainTable
	LEFT JOIN
		(SELECT PartyKey, Period, ServiceDate, NextPeriodDate
		 FROM #PrimarySupplyDates_NextPeriod
		) AS PrimaryPeriod
			ON
			MainTable.PartyKey = PrimaryPeriod.PartyKey
			AND MainTable.ServiceDate >= PrimaryPeriod.ServiceDate AND MainTable.ServiceDate < PrimaryPeriod.NextPeriodDate
;
--- TIME: 00:00:00

--=============================================================================
-- OverSupply
-- Days Not On Drug
--=============================================================================
DROP TABLE IF EXISTS ##os_dnod_RxServiceClaims_DummyDates;
SELECT  
	PartyKey 
  , SupplyRank
  , ETC_ID
  , Period
  , ServiceDate 	
  , NextSupplyDate
  , ObservationEndDate
  , DaysSupply
  , TimeToNextSupply
  , Diff_TimeToNextSupply_DaysSupply 
  , IIF(Diff_TimeToNextSupply_DaysSupply >= 0, Diff_TimeToNextSupply_DaysSupply, 0) AS DaysNotOnDrug
  , IIF(Diff_TimeToNextSupply_DaysSupply <= 0, ABS(Diff_TimeToNextSupply_DaysSupply), 0) AS OverSupply
INTO #os_dnod_RxServiceClaims_DummyDates
FROM #NextSupplyDate_RxServiceClaims_DummyDates
;

select count(distinct partykey) from #os_dnod_RxServiceClaims_DummyDates;

--=============================================================================
-- actual over supply (act_os)
-- actual days not on drug (act_dnod)
-- recursion
--=============================================================================
DROP TABLE IF EXISTS #CTE_RecursionTable
;
WITH CTE_Recursion AS (			
			
	SELECT		
		PartyKey	
	  , SupplyRank	
	  , ETC_ID
	  , DaysNotOnDrug		
	  , OverSupply		
	  , IIF(OverSupply-DaysNotOnDrug >= 0, OverSupply-DaysNotOnDrug, 0) AS act_os	
	  , IIF(OverSupply-DaysNotOnDrug < 0, ABS(OverSupply-DaysNotOnDrug), 0) AS act_dnod
	FROM		
		#os_dnod_RxServiceClaims_DummyDates	
	WHERE		
		SupplyRank = 1 --> anchor (R0)	
			
	UNION ALL		
			
	SELECT		
		T.PartyKey	
	  , T.SupplyRank   		
	  , T.ETC_ID 		
	  , T.DaysNotOnDrug    --> SupplyID=2		
	  , T.OverSupply	   --> SupplyID=2	
	  , IIF(R.act_os+T.OverSupply-T.DaysNotOnDrug >= 0, R.act_os+T.OverSupply-T.DaysNotOnDrug, 0) as act_os		
	  , IIF(R.act_os+T.OverSupply-T.DaysNotOnDrug < 0, ABS(R.act_os-T.DaysNotOnDrug+T.OverSupply), 0) as act_dnod		
--	  , R.act_os   --> SupplyID=1		
--	  , R.act_dnod --> SupplyID=1		
	FROM		
		#os_dnod_RxServiceClaims_DummyDates T	
		JOIN	
		CTE_Recursion R	
			ON
			T.PartyKey = R.PartyKey
			AND T.ETC_ID = R.ETC_ID
			AND T.SupplyRank = R.SupplyRank + 1 --> R1
)			
SELECT		
		PartyKey	
	  , SupplyRank	
	  , ETC_ID			
	  , DaysNotOnDrug		
	  , OverSupply			
	  , act_os
	  , act_dnod
INTO #CTE_RecursionTable
FROM			
	CTE_Recursion	
ORDER BY
	  PartyKey
	, ETC_ID
;

DROP TABLE IF EXISTS #Acutal_os_dnod_RxServiceClaims_DummyDates
;
SELECT
	MainTable.PartyKey 
  , MainTable.SupplyRank
  , MainTable.ETC_ID
  , Period
  , ServiceDate 	
  , NextSupplyDate
  , ObservationEndDate
  , DaysSupply
  , TimeToNextSupply
  , Diff_TimeToNextSupply_DaysSupply 
  , Rt.DaysNotOnDrug		
  , Rt.OverSupply			
  , Rt.act_os
  , Rt.act_dnod
INTO #Acutal_os_dnod_RxServiceClaims_DummyDates
FROM #os_dnod_RxServiceClaims_DummyDates AS MainTable
	JOIN
	#CTE_RecursionTable AS Rt
		ON
		MainTable.PartyKey = Rt.PartyKey
		AND MainTable.SupplyRank = Rt.SupplyRank
		AND MainTable.ETC_ID = Rt.ETC_ID 
;

--=============================================================================
-- Cumulative number of actual days not on drug by drug group and period (cum_act_dnod_period)
-- Cumulative number of days in period by drug group (cum_days_period)
--=============================================================================
DROP TABLE IF EXISTS #cum_RxServiceClaims_DummyDates
;
SELECT
	  PartyKey 
	, SupplyRank
	, ETC_ID
	, Period
	, ServiceDate 	
	, NextSupplyDate
	, ObservationEndDate
	, DaysSupply
	, TimeToNextSupply
	, Diff_TimeToNextSupply_DaysSupply 
	, DaysNotOnDrug		
	, OverSupply			
	, act_os
	, act_dnod
	, SUM(act_dnod) OVER (PARTITION BY PartyKey, ETC_ID, Period ORDER BY ServiceDate) AS cum_act_dnod_period
	, SUM(TimeToNextSupply) OVER (PARTITION BY PartyKey, ETC_ID, Period ORDER BY ServiceDate) AS cum_days_period
INTO
	#cum_RxServiceClaims_DummyDates
FROM
	#Acutal_os_dnod_RxServiceClaims_DummyDates
;

/* --=============================================================================
-- Calculating metrics by period, across drug groups. Will need these metrics to perform the final calculation.
see:
select * from #cum_RxServiceClaims_DummyDates   where partykey = 517145 order by period
select * from #Final_RxServiceClaims_DummyDates	where partykey = 517145 order by period
		
 Metrics:
-- MAX_cum_act_dnod_period
-- MAX_cum_days_period
-- number of drug groups in period n (Count_DrugGroups_Period)
-- observation window

-- Note: some members have > 365 days observation window. This is because the ServiceDate is before the observation window, but the Days Supply causes the 
end date to be within the ow. We should keep this because it gives insight into stockpiling prior to the observation window. 
*/--=============================================================================

---select * from #cum_RxServiceClaims_DummyDates   where partykey = 3917552 order by period
---select * from #Final_RxServiceClaims_DummyDates	where partykey = 3917552 order by period

DROP TABLE IF EXISTS #Final_RxServiceClaims_DummyDates
;
SELECT 
	DISTINCT
	  MainTable.PartyKey 
	, MainTable.ETC_ID
	, MainTable.Period
	, MAX_cum_act_dnod_period_TABLE.MAX_cum_act_dnod_period
	, MAX_cum_days_period_TABLE.MAX_cum_days_period
	, CountDrugGroups.Count_DrugGroups_Period
	, ow.ObservationWindow
INTO 
	#Final_RxServiceClaims_DummyDates
FROM
	#cum_RxServiceClaims_DummyDates AS MainTable
	LEFT JOIN
	(SELECT 
		  PartyKey
		, Period
		, COUNT(DISTINCT ETC_ID) AS Count_DrugGroups_Period
	FROM 
		#cum_RxServiceClaims_DummyDates
	GROUP BY
		  PartyKey
		, Period
	) AS CountDrugGroups   ---> number of drug groups per period
		ON
		MainTable.PartyKey = CountDrugGroups.PartyKey
		AND MainTable.Period = CountDrugGroups.Period
	LEFT JOIN
	(SELECT 
		  PartyKey
		, Period
		, ETC_ID
		, MAX(cum_act_dnod_period) AS MAX_cum_act_dnod_period
	FROM 
		#cum_RxServiceClaims_DummyDates
	GROUP BY
		  PartyKey
		, Period
		, ETC_ID
	) AS MAX_cum_act_dnod_period_TABLE ---> max number of days not on drug in a period across all drug groups in the period (this may vary for each group)
		ON
		MainTable.PartyKey = MAX_cum_act_dnod_period_TABLE.PartyKey
		AND MainTable.Period = MAX_cum_act_dnod_period_TABLE.Period
		AND MainTable.ETC_ID = MAX_cum_act_dnod_period_TABLE.ETC_ID
	LEFT JOIN
	(SELECT 
		  PartyKey
		, Period
		, MAX(cum_days_period) AS MAX_cum_days_period
	FROM 
		#cum_RxServiceClaims_DummyDates
	GROUP BY
		  PartyKey
		, Period
	) AS MAX_cum_days_period_TABLE ---> max number of days in a period across all drug groups in the period (this will be the same for each group)
		ON
		MainTable.PartyKey = MAX_cum_days_period_TABLE.PartyKey
		AND MainTable.Period = MAX_cum_days_period_TABLE.Period
	LEFT JOIN
	(SELECT
		  PartyKey
		, MIN(ServiceDate) AS MinServiceDate
		, ObservationEndDate
		, DATEDIFF(DAY, MIN(ServiceDate), ObservationEndDate) AS ObservationWindow
	FROM 
		#cum_RxServiceClaims_DummyDates
	GROUP BY
		  PartyKey
		, ObservationEndDate
	) AS ow
		ON
		MainTable.PartyKey = ow.PartyKey
;

--=============================================================================
-- Daily Polypharmacy Ratio
--============================================================================= 
DROP TABLE IF EXISTS Datalogy.ds.TEMP_DPPR_2021
;
SELECT
	  PartyKey
	, (SUM(Weighted_cum_act_dnod_period) / ObservationWindow) * 100 AS DPPR
INTO 
	Datalogy.ds.TEMP_DPPR_2021
FROM
	(SELECT 
		  PartyKey
		, Period
		, MAX_cum_days_period - (SUM(MAX_cum_act_dnod_period) / Count_DrugGroups_Period) AS Weighted_cum_act_dnod_period
		, ObservationWindow
	FROM 
		#Final_RxServiceClaims_DummyDates AS Final_Table
	GROUP BY
		  PartyKey
		, Period
		, MAX_cum_days_period
		, Count_DrugGroups_Period
		, ObservationWindow
	) AS Weighted_cum_act_dnod_period_TABLE  
GROUP BY 
	  PartyKey
	, ObservationWindow
;

SELECT COUNT(PartyKey) FROM Datalogy.ds.TEMP_DPPR_2020; ---193885
SELECT COUNT(PartyKey) FROM Datalogy.ds.TEMP_DPPR_2021; ---187884
--------------------------------------------------------------------------------------------END

--------------------------------------------------------------------------------------------CHECK: 

-- how many members are overestimated with MPR?
-- how many members are underestimated with MPRm?
DROP TABLE IF EXISTS ##Table_metrics
;
SELECT 
	  A.PartyKey
	, B.DPPR
	, A.MPR
	, A.MPRm
	, NTILE(100) OVER(ORDER BY B.DPPR asc) AS percentile_DPPR
	, NTILE(100) OVER(ORDER BY A.MPR asc) AS percentile_MPR
	, NTILE(100) OVER(ORDER BY A.MPRm asc) AS percentile_MPRm
	, (MPR - DPPR) AS Diff_MPR_DPPR
	, (MPR - MPRm) AS Diff_MPR_MPRm 
	, (MPRm - DPPR) AS Diff_MPRm_DPPR
INTO
	##Table_metrics
FROM 
	Datalogy.ds.TEMP_MPR_MPRm AS A
	JOIN
	Datalogy.ds.TEMP_DPPR AS B
		ON A.PartyKey = B.PartyKey
;
SELECT COUNT(PartyKey) FROM #Table_metrics; ---193596

MPR  (median 102.3%; Q1: 86.9 Q3: 115.7%) IQR: 28.8
MPRm (median 84.6%; Q1: 70.5%; Q3: 95.3%) IQR: 24.8
DPPR (median 93.8%; Q1: 81.09%; Q3: 99.2%) IQR: 18.1

--- 24.0% of the members (who have >=4 records per drug group) are missed 12173/50662
SELECT * FROM #Table_metrics ORDER BY DPPR --193590
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR < 80 --50662
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR < 80 AND MPR >= 80 ---12173/50662 (false negative)
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 80
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 80 AND MPR < 80 ---265/142941 (false positive)

SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR < 80 AND MPRm >= 80 --- (false negative)
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 80 AND MPRm < 80 --- (false positive)

--- 11.1% of the members (who have >=4 records per drug group) who have low DPPR med compliance would be considered compliant according to MPR
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR < 50 ---9892
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR < 50 AND MPR >= 50 ---1088/9892 (false negative)
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 50
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 50 AND MPR < 50 ---185/183711 (false positive)

SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR < 50 AND MPRm >= 50 ---83/9892 (false negative)
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 50 AND MPRm < 50 ---8068/183711 (false positive) 4.0%

--- compliant
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE DPPR >= 80 ---142941
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE MPR >= 80  ---154849
SELECT COUNT(PartyKey) FROM ##Table_metrics WHERE MPRm >= 80 ---107710

--- difference between mpr, mprm and dppr
SELECT MIN(MPR), MIN(MPRm), MIN(DPPR) FROM ##Table_metrics
SELECT MAX(MPR), MAX(MPRm), MAX(DPPR) FROM ##Table_metrics
SELECT AVG(MPR), AVG(MPRm), AVG(DPPR) FROM ##Table_metrics

SELECT COUNT(PartyKey), MAX(DPPR) AS Q1 FROM ##Table_metrics WHERE percentile_DPPR <= 25
SELECT COUNT(PartyKey), MAX(DPPR) AS Q2 FROM ##Table_metrics WHERE percentile_DPPR <= 50
SELECT COUNT(PartyKey), MAX(DPPR) AS Q3 FROM ##Table_metrics WHERE percentile_DPPR <= 75

SELECT COUNT(PartyKey), MAX(MPR) AS Q1 FROM ##Table_metrics WHERE percentile_MPR <= 25
SELECT COUNT(PartyKey), MAX(MPR) AS Q2 FROM ##Table_metrics WHERE percentile_MPR <= 50
SELECT COUNT(PartyKey), MAX(MPR) AS Q3 FROM ##Table_metrics WHERE percentile_MPR <= 75

SELECT COUNT(PartyKey), MAX(MPRm) AS Q1 FROM #Table_metrics WHERE percentile_MPRm <= 25
SELECT COUNT(PartyKey), MAX(MPRm) AS Q2 FROM #Table_metrics WHERE percentile_MPRm <= 50
SELECT COUNT(PartyKey), MAX(MPRm) AS Q3 FROM #Table_metrics WHERE percentile_MPRm <= 75


/*--------------------------------------------------------------------------------------
finding outliers: negative that do not involve end of the observation window. Combination therapy, where etc group should be divided.
	(inter quartile range x 1.5) + Q3 
--------------------------------------------------------------------------------------*/

SELECT A.PartyKey, ETC_ID, ServiceDate, NextSupplyDate, TimeToNextSupply, DaysSupply, Diff_TimeToNextSupply_DaysSupply, percentile_diff, MPR, MPRm, DPPR
FROM 
	##distribution_diff_negative A
	JOIN
	#Table_metrics B
		ON 
		A.PartyKey = B.PartyKey
WHERE Diff_TimeToNextSupply_DaysSupply < -34.5 
and A.PartyKey = 48218
AND NextSupplyDate <> '2021-01-01'
ORDER BY Diff_TimeToNextSupply_DaysSupply, A.PartyKey
;


DROP TABLE IF EXISTS #diff_alloriginalpks
;
SELECT A.PartyKey, ServiceDate, NextSupplyDate, ETC_ID, TimeToNextSupply, DaysSupply, Diff_TimeToNextSupply_DaysSupply, percentile_diff, MPR, MPRm, DPPR
INTO #diff_alloriginalpks
FROM 
	##distribution_diff_all A
	JOIN
	#Table_metrics B
		ON 
		A.PartyKey = B.PartyKey
ORDER BY A.PartyKey, ETC_ID, ServiceDate 
;

DROP TABLE IF EXISTS #diff_negativeoriginalpks
;
SELECT A.PartyKey, ETC_ID, ServiceDate, NextSupplyDate, TimeToNextSupply, DaysSupply, Diff_TimeToNextSupply_DaysSupply, percentile_diff, MPR, MPRm, DPPR
INTO 
	#diff_negativeoriginalpks
FROM 
	##distribution_diff_negative A
	JOIN
	#Table_metrics B
		ON 
		A.PartyKey = B.PartyKey
WHERE Diff_TimeToNextSupply_DaysSupply < -37 
ORDER BY Diff_TimeToNextSupply_DaysSupply, A.PartyKey
;

DROP TABLE IF EXISTS #OutlierNotInObservationWindow
;
SELECT DISTINCT PartyKey
INTO #OutlierNotInObservationWindow
FROM ##distribution_diff_negative WHERE Diff_TimeToNextSupply_DaysSupply < -34.5 AND NextSupplyDate <> '2021-01-01'
;

DROP TABLE IF EXISTS #diff_negative_examples
;
SELECT
	  U.PartyKey
	, U.ClaimNumber
	, U.ClaimLineNumber 
	, U.PrescriberID
	, U.ETC_ID
	, U.NDCCode
	, U.DrugProductName
	, U.ServiceDate 
	, U.DaysSupply 
INTO
	#diff_negative_examples
FROM
	(
	SELECT 
	DISTINCT
	  PartyKey
	, ClaimNumber
	, ClaimLineNumber 
	, PrescriberID
	, ETC_ID
	, NDCCode
	, DrugProductName
	, ServiceDate 
	, CAST(DaysSupply AS float) AS DaysSupply 
	FROM 
		BatchImportABCBS.dbo.FinalRX AS FRx
		JOIN
		Datalogy.ds.ETC_CardiovascularTherapyAgents AS ETC_CardiovascularTherapyAgents
			ON
			FRx.NDCCode = ETC_CardiovascularTherapyAgents.NDC
	WHERE 
		   ServiceDate<= '2020-12-31' AND DATEADD(DAY, CAST(DaysSupply AS float)-1, ServiceDate)>= '2020-01-02'
		AND (ClaimStatus = '1' OR ClaimStatus IS NULL) 	            --> 
		AND PaidAmount >= 0							            --> 
		AND CAST(DaysSupply AS float) > 0                       --> Same as the filter in generating main Rx features 
		AND LOB IN ('US', 'BH', 'BC', 'BX', 'HA')               -->
		AND CAST(MetricDecimalQuantity AS float) > 0 ----> additional filter for calculating MME 
	
UNION ALL

	SELECT 
	DISTINCT
	  PartyKey
	, ClaimNumber
	, ClaimLineNumber 
	, PrescriberID
	, ETC_ID
	, NDCCode
	, DrugProductName
	, ServiceDate 
	, CAST(DaysSupply AS float) AS DaysSupply 
	FROM 
		BatchImportABCBS.dbo.FinalRX AS FRx
		JOIN
		Datalogy.ds.ETC_DiabeticTherapy AS ETC_DiabeticTherapy
			ON
			FRx.NDCCode = ETC_DiabeticTherapy.NDC
	WHERE 
		 ServiceDate<= '2020-12-31' AND DATEADD(DAY, CAST(DaysSupply AS float)-1, ServiceDate)>= '2020-01-02'
		AND (ClaimStatus = '1' OR ClaimStatus IS NULL) 	            --> 
		AND PaidAmount >= 0							            --> 
		AND CAST(DaysSupply AS float) > 0                       --> Same as the filter in generating main Rx features 
		AND LOB IN ('US', 'BH', 'BC', 'BX', 'HA')               -->
		AND CAST(MetricDecimalQuantity AS float) > 0 ----> additional filter for calculating MME
	) AS U 
;

SELECT * FROM #diff_negativeoriginalpks WHERE PartyKey = '282107' ORDER BY etc_id, ServiceDate 
SELECT * FROM #diff_alloriginalpks WHERE PartyKey = '282107' ORDER BY etc_id, ServiceDate 
SELECT * FROM #diff_negative_examples    WHERE PartyKey = '282107' ORDER BY etc_id, ServiceDate 

SELECT PartyKey, ETC_ID, ServiceDate, COUNT(PartyKey)
FROM #diff_negative_examples
WHERE PartyKey = '1134881'
GROUP BY PartyKey, ETC_ID, ServiceDate
ORDER BY PartyKey, ETC_ID, ServiceDate, COUNT(PartyKey)