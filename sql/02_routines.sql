USE nexuspay;
SET time_zone = '+00:00';
DELIMITER $$

CREATE TRIGGER transactions_no_update BEFORE UPDATE ON transactions FOR EACH ROW
BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment records are immutable'; END$$
CREATE TRIGGER transactions_no_delete BEFORE DELETE ON transactions FOR EACH ROW
BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment records are immutable'; END$$
CREATE TRIGGER events_no_update BEFORE UPDATE ON transaction_events FOR EACH ROW
BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment events are append-only'; END$$
CREATE TRIGGER events_no_delete BEFORE DELETE ON transaction_events FOR EACH ROW
BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment events are append-only'; END$$
CREATE TRIGGER events_validate BEFORE INSERT ON transaction_events FOR EACH ROW
BEGIN
 DECLARE previous_status VARCHAR(20) DEFAULT NULL;
 SET previous_status=(SELECT status FROM transaction_events
  WHERE transaction_id=NEW.transaction_id ORDER BY event_id DESC LIMIT 1);
 IF NOT COALESCE(((previous_status IS NULL AND NEW.status='INITIATED') OR
  (previous_status='INITIATED' AND NEW.status IN ('AUTHORIZED','FAILED')) OR
  (previous_status='AUTHORIZED' AND NEW.status IN ('PENDING','FAILED')) OR
  (previous_status='PENDING' AND NEW.status IN ('SUCCESSFUL','FAILED'))),FALSE) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid transaction state transition';
 END IF;
END$$
CREATE TRIGGER transactions_initial_event AFTER INSERT ON transactions FOR EACH ROW
BEGIN INSERT INTO transaction_events(transaction_id,status) VALUES(NEW.transaction_id,'INITIATED'); END$$
CREATE TRIGGER source_identity_fixed BEFORE UPDATE ON funding_sources FOR EACH ROW
BEGIN
 IF NEW.user_id <> OLD.user_id OR NEW.source_type <> OLD.source_type
 OR NEW.account_reference <> OLD.account_reference THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Funding-source identity cannot be reassigned';
 END IF;
END$$
CREATE TRIGGER beneficiary_identity_fixed BEFORE UPDATE ON beneficiaries FOR EACH ROW
BEGIN
 IF NEW.customer_id <> OLD.customer_id OR NEW.destination_source <> OLD.destination_source THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Create a new beneficiary instead of changing its owner or destination';
 END IF;
END$$
CREATE TRIGGER customer_role BEFORE INSERT ON customers FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM users WHERE user_id=NEW.user_id AND role='CUSTOMER') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Customer profile requires a customer user'; END IF;
END$$
CREATE TRIGGER admin_role BEFORE INSERT ON admins FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM users WHERE user_id=NEW.user_id AND
  ((NEW.admin_scope='PLATFORM' AND role='ADMIN') OR (NEW.admin_scope='BANK' AND role='BANK_ADMIN'))) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Admin profile does not match the user role'; END IF;
END$$
CREATE TRIGGER merchant_role BEFORE INSERT ON merchants FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM users WHERE user_id=NEW.user_id AND role='MERCHANT') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Merchant profile requires a merchant user'; END IF;
 IF NEW.approved_by IS NOT NULL AND NOT EXISTS
 (SELECT 1 FROM admins WHERE admin_id=NEW.approved_by AND admin_scope='PLATFORM') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only a platform admin may approve merchants'; END IF;
END$$
CREATE TRIGGER merchant_approval BEFORE UPDATE ON merchants FOR EACH ROW
BEGIN
 IF NEW.user_id <> OLD.user_id THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Merchant identity cannot be reassigned'; END IF;
 IF NEW.approved_by IS NOT NULL AND NOT EXISTS
 (SELECT 1 FROM admins WHERE admin_id=NEW.approved_by AND admin_scope='PLATFORM') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only a platform admin may approve merchants'; END IF;
