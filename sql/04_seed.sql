USE nexuspay;
SET time_zone = '+00:00';
-- Fictional records. DEMO_DISABLED is not a usable credential hash.
INSERT INTO users(name,email,password_hash,role) VALUES
 ('Asha Rao','asha@example.test','DEMO_DISABLED','ADMIN'),
 ('Nisha Shah','nisha@example.test','DEMO_DISABLED','CUSTOMER'),
 ('Arjun Das','arjun@example.test','DEMO_DISABLED','CUSTOMER'),
 ('Campus Cafe','cafe@example.test','DEMO_DISABLED','MERCHANT'),
 ('Demo Bank Admin','bank-admin@example.test','DEMO_DISABLED','BANK_ADMIN');
INSERT INTO categories VALUES
 ('FOOD','Food & dining','Meals and refreshments'),
 ('TRANSFER','Transfers','Peer payments and funding-source transfers');
INSERT INTO admins(user_id,admin_scope,bank_name) VALUES(1,'PLATFORM',NULL),(5,'BANK','Demo Bank');
INSERT INTO customers(user_id,dob) VALUES(2,'2003-05-10'),(3,'2002-09-21');
INSERT INTO merchants(user_id,business_name,category_id,approval_status,approved_by)
 VALUES(4,'Campus Cafe','FOOD','APPROVED',1);
INSERT INTO funding_sources(user_id,source_type,account_reference,bank_name,ifsc_code,wallet_name,balance,is_primary) VALUES
 (2,'BANK','DEMO-C001','Demo Bank','DEMO0000001',NULL,10000,TRUE),
 (3,'BANK','DEMO-C002','Demo Bank','DEMO0000001',NULL,8000,TRUE),
 (4,'BANK','DEMO-M001','Demo Bank','DEMO0000001',NULL,0,TRUE),
 (2,'WALLET','DEMO-W001',NULL,NULL,'Nexus Wallet',0,TRUE),
 (3,'WALLET','DEMO-W002',NULL,NULL,'Nexus Wallet',0,TRUE);
INSERT INTO beneficiaries(customer_id,destination_source,beneficiary_name,verification_status,verified_by,verified_at) VALUES
 (1,3,'Campus Cafe','VERIFIED',1,CURRENT_TIMESTAMP(6)),
 (1,2,'Arjun','VERIFIED',1,CURRENT_TIMESTAMP(6)),
 (1,4,'My wallet','VERIFIED',1,CURRENT_TIMESTAMP(6)),
 (1,1,'My bank account','VERIFIED',1,CURRENT_TIMESTAMP(6)),
 (2,1,'Nisha','VERIFIED',1,CURRENT_TIMESTAMP(6));
CALL make_payment('demo-lunch-001',1,1,1,'FOOD',600);
CALL make_payment('demo-topup-001',1,3,1,'TRANSFER',200);
CALL make_payment('demo-withdraw-001',1,4,4,'TRANSFER',50);
INSERT INTO scheduled_payments(beneficiary_id,source_id,category_id,amount,frequency,start_date,next_due_date)
 VALUES(2,1,'TRANSFER',500,'MONTHLY',CURRENT_DATE,CURRENT_DATE+INTERVAL 1 MONTH);
INSERT INTO split_groups(initiated_customer,group_name) VALUES(1,'Campus lunch');
INSERT INTO group_members(group_id,customer_id) VALUES(1,1),(1,2);
CALL create_split(1,1,1,NULL);
CALL respond_to_split(1,2,TRUE);
-- A separate payment demonstrates an open dispute without refunding the group lunch.
CALL make_payment('demo-dispute-001',1,1,1,'FOOD',100);
INSERT INTO disputes(transaction_id,raised_by,admin_id,reason,description)
 SELECT transaction_id,1,1,'Duplicate item billed','Please review an extra item on the receipt'
 FROM transactions WHERE request_key='demo-dispute-001';
