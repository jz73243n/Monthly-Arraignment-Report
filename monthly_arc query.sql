/*1.	Monthly arraignment report (please let me know who will take on)—we should build a prototype by mid-month in January and then run on the first of the month thereafter starting in Feb
a.	Year over year by month comparison of arraignments (charge that they went into arraignments with) 
i.	Misdemeanors
	1.	Volume
	2.	Med/avg bail requested
	3.	Med/avg bail set
	4.	# of pleas
	a.	Misdemeanor pleas
	b.	Violation pleas 
	5.	# of RORs 
	6.	# Supervised Release 
ii.	Felonies 
	1.	Volume 
	2.	Med/avg bail requested
	3.	Med/avg bail set
	4.	# of pleas (should be minimal—does this make sense to include?)
	a.	Rate of Misdemeanor pleas
	b.	Rate Felony pleas 
	c.	Rate Violation pleas
	5.	Rate of RORs
	6.	Rate of Supervised Release
	7.	Rate remanded 
*/

USE DMS;
IF OBJECT_ID('tempdb.dbo.#base', 'U') IS NOT NULL

DROP TABLE #base

-- create base table with defendantID, arraignment event ID and arraignment date in 2019 and 2020 and remove 'SNC'

SELECT  
pa.defendantID,
pa.arcEventID,
arcDate,
arcOutcome, 
scrTopCMID ,
scrTopCat ,
scrTopChg ,
arcOutcomeReason ,
arcTopCMID ,
arcTopCat ,
arcPart,
--bailreqAmt will be set in R
bailReqAmt,
bailSetAmt,
arcRelease =releaseStatus
INTO #base
FROM planning_arraignments2 pa
WHERE year(arcDate) >= 2020


IF OBJECT_ID('tempdb.dbo.##arc', 'U') IS NOT NULL
													
DROP TABLE ##arc

CREATE TABLE ##arc (
defendantID INT NOT NULL,
isDAT INT NULL,
arcEventID INT NULL,
arcDate DATE NULL,
scrEventID INT NULL,
scrTopCMID INT NULL,
scrTopCat VARCHAR(100) NULL,
scrTopChg VARCHAR(100) NULL,
scrTopDetail VARCHAR(200) NULL,
arcOutcome VARCHAR(200) NULL,
arcTopCMID INT NULL,
arcTopCat VARCHAR(100) NULL,
arcPart VARCHAR(100) NULL,
--bailreqAmt will be set in R
bailReqAmt money NULL,
bailSetAmt money NULL,
arcRelease VARCHAR(150) NULL,
arcDispo VARCHAR(150) NULL,
isBailQualified INT NULL
)

INSERT INTO ##arc
(defendantID,
 arcEventID,
 scrEventID,
 arcDate,
 scrTopCMID,
 isDAT,
 isBailQualified,
 scrTopCat ,
 scrTopChg ,
 arcOutcome ,
 arcTopCMID ,
 arcTopCat ,
--bailreqAmt will be set in R
 bailReqAmt,
 bailSetAmt ,
 arcRelease
 )
SELECT
#base.defendantID,
#base.arcEventID,
fe.firstEvtID AS scrEventID,
#base.arcDate,
#base.scrTopCMID ,
isDAT = 0,
pc.isBailQualified,
#base.scrTopCat,
#base.scrTopChg ,
#base.arcOutcome ,
#base.arcTopCMID ,
#base.arcTopCat ,
#base.bailReqAmt,
#base.bailSetAmt ,
#base.arcRelease
FROM #base 
LEFT JOIN planning_fe2 fe on fe.defendantID = #base.defendantID
LEFT JOIN planning_charges2 pc ON pc.chargemodificationid = #base.scrTopCMID



/* get charge details from SP */
 /*
EXEC(' USE PLANINTDB;
	  
	  DECLARE @CMID AS CMIDTableType
	  INSERT INTO @CMID
	  SELECT DISTINCT
	  scrTopCMID
	  FROM ##arc
	  UNION
	  SELECT DISTINCT
	  arcTOPCMID
	  FROM ##arc

	  EXEC dbo.getChargeDetails @CMID

	 USE DMS
	 ')
	 */

/* update screen top charge category */
UPDATE ##arc
SET scrTopDetail = pc.chargeDescription
FROM ##arc
JOIN (SELECT chargemodificationID,
			 category,
			 chargeClean,
			 chargeDescription
	  FROM dms.dbo.planning_charges2
	  ) pc ON pc.chargemodificationID = ##arc.scrTopCMID