END$$
CREATE TRIGGER user_role_fixed BEFORE UPDATE ON users FOR EACH ROW
BEGIN
 IF NEW.role <> OLD.role THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='User role cannot change while using this schema'; END IF;
END$$
CREATE TRIGGER customer_identity_fixed BEFORE UPDATE ON customers FOR EACH ROW
BEGIN
 IF NEW.user_id <> OLD.user_id THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Customer identity cannot be reassigned'; END IF;
END$$
CREATE TRIGGER admin_identity_fixed BEFORE UPDATE ON admins FOR EACH ROW
BEGIN
 IF NEW.user_id <> OLD.user_id OR NEW.admin_scope <> OLD.admin_scope THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Admin identity and scope cannot change'; END IF;
END$$

-- Internal helper: caller owns the transaction and has validated the beneficiary.
-- Production application accounts must not be granted EXECUTE on this helper.
CREATE PROCEDURE post_transfer(
 IN p_request VARCHAR(64), IN p_source INT, IN p_destination INT,
 IN p_category VARCHAR(50), IN p_amount DECIMAL(15,2), IN p_refund BIGINT,
 IN p_schedule INT, IN p_due DATE, IN p_precheck_error VARCHAR(255),
 OUT p_transaction BIGINT, OUT p_status VARCHAR(20)
)
BEGIN
 DECLARE source_owner INT DEFAULT NULL;
 DECLARE destination_owner INT DEFAULT NULL;
 DECLARE source_kind VARCHAR(10);
 DECLARE destination_kind VARCHAR(10);
 DECLARE destination_role VARCHAR(20);
 DECLARE source_balance DECIMAL(15,2);
 DECLARE payment_cap DECIMAL(15,2) DEFAULT NULL;
 DECLARE daily_cap DECIMAL(15,2) DEFAULT NULL;
 DECLARE daily_spent DECIMAL(15,2) DEFAULT 0;
 DECLARE error_reason VARCHAR(255) DEFAULT NULL;
 DECLARE payment_kind VARCHAR(30);
 DECLARE owner_active BOOLEAN;
 IF p_amount IS NULL OR p_amount <= 0 OR p_source IS NULL OR p_destination IS NULL
 OR p_source=p_destination OR p_request IS NULL OR TRIM(p_request)='' THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid payment input'; END IF;
 SET source_owner=(SELECT user_id FROM funding_sources WHERE source_id=p_source);
 IF source_owner IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown source'; END IF;
 -- Serialize outgoing payments across every funding source owned by this payer.
 SELECT is_active INTO owner_active FROM users WHERE user_id=source_owner FOR UPDATE;
 IF p_source < p_destination THEN
  SELECT balance,source_type INTO source_balance,source_kind FROM funding_sources WHERE source_id=p_source FOR UPDATE;
  SELECT user_id,source_type INTO destination_owner,destination_kind FROM funding_sources WHERE source_id=p_destination FOR UPDATE;
 ELSE
  SELECT user_id,source_type INTO destination_owner,destination_kind FROM funding_sources WHERE source_id=p_destination FOR UPDATE;
  SELECT balance,source_type INTO source_balance,source_kind FROM funding_sources WHERE source_id=p_source FOR UPDATE;
 END IF;
 IF destination_owner IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown destination'; END IF;
 SET destination_role=(SELECT role FROM users WHERE user_id=destination_owner);
 SET payment_kind=CASE
  WHEN p_refund IS NOT NULL THEN 'REFUND'
  WHEN source_kind='BANK' AND destination_kind='WALLET' THEN 'BANK_TO_WALLET'
  WHEN source_kind='WALLET' AND destination_kind='BANK' THEN 'WALLET_TO_BANK'
  WHEN destination_role='MERCHANT' THEN 'MERCHANT_PAYMENT' ELSE 'P2P' END;
 INSERT INTO transactions(request_key,source_id,destination_source,category_id,amount,transaction_type,refund_of,schedule_id,scheduled_for)
 VALUES(p_request,p_source,p_destination,p_category,p_amount,payment_kind,p_refund,p_schedule,p_due);
 SET p_transaction=LAST_INSERT_ID();
 SET error_reason=p_precheck_error;
 IF NOT owner_active OR NOT EXISTS(SELECT 1 FROM users WHERE user_id=destination_owner AND is_active) THEN
 SET error_reason='Account user is inactive'; END IF;
 IF p_refund IS NULL AND destination_role='MERCHANT' AND NOT EXISTS
 (SELECT 1 FROM merchants WHERE user_id=destination_owner AND approval_status='APPROVED') THEN
 SET error_reason='Merchant is not approved'; END IF;
 IF p_refund IS NULL THEN
  SELECT payment_limit,daily_limit INTO payment_cap,daily_cap FROM customers WHERE user_id=source_owner;
  IF payment_cap IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment source must belong to a customer'; END IF;
  SELECT COALESCE(SUM(t.amount),0) INTO daily_spent
  FROM transactions t JOIN funding_sources f ON f.source_id=t.source_id
  JOIN transaction_events successful_event ON successful_event.transaction_id=t.transaction_id AND successful_event.status='SUCCESSFUL'
  WHERE f.user_id=source_owner AND t.refund_of IS NULL
   AND t.created_at >= CURRENT_DATE AND t.created_at < CURRENT_DATE + INTERVAL 1 DAY
   FOR UPDATE;
  IF p_amount > payment_cap THEN SET error_reason='Per-payment limit exceeded';
  ELSEIF daily_spent+p_amount > daily_cap THEN SET error_reason='Daily spending limit exceeded'; END IF;
 END IF;
 IF source_balance < p_amount THEN SET error_reason='Insufficient balance'; END IF;
 IF error_reason IS NULL THEN
  INSERT INTO transaction_events(transaction_id,status) VALUES(p_transaction,'AUTHORIZED'),(p_transaction,'PENDING');
  UPDATE funding_sources SET balance=balance-p_amount WHERE source_id=p_source;
  UPDATE funding_sources SET balance=balance+p_amount WHERE source_id=p_destination;
  INSERT INTO transaction_events(transaction_id,status) VALUES(p_transaction,'SUCCESSFUL');
  SET p_status='SUCCESSFUL';
 ELSE
  INSERT INTO transaction_events(transaction_id,status,reason) VALUES(p_transaction,'FAILED',error_reason);
  SET p_status='FAILED';
 END IF;
 INSERT INTO notifications(user_id,transaction_id,message,type) VALUES
  (source_owner,p_transaction,CONCAT('Payment ',p_transaction,': ',p_status,COALESCE(CONCAT(' - ',error_reason),'')),IF(p_schedule IS NULL,'PAYMENT','SCHEDULE')),
  (destination_owner,p_transaction,CONCAT('Incoming payment ',p_transaction,': ',p_status),IF(p_schedule IS NULL,'PAYMENT','SCHEDULE'));
