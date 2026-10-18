USE nexuspay;
DELIMITER $$
CREATE PROCEDURE pay_merchant(
 IN p_request VARCHAR(64), IN p_customer INT, IN p_merchant INT,
 IN p_source VARCHAR(50), IN p_destination VARCHAR(50), IN p_amount DECIMAL(15,2)
)
BEGIN
 DECLARE v_source_owner INT DEFAULT NULL;
 DECLARE v_destination_owner INT DEFAULT NULL;
 DECLARE v_customer_user INT DEFAULT NULL;
 DECLARE v_merchant_user INT DEFAULT NULL;
 DECLARE v_category VARCHAR(50);
 DECLARE v_balance DECIMAL(15,2);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_amount IS NULL OR p_amount <= 0 OR p_request IS NULL OR TRIM(p_request) = ''
 OR p_source IS NULL OR p_destination IS NULL OR p_source = p_destination THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid payment input';
 END IF;
 START TRANSACTION;
 SELECT user_id INTO v_customer_user FROM customers WHERE customer_id=p_customer;
 SELECT user_id, category_id INTO v_merchant_user, v_category FROM merchants WHERE merchant_id=p_merchant;
 -- Deterministic lock order reduces deadlocks for concurrent account pairs.
 IF p_source < p_destination THEN
  SELECT user_id, balance INTO v_source_owner, v_balance FROM bank_accounts WHERE account_number=p_source FOR UPDATE;
  SELECT user_id INTO v_destination_owner FROM bank_accounts WHERE account_number=p_destination FOR UPDATE;
 ELSE
  SELECT user_id INTO v_destination_owner FROM bank_accounts WHERE account_number=p_destination FOR UPDATE;
  SELECT user_id, balance INTO v_source_owner, v_balance FROM bank_accounts WHERE account_number=p_source FOR UPDATE;
 END IF;
 IF v_source_owner IS NULL OR v_destination_owner IS NULL OR v_customer_user IS NULL
 OR v_merchant_user IS NULL OR v_source_owner <> v_customer_user OR v_destination_owner <> v_merchant_user THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Account ownership mismatch';
 END IF;
 IF v_balance < p_amount THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient balance';
 END IF;
 INSERT INTO transactions(request_key,customer_payer,payee_id,category_id,source_account,destination_account,amount)
 VALUES(p_request,p_customer,p_merchant,v_category,p_source,p_destination,p_amount);
 UPDATE bank_accounts SET balance=balance-p_amount WHERE account_number=p_source;
 UPDATE bank_accounts SET balance=balance+p_amount WHERE account_number=p_destination;
 INSERT INTO notifications(user_id,message,type) VALUES(v_customer_user,CONCAT('Payment completed: INR ',p_amount),'PAYMENT');
 COMMIT;
END$$
CREATE TRIGGER scheduled_owner_before_insert BEFORE INSERT ON scheduled_payments FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM beneficiaries WHERE beneficiary_id=NEW.beneficiary_id AND customer_id=NEW.customer_id) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Beneficiary belongs to another customer';
 END IF;
END$$
CREATE TRIGGER scheduled_owner_before_update BEFORE UPDATE ON scheduled_payments FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM beneficiaries WHERE beneficiary_id=NEW.beneficiary_id AND customer_id=NEW.customer_id) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Beneficiary belongs to another customer';
 END IF;
END$$
DELIMITER ;