/*
UPDATE ##arc
SET bailreqAmt = req.bailRequest 
FROM ##arc
JOIN (SELECT eventID,
			 bailrequesteventID
	  FROM evt
	 ) e on e.eventID = ##arc.arcEventID
JOIN (SELECT eventID,
			 bailRequest
	  FROM evt
	  WHERE bailRequest IS NOT NULL 
	  ) req on req.eventID = e.bailrequesteventid

UPDATE ##arc
SET bailreqAmt = ebd.bailAmount
FROM ##arc
JOIN (SELECT eventID,
			 bailrequesteventID
	 FROM evt
	 ) e on e.eventID = ##arc.arcEventID
JOIN (SELECT eventID,
			 bailAmount = min(bailAmount)
	  FROM eventlinkbaildetail
	  WHERE bailAmount IS NOT NULL
	  GROUP BY eventID
	  ) ebd on ebd.eventID = e.bailrequesteventid
WHERE bailReqAmt is NULL
*/


UPDATE ##arc
SET isDAT = 1
FROM ##arc
JOIN (SELECT defendantID,
			 arrestCaseID
	  FROM defendant
	  ) d ON d.defendantID = ##arc.defendantID
JOIN (SELECT arrestCaseID
	  FROM arrest
	  WHERE DATreturnDate IS NOT NULL
	  ) a ON a.arrestCaseID = d.arrestCaseID
WHERE d.arrestCaseID IS NOT NULL


UPDATE ##arc
SET isDAT = 0
FROM ##arc
JOIN defendant d On d.defendantID = ##arc.defendantID
JOIN olbs.dbo.olbs_record o ON o.arr_id_num = d.arrestID
JOIN tsSummary ts On ts.ecabNum  = d.ecabNum
JOIN screeningCaseTypeLU sc ON sc.screeningcaseTypeID = ts.mostRecentCaseType
WHERE isDAT = 1 AND sc.screeningcaseType NOT LIKE 'DAT%'
AND ISNULL(arr_proc_type,'ok') NOT IN ('A', 'D')


/*drop table ##planning_charges
EXEC(' use planintdb;
	  
	  DECLARE @defendantID as defTableType
	  INSERT INTO @defendantID
	  SELECT DISTINCT defendantID
	  FROM ##arc

	  EXEC dbo.getDispos @defendantID

	  ')
*/




UPDATE ##arc
set arcDispo = el.eventOutcome
FROM ##arc
JOIN (SELECT eventID,
			eventOutcomeID
	  FROM courtNoteOnEventOutcome
	  ) cn ON cn.eventID = ##arc.arcEventID
JOIN (SELECT eventoutcomeID,
			 eventOutcome
	  FROM eventOutcomeLU
	  WHERE isDisposition = 1
	  ) el ON el.eventOutcomeID = cn.eventOutcomeID



/* DATs issued */
IF OBJECT_ID('tempdb.dbo.##dat', 'U') IS NOT NULL
DROP TABLE ##dat

SELECT DISTINCT
fe.defendantID,
fe.firstEvtID,
pa.arcEventID,
scrDate,
arcDate = cast(NULL as Date),
noArraignDate = cast(NULL as Date),
scrTopCat = pc.category,
isDP,
isArraigned = 0,
isBWO = CASE WHEN EXISTS (SELECT 1
						  FROM (SELECT defendantID,
										 eventID
								  FROM evt
								  WHERE eventTypeid = 88 -- Not Arraigned
								  ) no_arc
							JOIN (SELECT eventID
								 FROM courtNoteOnEventOutcome
								 WHERE eventOutcomeID = 20 -- BWO
								 ) bwo ON bwo.eventID = no_arc.eventID
						WHERE no_arc.defendantID = fe.defendantID
						) THEN 1 ELSE 0 END
INTO ##dat
FROM planning_fe2 fe
LEFT JOIN planning_arraignments2 pa ON pa.defendantID = fe.defendantID
JOIN (SELECT arr_id_num
		FROM olbs.dbo.olbs_record
		WHERE LEFT(arr_date,2) IN ('18', '19', '20')
		AND arr_proc_type IN ('A', 'D')
		) o ON o.arr_id_num = fe.arrestID
LEFT JOIN (SELECT firstEvtID,
				  convert(date, firstEvtDate) as scrDate
		   FROM planning_fe2
		   WHERE isECAB = 1
		   ) e ON e.firstEvtID = fe.firstEvtID	   
LEFT JOIN (SELECT eventID,
			 chargemodificationiD
	  FROM eventlinkcharge
	  WHERE chargepriority = 1
	  ) elc on elc.eventID = fe.firstEvtID