END$$

CREATE PROCEDURE make_payment(
 IN p_request VARCHAR(64), IN p_customer INT, IN p_beneficiary INT,
 IN p_source INT, IN p_category VARCHAR(50), IN p_amount DECIMAL(15,2)
)
BEGIN
 DECLARE destination_id INT DEFAULT NULL;
 DECLARE customer_user INT DEFAULT NULL;
 DECLARE verification VARCHAR(20);
 DECLARE transaction_id_value BIGINT;
 DECLARE final_status VARCHAR(20);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SET customer_user=(SELECT user_id FROM customers WHERE customer_id=p_customer);
 SELECT destination_source,verification_status INTO destination_id,verification
 FROM beneficiaries WHERE beneficiary_id=p_beneficiary AND customer_id=p_customer FOR UPDATE;
 IF destination_id IS NULL OR verification <> 'VERIFIED' THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='A verified beneficiary owned by the payer is required'; END IF;
 IF customer_user IS NULL OR NOT EXISTS(SELECT 1 FROM funding_sources WHERE source_id=p_source AND user_id=customer_user) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Source account does not belong to the payer'; END IF;
 CALL post_transfer(p_request,p_source,destination_id,p_category,p_amount,NULL,NULL,NULL,NULL,transaction_id_value,final_status);
 COMMIT;
 SELECT transaction_id_value AS transaction_id,final_status AS status;
