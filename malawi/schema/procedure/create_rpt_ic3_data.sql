CREATE PROCEDURE create_rpt_ic3_data(IN _endDate DATE, IN _location VARCHAR(255)) BEGIN

	-- Get initial cohort to operate on (for convenience)
	DROP TABLE IF EXISTS rpt_ic3_patient_ids;
	CREATE TEMPORARY TABLE rpt_ic3_patient_ids AS
	SELECT DISTINCT(patient_id) 
							FROM mw_art_register 
							WHERE art_number IS NOT NULL
							
	UNION				

	SELECT DISTINCT(patient_id) 
							FROM mw_ncd_register 
							WHERE ncd_number IS NOT NULL
							
	UNION				

	SELECT DISTINCT(patient_id) 
							FROM mw_eid_register 
							WHERE eid_number IS NOT NULL;	

	CREATE INDEX patient_id_index ON rpt_ic3_patient_ids(patient_id);
							
	-- Create lookup (row-per-patient) table to calculate ic3 indicators
	DROP TABLE IF EXISTS rpt_ic3_data_table;
	CREATE TABLE rpt_ic3_data_table AS
	-- Define columns
	SELECT 			ic3.patient_id, 
					birthdate,
					htnDx,				
					dmDx,
					cvDisease,
					asthmaDx,
					epilepsyDx,
					artStartDate, 
					artStartLocation, 
					ncdStartDate, 
					ncdStartLocation,
					eidStartDate, 
					eidStartLocation,
					hivCurrentStateStart,
					currentHivState,				
					hivCurrentLocation,
					ncdCurrentStateStart,
					currentNcdState,				
					ncdCurrentLocation,
					artVisits.lastArtVisit,
					ncdVisits.lastNcdVisit,
					lastMentalHealthVisitDate,
					lastAsthmaVisitDate,
					CASE 
						WHEN artVisits.lastArtVisit IS NULL THEN ncdVisits.lastNcdVisit
						WHEN ncdVisits.lastNcdVisit IS NULL THEN artVisits.lastArtVisit
						WHEN artVisits.lastArtVisit > ncdVisits.lastNcdVisit THEN artVisits.lastArtVisit
						ELSE ncdVisits.lastNcdVisit
					END AS lastIc3Visit,
					nextHtnDmAppt,
					nextAsthmaAppt,
					nextEpilepsyAppt,
					mentalHealthVisit.nextMentalHealthAppt,
					mentalHospitalizedSinceLastVisit,
					mentalHealthRxSideEffectsAtLastVisit,
					mentalStableAtLastVisit,
					artVisits.nextArtAppt,
					CASE WHEN	GREATEST(IFNULL(nextHtnDmAppt,"01-01-1500"), 
										IFNULL(nextAsthmaAppt,"01-01-1500"), 
										IFNULL(nextEpilepsyAppt,"01-01-1500"),
										IFNULL(nextMentalHealthAppt,"01-01-1500"),
										IFNULL(nextArtAppt,"01-01-1500")) <> "01-01-1500"
						THEN  GREATEST(IFNULL(nextHtnDmAppt,"01-01-1500"), 
										IFNULL(nextAsthmaAppt,"01-01-1500"), 
										IFNULL(nextEpilepsyAppt,"01-01-1500"),
										IFNULL(nextMentalHealthAppt,"01-01-1500"),
										IFNULL(nextArtAppt,"01-01-1500")) 
					END AS latestAppt,
					viralLoad.lastViralLoadTest,
					artRegimen.lastArtRegimen,
					motherArtNumber,
					motherEnrollmentHivStatus,
					dnaPcr.lastDnaPcrTest,
					rapid.lastRapidTest,
					systolicBpAtLastVisit,
					diastolicBpAtLastVisit,
					visualAcuityAtLastVisit,
					cvRiskAtLastVisit,
					htnDmHospitalizedSinceLastVisit,
					lastProteinuria,
					lastCreatinine,
					lastFundoscopy,
					fingerStickAtLastVisit,
					hba1cAtLastVisit,
					seizuresSinceLastVisit,
					seizures,				
					asthmaClassificationAtLastVisit,
					ablePerformDailyActivitiesAtLastVisit,
					suicideRiskAtLastVisit
	FROM 			rpt_ic3_patient_ids ic3
	LEFT JOIN 		(SELECT patient_id,
					birthdate
					FROM omrs_patient
					) pdetails
					ON pdetails.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT * FROM		
						(SELECT patient_id, start_date AS artStartDate, location AS artStartLocation
						FROM omrs_program_state
						WHERE state = "On antiretrovirals"
						AND program = "HIV Program"
						AND (location = _location OR _location IS NULL)
						AND start_date <= _endDate
						ORDER BY artStartDate ASC) artStateInner 
					GROUP BY patient_id) artState
					ON artState.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT * FROM		
						(SELECT patient_id, start_date AS ncdStartDate, location AS ncdStartLocation
						FROM omrs_program_state
						WHERE state = "On treatment"
						AND program = "Chronic Care Program"
						AND (location = _location OR _location IS NULL)
						AND start_date <= _endDate
						ORDER BY ncdStartDate ASC) ncdStateInner 
					GROUP BY patient_id) ncdState
					ON ncdState.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT * FROM		
						(SELECT patient_id, start_date AS eidStartDate, location AS eidStartLocation
						FROM omrs_program_state
						WHERE state = "Exposed Child (Continue)"
						AND program = "HIV Program"
						AND (location = _location OR _location IS NULL)
						AND start_date <= _endDate
						ORDER BY eidStartDate ASC) eidStateInner 
					GROUP BY patient_id) eidState
					ON eidState.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT * FROM		
						(SELECT patient_id, 
						state as currentHivState, 
						start_date AS hivCurrentStateStart, 
						location AS hivCurrentLocation
						FROM omrs_program_state
						JOIN (SELECT program_enrollment_id, enrollment_date, completion_date, program 
							 FROM omrs_program_enrollment) e 
						ON e.program_enrollment_id = omrs_program_state.program_enrollment_id
						WHERE e.program = "HIV Program"
						AND (location = _location OR _location IS NULL)
						AND start_date <= _endDate
						AND (end_date IS NULL or end_date > _endDate)					
						ORDER BY hivCurrentStateStart DESC, enrollment_date DESC, completion_date ASC) hivStateInner 
					GROUP BY patient_id) hivCurrentState
					ON hivCurrentState.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT * FROM		
						(SELECT patient_id, state as currentNcdState, 
						start_date AS ncdCurrentStateStart, 
						location AS ncdCurrentLocation
						FROM omrs_program_state
						JOIN (SELECT program_enrollment_id, enrollment_date, completion_date, program 
							 FROM omrs_program_enrollment) e 
						ON e.program_enrollment_id = omrs_program_state.program_enrollment_id
						WHERE e.program = "Chronic Care Program"
						AND (location = _location OR _location IS NULL)
						AND start_date <= _endDate
						AND (end_date IS NULL or end_date > _endDate)
						ORDER BY ncdCurrentStateStart DESC, enrollment_date DESC, completion_date ASC) ncdCurrentStateInner 
					GROUP BY patient_id) ncdCurrentState
					ON ncdCurrentState.patient_id = ic3.patient_id	
	LEFT JOIN		(SELECT * 
					FROM 	(SELECT patient_id, 
							visit_date as lastArtVisit,
							next_appointment_date as nextArtAppt
							FROM mw_art_visits
							-- WHERE (location = _location OR _location IS NULL)
							WHERE visit_date <= _endDate
							ORDER BY visit_date DESC
							) artVisitsInner
					GROUP BY patient_id	
					) artVisits	
					ON artVisits.patient_id = ic3.patient_id	
	LEFT JOIN		(SELECT * 
					FROM 	(SELECT patient_id, 
							visit_date as lastNcdVisit
							FROM mw_ncd_visits
							-- WHERE (location = _location OR _location IS NULL)
							WHERE visit_date <= _endDate
							ORDER BY visit_date DESC
							) ncdVisitsInner
					GROUP BY patient_id	
					) ncdVisits	
					ON ncdVisits.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT patient_id,
					CASE WHEN diagnosis IS NOT NULL THEN 'X' END AS asthmaDx 
					FROM mw_ncd_diagnoses
					WHERE diagnosis = "Asthma"
					AND diagnosis_date < _endDate
					GROUP BY patient_id
					) asthmaDx
					ON asthmaDx.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT patient_id,
					CASE WHEN diagnosis IS NOT NULL THEN 'X' END AS htnDx 
					FROM mw_ncd_diagnoses
					WHERE diagnosis = "Hypertension"
					AND diagnosis_date < _endDate
					GROUP BY patient_id
					) htnDx
					ON htnDx.patient_id = ic3.patient_id				
	LEFT JOIN 		(SELECT patient_id,
					CASE WHEN diagnosis IS NOT NULL THEN 'X' END AS dmDx 
					FROM mw_ncd_diagnoses
					WHERE diagnosis in ("Diabetes", "Type 1 diabetes", "Type 2 diabetes")
					AND diagnosis_date < _endDate
					GROUP BY patient_id
					) dmDx
					ON dmDx.patient_id = ic3.patient_id								
	LEFT JOIN 		(SELECT patient_id,
					CASE WHEN diagnosis IS NOT NULL THEN 'X' END AS epilepsyDx 
					FROM mw_ncd_diagnoses
					WHERE diagnosis = "Epilepsy"
					AND diagnosis_date < _endDate
					GROUP BY patient_id
					) epilepsyDx
					ON epilepsyDx.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT patient_id, 
					cv_disease as cvDisease
					FROM mw_ncd_register
					WHERE cv_disease = 1
					GROUP BY patient_id
					) cvDisease on cvDisease.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT * 
					FROM 	(SELECT patient_id,
							date_collected AS lastViralLoadTest
							FROM mw_lab_tests
							WHERE date_collected <= _endDate
							AND test_type = "Viral Load"
							ORDER BY date_collected DESC
							) viralLoadInner GROUP BY patient_id
					) viralLoad 
					ON viralLoad.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT patient_id, 
							art_drug_regimen as lastArtRegimen
							FROM mw_art_visits
							WHERE visit_date < _endDate
							AND art_drug_regimen IS NOT NULL
							ORDER BY visit_date DESC
							) artRegimenInner GROUP BY patient_id
					) artRegimen
					ON artRegimen.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT patient_id,
					mother_art_number as motherArtNumber
					FROM mw_eid_register
					GROUP BY patient_id) mwEid
					ON mwEid.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT * 
					FROM 	(SELECT patient_id,
							date_collected AS lastDnaPcrTest
							FROM mw_lab_tests
							WHERE date_collected <= _endDate
							AND test_type = "HIV DNA polymerase chain reaction"
							ORDER BY date_collected DESC
							) dnaPcrInner GROUP BY patient_id
					) dnaPcr 
					ON dnaPcr.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT * 
					FROM 	(SELECT patient_id,
							date_collected AS lastRapidTest
							FROM mw_lab_tests
							WHERE date_collected <= _endDate
							AND test_type = "HIV rapid test, qualitative"
							ORDER BY date_collected DESC
							) rapidInner GROUP BY patient_id
					) rapid 
					ON rapid.patient_id = ic3.patient_id					
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT patient_id,
							value_coded as motherEnrollmentHivStatus
							FROM omrs_obs
							WHERE concept = 'Mother HIV Status'
							AND obs_date < _endDate
							AND encounter_type = 'EXPOSED_CHILD_INITIAL'
							ORDER BY obs_date DESC
							) motherHivStatusInner GROUP BY patient_id
					) motherHivStatus
					ON motherHivStatus.patient_id = ic3.patient_id			
	LEFT JOIN 		(SELECT *
					FROM	(SELECT patient_id,
							hba1c as hba1cAtLastVisit,
							serum_glucose as fingerStickAtLastVisit,
							systolic_bp as systolicBpAtLastVisit,
							diastolic_bp as diastolicBpAtLastVisit,
							visual_acuity as visualAcuityAtLastVisit,
							cv_risk as cvRiskAtLastVisit,
							hospitalized_since_last_visit as htnDmHospitalizedSinceLastVisit,
							next_appointment_date AS nextHtnDmAppt						
							FROM mw_ncd_visits
							WHERE diabetes_htn_followup = 1
							AND visit_date < _endDate
							ORDER BY visit_date DESC
							) htnDmVisitInner GROUP BY patient_id 
					) htnDmVisit
					ON htnDmVisit.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT patient_id,
							proteinuria as lastProteinuria
							FROM mw_ncd_visits
							WHERE visit_date < _endDate
							ORDER BY visit_date DESC
					) proteinuriaInner GROUP BY patient_id
					) proteinuria
					ON proteinuria.patient_id = ic3.patient_id
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT patient_id,
							creatinine as lastCreatinine
							FROM mw_ncd_visits
							WHERE visit_date < _endDate
							ORDER BY visit_date DESC
					) creatinineInner GROUP BY patient_id
					) creatinine
					ON creatinine.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT patient_id,
							fundoscopy as lastFundoscopy
							FROM mw_ncd_visits
							WHERE visit_date < _endDate
							ORDER BY visit_date DESC
					) fundoscopyInner GROUP BY patient_id
					) fundoscopy
					ON fundoscopy.patient_id = ic3.patient_id
					
	LEFT JOIN		(SELECT * 
					FROM 	(SELECT patient_id,
							num_seizures as seizures,
							next_appointment_date AS nextEpilepsyAppt
							FROM mw_ncd_visits
							WHERE epilepsy_followup = 1
							AND visit_date < _endDate
							ORDER BY visit_date DESC					
							) epilepsyInner GROUP BY patient_id
					) epilepsyVisit ON epilepsyVisit.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT omrs_encounter.patient_id,
							omrs_encounter.encounter_id,
							CASE WHEN value_coded IS NOT NULL 
							THEN 'X' 
							ELSE NULL 
							END AS seizuresSinceLastVisit
							FROM omrs_encounter
							LEFT JOIN 	(SELECT encounter_id, value_coded
										FROM omrs_obs 
					   					WHERE concept = 'Seizure activity'
					   					AND value_coded = 'Seizure since last visit'
					   					) seizuresSinceLastVisit
					   		ON seizuresSinceLastVisit.encounter_id = omrs_encounter.encounter_id				   								   					   				
							WHERE encounter_type = 'EPILEPSY_FOLLOWUP'
							AND encounter_date < _endDate
							ORDER BY encounter_date DESC
							) epilepsyVisitInner1 GROUP BY patient_id) epilepsyVisit2
					ON epilepsyVisit2.patient_id = ic3.patient_id	
	LEFT JOIN 		(SELECT *
					FROM 	(SELECT omrs_encounter.patient_id,
							omrs_encounter.encounter_id,
							ablePerformDailyActivitiesAtLastVisit,
							suicideRiskAtLastVisit
							FROM omrs_encounter
							LEFT JOIN 	(SELECT encounter_id, value_coded as ablePerformDailyActivitiesAtLastVisit
										FROM omrs_obs 
					   					WHERE concept = 'Able to perform daily activities'
					   					) ablePerformDailyActivities
					   		ON ablePerformDailyActivities.encounter_id = omrs_encounter.encounter_id	
							LEFT JOIN 	(SELECT encounter_id, value_coded as suicideRiskAtLastVisit
										FROM omrs_obs 
					   					WHERE concept = 'Suicide risk'
					   					) suicideRisk
					   		ON suicideRisk.encounter_id = omrs_encounter.encounter_id
							WHERE encounter_type = 'MENTAL_HEALTH_FOLLOWUP'
							AND encounter_date < _endDate
							ORDER BY encounter_date DESC
							) mentalHealthVisitInner GROUP BY patient_id) mentalHealthVisit1
					ON mentalHealthVisit1.patient_id = ic3.patient_id											
	LEFT JOIN		(SELECT * 
					FROM 	(SELECT patient_id,
							visit_date as lastAsthmaVisitDate,
							asthma_classification as asthmaClassificationAtLastVisit,
							next_appointment_date AS nextAsthmaAppt
							FROM mw_ncd_visits
							WHERE asthma_followup = 1
							AND visit_date < _endDate
							ORDER BY visit_date DESC					
							) asthmaInner GROUP BY patient_id
					) asthmaVisit ON asthmaVisit.patient_id = ic3.patient_id	
	LEFT JOIN		(SELECT * 
					FROM 	(SELECT patient_id,
							visit_date AS lastMentalHealthVisitDate,
							hospitalized_since_last_visit as mentalHospitalizedSinceLastVisit,
							mental_health_drug_side_effect as mentalHealthRxSideEffectsAtLastVisit,
							mental_stable as mentalStableAtLastVisit,
							next_appointment_date AS nextMentalHealthAppt
							FROM mw_ncd_visits
							WHERE mental_health_followup = 1
							AND visit_date < _endDate
							ORDER BY visit_date DESC					
							) asthmaInner GROUP BY patient_id
					) mentalHealthVisit ON mentalHealthVisit.patient_id = ic3.patient_id																									
	;		


	DROP TABLE IF EXISTS rpt_ic3_patient_ids;

END	
