-- =====================================================================
-- HOSPITAL MANAGEMENT DATABASE  (MySQL 8.x)
-- Sections: 1) DDL  2) Triggers & Procedure  3) DML (sample data)
--           4) DML (modify / delete)  5) Queries  6) Views
-- =====================================================================

DROP DATABASE IF EXISTS hospital_db;
CREATE DATABASE hospital_db;
USE hospital_db;

-- =====================================================================
-- 1. DDL
-- =====================================================================

CREATE TABLE department (
    dept_id    INT AUTO_INCREMENT PRIMARY KEY,
    dept_name  VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE doctor (
    doctor_id        INT AUTO_INCREMENT PRIMARY KEY,
    doc_name         VARCHAR(80) NOT NULL,
    specialization   VARCHAR(60) NOT NULL,
    phone            VARCHAR(15) NOT NULL UNIQUE,
    email            VARCHAR(80),
    consultation_fee DECIMAL(10,2) NOT NULL CHECK (consultation_fee >= 0),
    dept_id          INT NOT NULL,
    FOREIGN KEY (dept_id) REFERENCES department(dept_id)
);

-- Availability of doctors (one row per working day)
CREATE TABLE doctor_schedule (
    schedule_id  INT AUTO_INCREMENT PRIMARY KEY,
    doctor_id    INT NOT NULL,
    day_of_week  ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') NOT NULL,
    start_time   TIME NOT NULL,
    end_time     TIME NOT NULL,
    CHECK (end_time > start_time),
    UNIQUE (doctor_id, day_of_week),
    FOREIGN KEY (doctor_id) REFERENCES doctor(doctor_id) ON DELETE CASCADE
);

CREATE TABLE patient (
    patient_id    INT AUTO_INCREMENT PRIMARY KEY,
    first_name    VARCHAR(40) NOT NULL,
    last_name     VARCHAR(40),
    gender        ENUM('M','F','O') NOT NULL,
    dob           DATE NOT NULL,
    phone         VARCHAR(15) NOT NULL,
    address       VARCHAR(150),
    blood_group   VARCHAR(5),
    patient_type  ENUM('OUT','IN') NOT NULL DEFAULT 'OUT',
    registered_on DATE NOT NULL DEFAULT (CURRENT_DATE)
);

-- Room categories: general, semi-private, private, ICU, operation theatre
CREATE TABLE room_category (
    category_id    INT AUTO_INCREMENT PRIMARY KEY,
    category_name  VARCHAR(40) NOT NULL UNIQUE,
    category_type  ENUM('ROOM','ICU','OT') NOT NULL,
    charge         DECIMAL(10,2) NOT NULL CHECK (charge >= 0)   -- per day (ROOM/ICU) or per use (OT)
);

CREATE TABLE room (
    room_id      INT AUTO_INCREMENT PRIMARY KEY,
    room_no      VARCHAR(10) NOT NULL UNIQUE,
    category_id  INT NOT NULL,
    status       ENUM('Available','Occupied','Maintenance') NOT NULL DEFAULT 'Available',
    FOREIGN KEY (category_id) REFERENCES room_category(category_id)
);

CREATE TABLE admission (
    admission_id    INT AUTO_INCREMENT PRIMARY KEY,
    patient_id      INT NOT NULL,
    doctor_id       INT NOT NULL,
    room_id         INT NOT NULL,
    admit_date      DATE NOT NULL,
    discharge_date  DATE NULL,
    reason          VARCHAR(200),
    CHECK (discharge_date IS NULL OR discharge_date >= admit_date),
    FOREIGN KEY (patient_id) REFERENCES patient(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES doctor(doctor_id),
    FOREIGN KEY (room_id)    REFERENCES room(room_id)
);

CREATE TABLE appointment (
    appointment_id  INT AUTO_INCREMENT PRIMARY KEY,
    patient_id      INT NOT NULL,
    doctor_id       INT NOT NULL,
    appt_date       DATE NOT NULL,
    appt_time       TIME NOT NULL,
    status          ENUM('Booked','Completed','Cancelled') NOT NULL DEFAULT 'Booked',
    UNIQUE (doctor_id, appt_date, appt_time),         -- prevents double booking
    FOREIGN KEY (patient_id) REFERENCES patient(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES doctor(doctor_id)
);

CREATE TABLE diagnostic_test (
    test_id    INT AUTO_INCREMENT PRIMARY KEY,
    test_name  VARCHAR(80) NOT NULL UNIQUE,
    charge     DECIMAL(10,2) NOT NULL CHECK (charge >= 0)
);

CREATE TABLE bill (
    bill_id       INT AUTO_INCREMENT PRIMARY KEY,
    patient_id    INT NOT NULL,
    admission_id  INT NULL,                        -- NULL for out-patient bills
    bill_date     DATE NOT NULL,
    total_amount  DECIMAL(12,2) NOT NULL DEFAULT 0,
    paid_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
    status        ENUM('Unpaid','Partial','Paid') NOT NULL DEFAULT 'Unpaid',
    FOREIGN KEY (patient_id)   REFERENCES patient(patient_id),
    FOREIGN KEY (admission_id) REFERENCES admission(admission_id)
);

CREATE TABLE bill_item (
    item_id      INT AUTO_INCREMENT PRIMARY KEY,
    bill_id      INT NOT NULL,
    item_type    ENUM('CONSULTATION','TREATMENT','TEST','ROOM','OT') NOT NULL,
    description  VARCHAR(200) NOT NULL,
    amount       DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
    FOREIGN KEY (bill_id) REFERENCES bill(bill_id) ON DELETE CASCADE
);

CREATE TABLE treatment (
    treatment_id    INT AUTO_INCREMENT PRIMARY KEY,
    patient_id      INT NOT NULL,
    doctor_id       INT NOT NULL,
    admission_id    INT NULL,
    diagnosis       VARCHAR(150) NOT NULL,
    treatment_desc  VARCHAR(250),
    treatment_date  DATE NOT NULL,
    charge          DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (charge >= 0),
    bill_id         INT NULL,                      -- set once the item has been billed
    FOREIGN KEY (patient_id)   REFERENCES patient(patient_id),
    FOREIGN KEY (doctor_id)    REFERENCES doctor(doctor_id),
    FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    FOREIGN KEY (bill_id)      REFERENCES bill(bill_id)
);

CREATE TABLE patient_test (
    pt_id         INT AUTO_INCREMENT PRIMARY KEY,
    patient_id    INT NOT NULL,
    test_id       INT NOT NULL,
    doctor_id     INT NOT NULL,                    -- referring doctor
    admission_id  INT NULL,
    test_date     DATE NOT NULL,
    result        VARCHAR(250),
    charge        DECIMAL(10,2) NOT NULL CHECK (charge >= 0),   -- charge at time of test
    bill_id       INT NULL,
    FOREIGN KEY (patient_id)   REFERENCES patient(patient_id),
    FOREIGN KEY (test_id)      REFERENCES diagnostic_test(test_id),
    FOREIGN KEY (doctor_id)    REFERENCES doctor(doctor_id),
    FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    FOREIGN KEY (bill_id)      REFERENCES bill(bill_id)
);

CREATE TABLE ot_usage (
    ot_usage_id   INT AUTO_INCREMENT PRIMARY KEY,
    admission_id  INT NOT NULL,
    room_id       INT NOT NULL,                    -- the OT used
    doctor_id     INT NOT NULL,                    -- surgeon
    surgery_name  VARCHAR(100) NOT NULL,
    surgery_date  DATE NOT NULL,
    ot_charge     DECIMAL(10,2) NOT NULL CHECK (ot_charge >= 0),
    bill_id       INT NULL,
    FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    FOREIGN KEY (room_id)      REFERENCES room(room_id),
    FOREIGN KEY (doctor_id)    REFERENCES doctor(doctor_id),
    FOREIGN KEY (bill_id)      REFERENCES bill(bill_id)
);

CREATE INDEX idx_doctor_spec   ON doctor(specialization);
CREATE INDEX idx_appt_date     ON appointment(appt_date);
CREATE INDEX idx_patient_name  ON patient(first_name, last_name);

-- =====================================================================
-- 2. TRIGGERS & STORED PROCEDURE
-- =====================================================================
DELIMITER $$

-- Mark room occupied and patient as in-patient on admission
CREATE TRIGGER trg_admission_insert
AFTER INSERT ON admission
FOR EACH ROW
BEGIN
    UPDATE room    SET status = 'Occupied' WHERE room_id = NEW.room_id;
    UPDATE patient SET patient_type = 'IN' WHERE patient_id = NEW.patient_id;
END$$

-- Free the room when the patient is discharged
CREATE TRIGGER trg_admission_discharge
AFTER UPDATE ON admission
FOR EACH ROW
BEGIN
    IF OLD.discharge_date IS NULL AND NEW.discharge_date IS NOT NULL THEN
        UPDATE room    SET status = 'Available' WHERE room_id = NEW.room_id;
        UPDATE patient SET patient_type = 'OUT' WHERE patient_id = NEW.patient_id;
    END IF;
END$$

-- Generate a bill for a patient.
-- p_admission = admission id for an in-patient bill, NULL for an out-patient bill.
CREATE PROCEDURE generate_bill(IN p_patient INT, IN p_admission INT)
BEGIN
    DECLARE v_bill INT;
    DECLARE v_days INT;
    DECLARE v_rate DECIMAL(10,2);
    DECLARE v_room_cat VARCHAR(40);

    INSERT INTO bill(patient_id, admission_id, bill_date)
    VALUES (p_patient, p_admission, CURDATE());
    SET v_bill = LAST_INSERT_ID();

    -- Consultation fees for completed appointments (out-patient bills only)
    IF p_admission IS NULL THEN
        INSERT INTO bill_item(bill_id, item_type, description, amount)
        SELECT v_bill, 'CONSULTATION',
               CONCAT('Consultation - Dr. ', d.doc_name, ' on ', a.appt_date),
               d.consultation_fee
        FROM appointment a JOIN doctor d ON d.doctor_id = a.doctor_id
        WHERE a.patient_id = p_patient AND a.status = 'Completed'
          AND NOT EXISTS (SELECT 1 FROM bill_item bi
                          WHERE bi.bill_id IN (SELECT bill_id FROM bill WHERE patient_id = p_patient AND bill_id <> v_bill)
                            AND bi.description = CONCAT('Consultation - Dr. ', d.doc_name, ' on ', a.appt_date));
    END IF;

    -- Treatments not yet billed
    INSERT INTO bill_item(bill_id, item_type, description, amount)
    SELECT v_bill, 'TREATMENT', CONCAT(diagnosis, ' - ', IFNULL(treatment_desc,'')), charge
    FROM treatment
    WHERE patient_id = p_patient AND bill_id IS NULL AND admission_id <=> p_admission;
    UPDATE treatment SET bill_id = v_bill
    WHERE patient_id = p_patient AND bill_id IS NULL AND admission_id <=> p_admission;

    -- Diagnostic tests not yet billed
    INSERT INTO bill_item(bill_id, item_type, description, amount)
    SELECT v_bill, 'TEST', t.test_name, pt.charge
    FROM patient_test pt JOIN diagnostic_test t ON t.test_id = pt.test_id
    WHERE pt.patient_id = p_patient AND pt.bill_id IS NULL AND pt.admission_id <=> p_admission;
    UPDATE patient_test SET bill_id = v_bill
    WHERE patient_id = p_patient AND bill_id IS NULL AND admission_id <=> p_admission;

    -- Room / ICU charges and OT charges (in-patient only)
    IF p_admission IS NOT NULL THEN
        SELECT GREATEST(DATEDIFF(IFNULL(a.discharge_date, CURDATE()), a.admit_date), 1),
               rc.charge, rc.category_name
          INTO v_days, v_rate, v_room_cat
        FROM admission a
        JOIN room r           ON r.room_id = a.room_id
        JOIN room_category rc ON rc.category_id = r.category_id
        WHERE a.admission_id = p_admission;

        INSERT INTO bill_item(bill_id, item_type, description, amount)
        VALUES (v_bill, 'ROOM', CONCAT(v_room_cat, ' for ', v_days, ' day(s)'), v_days * v_rate);

        INSERT INTO bill_item(bill_id, item_type, description, amount)
        SELECT v_bill, 'OT', o.surgery_name, o.ot_charge
        FROM ot_usage o WHERE o.admission_id = p_admission AND o.bill_id IS NULL;
        UPDATE ot_usage SET bill_id = v_bill WHERE admission_id = p_admission AND bill_id IS NULL;
    END IF;

    UPDATE bill
    SET total_amount = (SELECT IFNULL(SUM(amount),0) FROM bill_item WHERE bill_id = v_bill)
    WHERE bill_id = v_bill;

    SELECT v_bill AS new_bill_id;
END$$

-- Record a payment against a bill and update its status
CREATE PROCEDURE pay_bill(IN p_bill INT, IN p_amount DECIMAL(12,2))
BEGIN
    UPDATE bill
    SET paid_amount = paid_amount + p_amount,
        status = CASE WHEN paid_amount + p_amount >= total_amount THEN 'Paid'
                      WHEN paid_amount + p_amount > 0            THEN 'Partial'
                      ELSE 'Unpaid' END
    WHERE bill_id = p_bill;
END$$

DELIMITER ;

-- =====================================================================
-- 3. DML  -  INSERT SAMPLE DATA
-- =====================================================================

INSERT INTO department(dept_name) VALUES
('Cardiology'),('Orthopedics'),('Neurology'),('Pediatrics'),('General Medicine');

INSERT INTO doctor(doc_name, specialization, phone, email, consultation_fee, dept_id) VALUES
('Anil Sharma', 'Cardiologist',       '9810000001', 'anil@hosp.com',   800, 1),
('Meera Iyer',  'Orthopedic Surgeon', '9810000002', 'meera@hosp.com',  700, 2),
('Rajesh Gupta','Neurologist',        '9810000003', 'rajesh@hosp.com', 900, 3),
('Sunita Rao',  'Pediatrician',       '9810000004', 'sunita@hosp.com', 500, 4),
('Vikram Singh','General Physician',  '9810000005', 'vikram@hosp.com', 400, 5);

INSERT INTO doctor_schedule(doctor_id, day_of_week, start_time, end_time) VALUES
(1,'Monday','09:00','13:00'),(1,'Wednesday','09:00','13:00'),(1,'Friday','14:00','18:00'),
(2,'Tuesday','10:00','14:00'),(2,'Thursday','10:00','14:00'),
(3,'Monday','11:00','15:00'),(3,'Saturday','09:00','12:00'),
(4,'Monday','09:00','12:00'),(4,'Tuesday','09:00','12:00'),(4,'Wednesday','09:00','12:00'),
(5,'Monday','08:00','16:00'),(5,'Tuesday','08:00','16:00'),(5,'Wednesday','08:00','16:00'),
(5,'Thursday','08:00','16:00'),(5,'Friday','08:00','16:00');

INSERT INTO patient(first_name,last_name,gender,dob,phone,address,blood_group,patient_type,registered_on) VALUES
('Rohan', 'Verma',  'M','1990-05-14','9900000001','Sector 15, Faridabad','B+', 'OUT','2026-10-01'),
('Priya', 'Nair',   'F','1985-09-30','9900000002','NIT, Faridabad',       'O+', 'OUT','2026-10-05'),
('Aarav', 'Mehta',  'M','2018-02-11','9900000003','Ballabgarh',           'A+', 'OUT','2026-10-20'),
('Sanjay','Kumar',  'M','1972-12-01','9900000004','Sector 21, Faridabad', 'AB+','OUT','2026-11-01'),
('Kavita','Joshi',  'F','1968-07-22','9900000005','Greater Faridabad',    'O-', 'OUT','2026-11-05');

INSERT INTO room_category(category_name, category_type, charge) VALUES
('General Ward',  'ROOM', 1500),
('Semi-Private',  'ROOM', 3000),
('Private',       'ROOM', 5000),
('ICU',           'ICU', 12000),
('Operation Theatre','OT',25000);

INSERT INTO room(room_no, category_id) VALUES
('G-101',1),('G-102',1),('S-201',2),('P-301',3),('P-302',3),('ICU-1',4),('ICU-2',4),('OT-1',5);

INSERT INTO diagnostic_test(test_name, charge) VALUES
('Complete Blood Count', 350),('X-Ray Chest', 600),('ECG', 500),
('MRI Brain', 7500),('CT Scan Abdomen', 5500),('Lipid Profile', 900);

-- Appointments
INSERT INTO appointment(patient_id, doctor_id, appt_date, appt_time, status) VALUES
(1, 1, '2026-11-16', '09:30', 'Completed'),
(2, 5, '2026-11-17', '10:00', 'Booked'),
(3, 4, '2026-11-18', '09:15', 'Booked'),
(1, 5, '2026-11-17', '11:00', 'Booked');

-- Admissions (triggers will mark rooms Occupied and patients IN)
INSERT INTO admission(patient_id, doctor_id, room_id, admit_date, reason) VALUES
(4, 1, 1, '2026-11-10', 'Chest pain - suspected cardiac event'),
(5, 2, 4, '2026-11-15', 'Fracture - right femur');

-- Treatments
INSERT INTO treatment(patient_id, doctor_id, admission_id, diagnosis, treatment_desc, treatment_date, charge) VALUES
(1, 1, NULL, 'Hypertension',   'Medication and diet plan', '2026-11-16', 300),
(4, 1, 1,    'Angina',         'Angioplasty follow-up care and medication', '2026-11-11', 15000),
(5, 2, 2,    'Femur fracture', 'Plaster and pain management', '2026-11-15', 4000);

-- Diagnostic tests
INSERT INTO patient_test(patient_id, test_id, doctor_id, admission_id, test_date, result, charge) VALUES
(1, 3, 1, NULL, '2026-11-16', 'Normal sinus rhythm', 500),
(4, 3, 1, 1,    '2026-11-10', 'ST changes noted', 500),
(4, 6, 1, 1,    '2026-11-10', 'LDL high', 900),
(5, 2, 2, 2,    '2026-11-15', 'Fracture confirmed', 600);

-- Operation theatre usage
INSERT INTO ot_usage(admission_id, room_id, doctor_id, surgery_name, surgery_date, ot_charge) VALUES
(1, 8, 1, 'Coronary Angioplasty', '2026-11-11', 25000),
(2, 8, 2, 'Femur Fixation',       '2026-11-16', 25000);

-- Discharge patient 4 (trigger frees room G-101)
UPDATE admission SET discharge_date = '2026-11-15' WHERE admission_id = 1;

-- Generate bills (in-patient and out-patient)
CALL generate_bill(4, 1);      -- in-patient bill for Sanjay Kumar
CALL generate_bill(1, NULL);   -- out-patient bill for Rohan Verma
CALL pay_bill(1, 20000);       -- partial payment on bill 1

-- =====================================================================
-- 4. DML  -  MODIFY / DELETE
-- =====================================================================

-- Modify patient contact details
UPDATE patient SET phone = '9911223344', address = 'Sector 37, Faridabad' WHERE patient_id = 2;

-- Modify doctor consultation fee
UPDATE doctor SET consultation_fee = 1000 WHERE doctor_id = 1;

-- Modify diagnostic test charge
UPDATE diagnostic_test SET charge = 8000 WHERE test_name = 'MRI Brain';

-- Modify room category charge
UPDATE room_category SET charge = 5500 WHERE category_name = 'Private';

-- Modify treatment details
UPDATE treatment SET charge = 350, treatment_desc = 'Medication, diet plan and BP monitoring'
WHERE treatment_id = 1 AND bill_id IS NULL;

-- Reschedule / cancel an appointment
UPDATE appointment SET appt_time = '10:30' WHERE appointment_id = 2;
UPDATE appointment SET status = 'Cancelled' WHERE appointment_id = 4;

-- Delete a cancelled appointment
DELETE FROM appointment WHERE status = 'Cancelled';

-- Delete a doctor's schedule row
DELETE FROM doctor_schedule WHERE doctor_id = 3 AND day_of_week = 'Saturday';

-- Delete an unbilled test record (billed rows are protected by the bill_id check)
DELETE FROM patient_test WHERE pt_id = 1 AND bill_id IS NULL;

-- Deleting a patient / doctor who has records fails due to foreign keys (data integrity).
-- Example, works only for a patient with no history:
-- DELETE FROM patient WHERE patient_id = 3;

-- =====================================================================
-- 5. QUERIES
-- =====================================================================

-- ---- 5.1 VIEW details -------------------------------------------------

-- All patients
SELECT patient_id, CONCAT(first_name,' ',last_name) AS name, gender,
       TIMESTAMPDIFF(YEAR, dob, CURDATE()) AS age, phone, blood_group, patient_type
FROM patient;

-- Out-patients / in-patients only
SELECT * FROM patient WHERE patient_type = 'OUT';
SELECT * FROM patient WHERE patient_type = 'IN';

-- Doctor details with department
SELECT d.doctor_id, d.doc_name, d.specialization, dp.dept_name, d.consultation_fee, d.phone
FROM doctor d JOIN department dp ON dp.dept_id = d.dept_id;

-- Treatment details of a patient
SELECT CONCAT(p.first_name,' ',p.last_name) AS patient, d.doc_name AS doctor,
       t.diagnosis, t.treatment_desc, t.treatment_date, t.charge
FROM treatment t
JOIN patient p ON p.patient_id = t.patient_id
JOIN doctor  d ON d.doctor_id  = t.doctor_id
WHERE p.patient_id = 4;

-- Currently admitted patients with room and doctor
SELECT a.admission_id, CONCAT(p.first_name,' ',p.last_name) AS patient,
       r.room_no, rc.category_name, d.doc_name, a.admit_date
FROM admission a
JOIN patient p        ON p.patient_id = a.patient_id
JOIN room r           ON r.room_id = a.room_id
JOIN room_category rc ON rc.category_id = r.category_id
JOIN doctor d         ON d.doctor_id = a.doctor_id
WHERE a.discharge_date IS NULL;

-- Tests taken by a patient
SELECT t.test_name, pt.test_date, pt.result, pt.charge
FROM patient_test pt JOIN diagnostic_test t ON t.test_id = pt.test_id
WHERE pt.patient_id = 4;

-- ---- 5.2 SEARCH facilities ------------------------------------------

-- Doctors by specialisation
SELECT doc_name, specialization, consultation_fee, phone
FROM doctor WHERE specialization LIKE '%cardio%';

-- Doctors available on a given weekday (Monday)
SELECT d.doc_name, d.specialization, s.start_time, s.end_time
FROM doctor d JOIN doctor_schedule s ON s.doctor_id = d.doctor_id
WHERE s.day_of_week = 'Monday';

-- Doctors available on a specific date AND still having a particular slot free
SELECT d.doc_name, d.specialization
FROM doctor d
JOIN doctor_schedule s ON s.doctor_id = d.doctor_id
WHERE s.day_of_week = DAYNAME('2026-11-23')
  AND '10:00' BETWEEN s.start_time AND s.end_time
  AND NOT EXISTS (SELECT 1 FROM appointment a
                  WHERE a.doctor_id = d.doctor_id AND a.appt_date = '2026-11-23'
                    AND a.appt_time = '10:00' AND a.status <> 'Cancelled');

-- Charges of diagnostic tests (search by name, sorted by price)
SELECT test_name, charge FROM diagnostic_test
WHERE test_name LIKE '%scan%' OR test_name LIKE '%MRI%'
ORDER BY charge;

-- Charges for OT, ICU and all room categories
SELECT category_name, category_type, charge,
       CASE category_type WHEN 'OT' THEN 'per use' ELSE 'per day' END AS unit
FROM room_category ORDER BY charge;

-- Available rooms by category
SELECT rc.category_name, r.room_no
FROM room r JOIN room_category rc ON rc.category_id = r.category_id
WHERE r.status = 'Available' ORDER BY rc.category_name;

-- Count of available rooms per category
SELECT rc.category_name, COUNT(*) AS available_rooms
FROM room r JOIN room_category rc ON rc.category_id = r.category_id
WHERE r.status = 'Available' GROUP BY rc.category_name;

-- ---- 5.3 APPOINTMENTS -------------------------------------------------

-- Book an appointment (fails with duplicate-key error if the slot is taken)
INSERT INTO appointment(patient_id, doctor_id, appt_date, appt_time)
VALUES (2, 3, '2026-11-23', '11:30');

-- Appointments of a doctor on a date
SELECT a.appt_time, CONCAT(p.first_name,' ',p.last_name) AS patient, a.status
FROM appointment a JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 5 AND a.appt_date = '2026-11-17'
ORDER BY a.appt_time;

-- Upcoming appointments of a patient
SELECT a.appt_date, a.appt_time, d.doc_name, d.specialization
FROM appointment a JOIN doctor d ON d.doctor_id = a.doctor_id
WHERE a.patient_id = 2 AND a.appt_date >= CURDATE() AND a.status = 'Booked';

-- ---- 5.4 BILLS ------------------------------------------------------------

-- View a bill with its patient details and line items
SELECT b.bill_id, CONCAT(p.first_name,' ',p.last_name) AS patient, b.bill_date,
       bi.item_type, bi.description, bi.amount
FROM bill b
JOIN patient p    ON p.patient_id = b.patient_id
JOIN bill_item bi ON bi.bill_id = b.bill_id
WHERE b.bill_id = 1;

-- Bill summary: total, paid, balance
SELECT b.bill_id, CONCAT(p.first_name,' ',p.last_name) AS patient,
       b.total_amount, b.paid_amount, (b.total_amount - b.paid_amount) AS balance, b.status
FROM bill b JOIN patient p ON p.patient_id = b.patient_id;

-- Pending (unpaid / partially paid) bills
SELECT * FROM bill WHERE status <> 'Paid';

-- Bill total broken down by item type
SELECT item_type, SUM(amount) AS total
FROM bill_item WHERE bill_id = 1 GROUP BY item_type;

-- ---- 5.5 REPORTS / ANALYTICS ---------------------------------------------

-- Number of patients per doctor (from appointments)
SELECT d.doc_name, COUNT(DISTINCT a.patient_id) AS patients
FROM doctor d LEFT JOIN appointment a ON a.doctor_id = d.doctor_id
GROUP BY d.doc_name;

-- Revenue per department (treatment charges)
SELECT dp.dept_name, SUM(t.charge) AS revenue
FROM treatment t
JOIN doctor d ON d.doctor_id = t.doctor_id
JOIN department dp ON dp.dept_id = d.dept_id
GROUP BY dp.dept_name ORDER BY revenue DESC;

-- Total hospital revenue collected
SELECT SUM(paid_amount) AS collected, SUM(total_amount - paid_amount) AS outstanding FROM bill;

-- Most frequently ordered diagnostic tests
SELECT t.test_name, COUNT(*) AS times_ordered
FROM patient_test pt JOIN diagnostic_test t ON t.test_id = pt.test_id
GROUP BY t.test_name ORDER BY times_ordered DESC;

-- Average length of stay of discharged in-patients
SELECT AVG(DATEDIFF(discharge_date, admit_date)) AS avg_days
FROM admission WHERE discharge_date IS NOT NULL;

-- =====================================================================
-- 6. VIEWS
-- =====================================================================

CREATE VIEW v_doctor_availability AS
SELECT d.doctor_id, d.doc_name, d.specialization, d.consultation_fee,
       s.day_of_week, s.start_time, s.end_time
FROM doctor d JOIN doctor_schedule s ON s.doctor_id = d.doctor_id;

CREATE VIEW v_room_charges AS
SELECT rc.category_name, rc.category_type, rc.charge,
       COUNT(r.room_id) AS total_rooms,
       SUM(r.status = 'Available') AS available_rooms
FROM room_category rc LEFT JOIN room r ON r.category_id = rc.category_id
GROUP BY rc.category_id, rc.category_name, rc.category_type, rc.charge;

CREATE VIEW v_bill_summary AS
SELECT b.bill_id, CONCAT(p.first_name,' ',p.last_name) AS patient, b.bill_date,
       b.total_amount, b.paid_amount, (b.total_amount - b.paid_amount) AS balance, b.status
FROM bill b JOIN patient p ON p.patient_id = b.patient_id;

SELECT * FROM v_doctor_availability WHERE specialization LIKE '%General%';
SELECT * FROM v_room_charges;
SELECT * FROM v_bill_summary;