END$$

CREATE PROCEDURE validate_schedule(IN p_beneficiary INT, IN p_source INT)
BEGIN
 IF NOT EXISTS(SELECT 1 FROM beneficiaries b JOIN customers c ON c.customer_id=b.customer_id
 JOIN funding_sources f ON f.user_id=c.user_id AND f.source_id=p_source
 WHERE b.beneficiary_id=p_beneficiary AND b.verification_status='VERIFIED' AND b.destination_source<>p_source) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Schedule requires an owned source and a verified beneficiary'; END IF;
END$$
CREATE TRIGGER scheduled_before_insert BEFORE INSERT ON scheduled_payments FOR EACH ROW
BEGIN CALL validate_schedule(NEW.beneficiary_id,NEW.source_id); END$$
CREATE TRIGGER scheduled_before_update BEFORE UPDATE ON scheduled_payments FOR EACH ROW
BEGIN
 IF NEW.beneficiary_id<>OLD.beneficiary_id OR NEW.source_id<>OLD.source_id
 OR NEW.amount<>OLD.amount OR NEW.category_id<>OLD.category_id OR NEW.status='ACTIVE' AND OLD.status<>'ACTIVE' THEN
 CALL validate_schedule(NEW.beneficiary_id,NEW.source_id); END IF;
END$$

-- Run from an external scheduler in UTC. Processes one due occurrence per schedule.
CREATE PROCEDURE execute_schedule(IN p_schedule INT)
execute_block: BEGIN
 DECLARE beneficiary_value INT;
 DECLARE source_value INT;
 DECLARE destination_value INT;
 DECLARE category_value VARCHAR(50);
 DECLARE amount_value DECIMAL(15,2);
 DECLARE frequency_value VARCHAR(10);
 DECLARE due_value DATE;
 DECLARE end_value DATE;
 DECLARE schedule_status VARCHAR(20) DEFAULT NULL;
 DECLARE verification VARCHAR(20);
 DECLARE transaction_value BIGINT;
 DECLARE final_status VARCHAR(20);
 DECLARE precheck VARCHAR(255) DEFAULT NULL;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT beneficiary_id,source_id,category_id,amount,frequency,next_due_date,end_date,status
 INTO beneficiary_value,source_value,category_value,amount_value,frequency_value,due_value,end_value,schedule_status
 FROM scheduled_payments WHERE schedule_id=p_schedule FOR UPDATE;
 IF schedule_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown schedule'; END IF;
 IF schedule_status<>'ACTIVE' OR due_value>CURRENT_DATE THEN COMMIT; LEAVE execute_block; END IF;
 IF end_value IS NOT NULL AND due_value>end_value THEN
 UPDATE scheduled_payments SET status='COMPLETED' WHERE schedule_id=p_schedule;
 COMMIT; LEAVE execute_block; END IF;
 SELECT destination_source,verification_status INTO destination_value,verification
 FROM beneficiaries WHERE beneficiary_id=beneficiary_value FOR UPDATE;
 IF verification<>'VERIFIED' THEN SET precheck='Scheduled beneficiary is no longer verified'; END IF;
 CALL post_transfer(CONCAT('schedule:',p_schedule,':',due_value),source_value,destination_value,
 category_value,amount_value,NULL,p_schedule,due_value,precheck,transaction_value,final_status);
 SET due_value=CASE frequency_value WHEN 'DAILY' THEN DATE_ADD(due_value,INTERVAL 1 DAY)
 WHEN 'WEEKLY' THEN DATE_ADD(due_value,INTERVAL 1 WEEK) ELSE DATE_ADD(due_value,INTERVAL 1 MONTH) END;
 UPDATE scheduled_payments SET next_due_date=due_value,
 status=IF(end_value IS NOT NULL AND due_value>end_value,'COMPLETED','ACTIVE') WHERE schedule_id=p_schedule;
 COMMIT;