LEFT JOIN (SELECT chargemodificationID,
			 category
	 FROM dms.dbo.planning_charges2
	  ) pc on pc.chargemodificationID = elc.chargemodificationID

	




INSERT INTO ##dat
SELECT DISTINCT
fe.defendantID,
fe.firstEvtID,
pa.arcEventID,
e.scrDate,
arcDate = cast(NULL as Date),
noArraignDate = cast(NULL as Date),
scrTopCat = pc.category,
fe.isDP,
isArraigned = 0,
isBWO = CASE WHEN EXISTS (SELECT 1
						  FROM (SELECT defendantID,
										 eventID
								  FROM evt
								  WHERE eventTypeid = 88 -- Not Arraigned
								  ) no_arc
							JOIN (SELECT eventID
								 FROM courtNoteOnEventOutcome
								 WHERE eventOutcomeID = 20 -- BWO
								 ) bwo ON bwo.eventID = no_arc.eventID
						WHERE no_arc.defendantID = fe.defendantID
						) THEN 1 ELSE 0 END
FROM defendant d
JOIN planning_fe2 fe on fe.defendantiD = d.DefendantId
JOIN arrest a ON a.arrestcaseID = d.arrestCaseID
LEFT JOIN planning_arraignments2 pa on pa.defendantID = fe.defendantID
LEFT JOIN ##dat ON ##dat.defendantID = d.defendantID
LEFT JOIN (SELECT firstEvtID,
				  firstEvtDate as scrDate
		   FROM planning_fe2 
		   WHERE isECAB = 1
		   ) e ON e.firstEvtID = fe.firstEvtID	   
LEFT JOIN (SELECT eventID,
			 chargemodificationiD
	  FROM eventlinkcharge
	  WHERE chargePriority = 1
	  ) elc on elc.eventID = fe.firstEvtID
LEFT JOIN (SELECT chargemodificationID,
			 category
	 FROM dms.dbo.planning_charges2
	  ) pc on pc.chargemodificationID = elc.chargemodificationID
WHERE a.DATReturnDate IS NOT NULL
AND YEAR(a.arrestDate) >= 2018 
AND ##dat.defendantID IS NULL



UPDATE ##dat
SET arcEventID = e.eventID
FROM ##dat
JOIN evt e ON e.defendantID = ##dat.defendantID AND eventTypeID = 9 AND e.eventDateTime IS NOT NULL

UPDATE ##dat
set isArraigned = 1,
	arcDate = CONVERT(DATE, e.eventdatetime)
FROM ##dat
JOIN evt e On e.eventID = ##dat.arcEventID AND e.eventDateTime IS NOT NULL

UPDATE ##dat
SET noArraignDate = eventDate
FROM ##dat
JOIN (SELECT defendantID,
			eventID, 
			eventDate = convert(date, eventdatetime)
	FROM evt
	WHERE eventTypeid = 88 -- Not Arraigned
	) no_arc ON no_arc.defendantID = ##dat.defendantID
JOIN (SELECT eventID
	FROM courtNoteOnEventOutcome
	WHERE eventOutcomeID = 20 -- BWO
	) bwo ON bwo.eventID = no_arc.eventID



DELETE FROM ##dat WHERE YEAR(arcDate) = 2018 OR YEAR(noArraignDate) = 2018 



/* GET BAIL REQUEST DETAILS FOR CLEANING */
IF OBJECT_ID('tempdb.dbo.##bail', 'U') IS NOT NULL
DROP TABLE ##bail

SELECT
##arc.defendantid,
arcEventID,
arcDate,
bailrequest = case when patindex('%[0-9]%', coalesce(e2.bailrequest, e.bailrequest))=0 then null
				else replace(ltrim(rtrim(coalesce(e2.bailrequest, e.bailrequest))), '  ', '') end,
cash = cast(NULL as varchar(1000)),
bail1 = cast(NULL as varchar(1000)),
bail2 = cast(NULL as varchar(1000))
INTO ##bail
from ##arc
join evt e on e.eventid = ##arc.arcEventID
JOIN evt e2 ON e2.eventID = e.bailrequesteventID


update ##bail
set bailrequest = replace(bailrequest, '.00', '')


update ##bail
set cash = 1
where bailrequest = 'One Dollar'

update ##bail
set cash = 1000000
where bailrequest like 'one million%'


update ##bail
set cash = 'None'
where bailrequest like 'N/A%'

update ##bail
set cash = replace(bailrequest, '$', '')
where patindex('%[^0-9$]%', bailrequest)=0

delete from ##bail where bailrequest is null

