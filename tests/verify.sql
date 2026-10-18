USE nexuspay;
DELIMITER $$
CREATE PROCEDURE verify_nexuspay()
BEGIN
 DECLARE failed BOOLEAN DEFAULT FALSE;
 DECLARE before_total DECIMAL(15,2);
 DECLARE after_total DECIMAL(15,2);
 DECLARE before_source DECIMAL(15,2);
 DECLARE before_count INT;
 DECLARE before_destination DECIMAL(15,2);
 DECLARE before_notifications INT;
 SELECT SUM(balance) INTO before_total FROM bank_accounts;
 SELECT balance INTO before_source FROM bank_accounts WHERE account_number='DEMO-C001';
 SELECT COUNT(*) INTO before_count FROM transactions;
 SELECT COUNT(*) INTO before_notifications FROM notifications;
 SELECT balance INTO before_destination FROM bank_accounts WHERE account_number='DEMO-M001';
 CALL pay_merchant('verification-success',1,1,'DEMO-C001','DEMO-M001',25);
 IF (SELECT balance FROM bank_accounts WHERE account_number='DEMO-C001') <> before_source-25 THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: debit'; END IF;
 SELECT SUM(balance) INTO after_total FROM bank_accounts;
 IF before_total <> after_total THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: conservation'; END IF;
 BEGIN
 DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=TRUE;
 CALL pay_merchant('verification-success',1,1,'DEMO-C001','DEMO-M001',25);
 END;
 IF NOT failed THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: duplicate accepted'; END IF;
 SET failed=FALSE;
 BEGIN
 DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=TRUE;
 CALL pay_merchant('verification-poor',1,1,'DEMO-C001','DEMO-M001',99999999);
 END;
 IF NOT failed THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: overdraft accepted'; END IF;
 SET failed=FALSE;
 BEGIN
 DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=TRUE;
 CALL pay_merchant('verification-owner',2,1,'DEMO-C001','DEMO-M001',10);
 END;
 IF NOT failed THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: ownership accepted'; END IF;
 SET failed=FALSE;
 BEGIN
 DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=TRUE;
 INSERT INTO scheduled_payments(customer_id,beneficiary_id,amount,frequency,start_date,next_due_date)
 VALUES(2,1,100,'MONTHLY','2026-01-01','2026-02-01');
 END;
 IF NOT failed THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: beneficiary ownership'; END IF;
 IF (SELECT balance FROM bank_accounts WHERE account_number='DEMO-M001') <> before_destination+25
 OR (SELECT COUNT(*) FROM notifications) <> before_notifications+1 THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: credit or notification'; END IF;
 IF (SELECT COUNT(*) FROM transactions) <> before_count+1
 OR (SELECT balance FROM bank_accounts WHERE account_number='DEMO-C001') <> before_source-25
 OR (SELECT SUM(balance) FROM bank_accounts) <> before_total THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: rollback integrity'; END IF;
 IF EXISTS(SELECT 1 FROM split_expenses e JOIN expense_shares s ON s.split_id=e.split_id
 GROUP BY e.split_id,e.total_amount HAVING SUM(s.share_amount)<>e.total_amount) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='FAIL: split allocation'; END IF;
 SELECT 'PASS: debit, conservation, duplicate protection, overdraft, ownership, beneficiary and rollback checks' AS result;
END$$
DELIMITER ;
-- Run on a freshly seeded demo. Adds one INR 25 payment; rebuild before rerunning.
CALL verify_nexuspay();
DROP PROCEDURE verify_nexuspay;