END$$
CREATE PROCEDURE run_due_payments()
BEGIN
 DECLARE finished BOOLEAN DEFAULT FALSE;
 DECLARE schedule_value INT;
 DECLARE due_cursor CURSOR FOR SELECT schedule_id FROM scheduled_payments
 WHERE status='ACTIVE' AND next_due_date<=CURRENT_DATE ORDER BY schedule_id;
 DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished=TRUE;
 OPEN due_cursor;
 due_loop: LOOP
 FETCH due_cursor INTO schedule_value;
 IF finished THEN LEAVE due_loop; END IF;
 CALL execute_schedule(schedule_value);
 END LOOP;
 CLOSE due_cursor;
END$$

CREATE TRIGGER split_validate BEFORE INSERT ON split_expenses FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM transactions t JOIN funding_sources f ON f.source_id=t.source_id
 JOIN customers c ON c.user_id=f.user_id
 WHERE t.transaction_id=NEW.transaction_id AND c.customer_id=NEW.customer_id AND t.refund_of IS NULL
 AND EXISTS(SELECT 1 FROM transaction_events e WHERE e.transaction_id=t.transaction_id AND e.status='SUCCESSFUL')
 AND NOT EXISTS(SELECT 1 FROM transactions refund WHERE refund.refund_of=t.transaction_id)) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An expense must match a successful payment made by its payer'; END IF;
END$$
CREATE TRIGGER shares_validate BEFORE INSERT ON expense_shares FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM split_expenses e JOIN group_members g ON g.group_id=e.group_id
 WHERE e.split_id=NEW.split_id AND g.customer_id=NEW.customer_id) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Expense shares must belong to group members'; END IF;
END$$
CREATE TRIGGER shares_update BEFORE UPDATE ON expense_shares FOR EACH ROW
BEGIN
 IF NEW.split_id<>OLD.split_id OR NEW.customer_id<>OLD.customer_id OR NEW.share_amount<>OLD.share_amount
 OR OLD.status='SETTLED' THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Allocated or settled shares cannot be rewritten'; END IF;
 IF NEW.status='SETTLED' AND NOT EXISTS(
 SELECT 1 FROM transactions t JOIN funding_sources src ON src.source_id=t.source_id
 JOIN funding_sources dst ON dst.source_id=t.destination_source
 JOIN customers debtor ON debtor.user_id=src.user_id
 JOIN split_expenses e ON e.split_id=NEW.split_id
 JOIN customers creditor ON creditor.customer_id=e.customer_id
 WHERE t.transaction_id=NEW.settlement_transaction_id AND debtor.customer_id=NEW.customer_id
 AND dst.user_id=creditor.user_id AND t.amount=NEW.share_amount AND t.refund_of IS NULL
 AND EXISTS(SELECT 1 FROM transaction_events ev WHERE ev.transaction_id=t.transaction_id AND ev.status='SUCCESSFUL')) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Settled share requires a matching successful repayment'; END IF;
END$$

-- NULL shares means an equal split; otherwise pass a JSON array of customer_id/amount.
CREATE PROCEDURE create_split(IN p_group INT, IN p_customer INT, IN p_transaction BIGINT, IN p_shares JSON)
BEGIN
 DECLARE split_value INT;
 DECLARE amount_value DECIMAL(15,2) DEFAULT NULL;
 DECLARE member_count INT;
 DECLARE cents_value BIGINT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT amount INTO amount_value FROM transactions WHERE transaction_id=p_transaction FOR UPDATE;
 IF amount_value IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown expense payment'; END IF;
 -- Serialize group allocation with membership edits made by the application.
 SELECT group_id INTO member_count FROM split_groups WHERE group_id=p_group FOR UPDATE;
 SELECT COUNT(*) INTO member_count FROM group_members WHERE group_id=p_group;
 IF member_count=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Group has no members'; END IF;
 IF p_shares IS NOT NULL THEN
  IF JSON_TYPE(p_shares)<>'ARRAY' OR JSON_LENGTH(p_shares)=0 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Custom shares must be a nonempty array'; END IF;
  IF EXISTS(SELECT 1 FROM JSON_TABLE(p_shares,'$[*]' COLUMNS(
   customer_id INT PATH '$.customer_id', amount DECIMAL(18,6) PATH '$.amount')) j
   WHERE j.customer_id IS NULL OR j.amount IS NULL OR j.amount<=0 OR j.amount<>ROUND(j.amount,2)
   OR NOT EXISTS(SELECT 1 FROM group_members g WHERE g.group_id=p_group AND g.customer_id=j.customer_id)) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid participant or share amount'; END IF;
  IF (SELECT COUNT(*)<>COUNT(DISTINCT customer_id) OR SUM(amount)<>amount_value
    OR SUM(customer_id=p_customer)<>1 FROM JSON_TABLE(p_shares,'$[*]' COLUMNS(
    customer_id INT PATH '$.customer_id', amount DECIMAL(18,6) PATH '$.amount')) j) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Shares must be unique, include the payer, and sum to the payment'; END IF;
 END IF;
 INSERT INTO split_expenses(group_id,customer_id,transaction_id,split_type)
 VALUES(p_group,p_customer,p_transaction,IF(p_shares IS NULL,'EQUAL','CUSTOM'));
 SET split_value=LAST_INSERT_ID();
 IF p_shares IS NULL THEN
  SET cents_value=CAST(amount_value*100 AS UNSIGNED);
  IF cents_value<member_count THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Amount is too small for positive member shares'; END IF;
  INSERT INTO expense_shares(split_id,customer_id,share_amount,acceptance,status,settled_at)
  SELECT split_value,customer_id,
   (FLOOR(cents_value/member_count)+IF(ROW_NUMBER() OVER(ORDER BY customer_id)<=MOD(cents_value,member_count),1,0))/100,
   IF(customer_id=p_customer,'ACCEPTED','PENDING'),IF(customer_id=p_customer,'SETTLED','PENDING'),
   IF(customer_id=p_customer,CURRENT_TIMESTAMP(6),NULL)
  FROM group_members WHERE group_id=p_group;
 ELSE
  INSERT INTO expense_shares(split_id,customer_id,share_amount,acceptance,status,settled_at)
  SELECT split_value,customer_id,amount,IF(customer_id=p_customer,'ACCEPTED','PENDING'),
   IF(customer_id=p_customer,'SETTLED','PENDING'),IF(customer_id=p_customer,CURRENT_TIMESTAMP(6),NULL)
  FROM JSON_TABLE(p_shares,'$[*]' COLUMNS(customer_id INT PATH '$.customer_id',amount DECIMAL(15,2) PATH '$.amount')) j;
 END IF;
 INSERT INTO notifications(user_id,message,type)
 SELECT c.user_id,CONCAT('Expense ',split_value,': your share is INR ',s.share_amount),'SPLIT'
 FROM expense_shares s JOIN customers c ON c.customer_id=s.customer_id WHERE s.split_id=split_value;
 COMMIT;
 SELECT split_value AS split_id;
END$$
CREATE PROCEDURE respond_to_split(IN p_split INT, IN p_customer INT, IN p_accept BOOLEAN)
BEGIN
 DECLARE recipient INT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 IF p_accept IS NULL OR p_accept NOT IN(0,1) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Acceptance must be true or false'; END IF;
 UPDATE expense_shares SET acceptance=IF(p_accept,'ACCEPTED','DECLINED')
 WHERE split_id=p_split AND customer_id=p_customer AND acceptance='PENDING' AND status='PENDING';
 IF ROW_COUNT()<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='No pending split invitation for this customer'; END IF;
 SELECT c.user_id INTO recipient FROM split_expenses e JOIN customers c ON c.customer_id=e.customer_id WHERE e.split_id=p_split;
 INSERT INTO notifications(user_id,message,type) VALUES(recipient,CONCAT('Customer ',p_customer,' ',IF(p_accept,'accepted','declined'),' expense ',p_split),'SPLIT');
 COMMIT;
END$$
CREATE PROCEDURE settle_share(IN p_request VARCHAR(64), IN p_split INT, IN p_customer INT,
 IN p_source INT, IN p_beneficiary INT)
BEGIN
 DECLARE amount_value DECIMAL(15,2) DEFAULT NULL;
 DECLARE destination_value INT;
 DECLARE category_value VARCHAR(50);
 DECLARE payer_user INT;
 DECLARE creditor_user INT;
 DECLARE transaction_value BIGINT;
 DECLARE final_status VARCHAR(20);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT share_amount INTO amount_value FROM expense_shares
 WHERE split_id=p_split AND customer_id=p_customer AND acceptance='ACCEPTED' AND status='PENDING' FOR UPDATE;
 IF amount_value IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An accepted unpaid share is required'; END IF;
 SELECT c.user_id,t.category_id INTO creditor_user,category_value
 FROM split_expenses e JOIN customers c ON c.customer_id=e.customer_id
 JOIN transactions t ON t.transaction_id=e.transaction_id WHERE e.split_id=p_split;
 SET payer_user=(SELECT user_id FROM customers WHERE customer_id=p_customer);
 SELECT destination_source INTO destination_value FROM beneficiaries b JOIN funding_sources f ON f.source_id=b.destination_source
 WHERE b.beneficiary_id=p_beneficiary AND b.customer_id=p_customer AND b.verification_status='VERIFIED' AND f.user_id=creditor_user FOR UPDATE;
 IF destination_value IS NULL OR NOT EXISTS(SELECT 1 FROM funding_sources WHERE source_id=p_source AND user_id=payer_user) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Repayment requires owned source and verified beneficiary for the expense payer'; END IF;
 CALL post_transfer(p_request,p_source,destination_value,category_value,amount_value,NULL,NULL,NULL,NULL,transaction_value,final_status);
 IF final_status='SUCCESSFUL' THEN
 UPDATE expense_shares SET status='SETTLED',settlement_transaction_id=transaction_value,settled_at=CURRENT_TIMESTAMP(6)
 WHERE split_id=p_split AND customer_id=p_customer;
 END IF;
 COMMIT;
 SELECT transaction_value AS transaction_id,final_status AS status;
END$$

CREATE TRIGGER dispute_validate BEFORE INSERT ON disputes FOR EACH ROW
BEGIN
 IF NEW.status<>'OPEN' OR NOT EXISTS(
 SELECT 1 FROM transactions t JOIN funding_sources f ON f.source_id=t.source_id
 JOIN customers c ON c.user_id=f.user_id
 WHERE t.transaction_id=NEW.transaction_id AND c.customer_id=NEW.raised_by AND t.refund_of IS NULL
 AND EXISTS(SELECT 1 FROM transaction_events e WHERE e.transaction_id=t.transaction_id AND e.status='SUCCESSFUL')) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only the payer may dispute a successful original payment'; END IF;
 IF NEW.admin_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM admins WHERE admin_id=NEW.admin_id AND admin_scope='PLATFORM') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Dispute requires a platform admin'; END IF;
END$$
CREATE TRIGGER dispute_update BEFORE UPDATE ON disputes FOR EACH ROW
BEGIN
 IF OLD.status<>'OPEN' OR NEW.transaction_id<>OLD.transaction_id OR NEW.raised_by<>OLD.raised_by
 OR NEW.reason<>OLD.reason OR NOT(NEW.description <=> OLD.description) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Dispute evidence and final decisions cannot be rewritten'; END IF;
 IF NEW.admin_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM admins WHERE admin_id=NEW.admin_id AND admin_scope='PLATFORM') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Dispute requires a platform admin'; END IF;
 IF NEW.status='RESOLVED' AND NOT EXISTS(SELECT 1 FROM transactions t
 WHERE t.transaction_id=NEW.refund_transaction_id AND t.refund_of=NEW.transaction_id
 AND EXISTS(SELECT 1 FROM transaction_events e WHERE e.transaction_id=t.transaction_id AND e.status='SUCCESSFUL')) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolution requires a successful linked refund'; END IF;
END$$
CREATE TRIGGER dispute_notification AFTER INSERT ON disputes FOR EACH ROW
BEGIN
 INSERT INTO notifications(user_id,transaction_id,message,type)
 SELECT user_id,NEW.transaction_id,CONCAT('Dispute ',NEW.dispute_id,' opened'),'DISPUTE'
 FROM customers WHERE customer_id=NEW.raised_by;
END$$
CREATE PROCEDURE resolve_dispute(IN p_dispute INT, IN p_admin INT, IN p_approve BOOLEAN, IN p_notes VARCHAR(1000))
BEGIN
 DECLARE original_id BIGINT DEFAULT NULL;
 DECLARE source_value INT;
 DECLARE destination_value INT;
 DECLARE category_value VARCHAR(50);
 DECLARE amount_value DECIMAL(15,2);
 DECLARE customer_value INT;
 DECLARE refund_id BIGINT;
 DECLARE final_status VARCHAR(20);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_approve IS NULL OR p_approve NOT IN(0,1) OR p_notes IS NULL OR TRIM(p_notes)='' THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='A decision and resolution notes are required'; END IF;
 START TRANSACTION;
 IF NOT EXISTS(SELECT 1 FROM admins a JOIN users u ON u.user_id=a.user_id
 WHERE a.admin_id=p_admin AND a.admin_scope='PLATFORM' AND u.is_active) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active platform admin must review the dispute'; END IF;
 SELECT transaction_id,raised_by INTO original_id,customer_value FROM disputes WHERE dispute_id=p_dispute AND status='OPEN' FOR UPDATE;
 IF original_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An open dispute is required'; END IF;
 IF p_approve THEN
  IF EXISTS(SELECT 1 FROM split_expenses WHERE transaction_id=original_id)
  OR EXISTS(SELECT 1 FROM expense_shares WHERE settlement_transaction_id=original_id) THEN
   SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Group payments require split reconciliation before a refund';
  END IF;
  SELECT source_id,destination_source,category_id,amount INTO source_value,destination_value,category_value,amount_value
  FROM transactions WHERE transaction_id=original_id FOR UPDATE;
  CALL post_transfer(CONCAT('refund:',original_id),destination_value,source_value,category_value,amount_value,
   original_id,NULL,NULL,NULL,refund_id,final_status);
  IF final_status<>'SUCCESSFUL' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Refund failed; dispute remains open and no balances changed'; END IF;
  UPDATE disputes SET admin_id=p_admin,status='RESOLVED',resolution_notes=p_notes,
  refund_transaction_id=refund_id,resolved_at=CURRENT_TIMESTAMP(6) WHERE dispute_id=p_dispute;
 ELSE
  UPDATE disputes SET admin_id=p_admin,status='REJECTED',resolution_notes=p_notes,resolved_at=CURRENT_TIMESTAMP(6)
  WHERE dispute_id=p_dispute;
 END IF;
 INSERT INTO notifications(user_id,transaction_id,message,type)
 SELECT user_id,original_id,CONCAT('Dispute ',p_dispute,': ',IF(p_approve,'refund completed','rejected')),'DISPUTE'
 FROM customers WHERE customer_id=customer_value;
 COMMIT;
END$$
DELIMITER ;
