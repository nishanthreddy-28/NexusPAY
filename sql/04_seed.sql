USE nexuspay;
-- Fictional demo identities. These placeholders are not usable password hashes.
INSERT INTO users(name,email,password_hash,role) VALUES
 ('Asha Rao','asha@example.test','DEMO_DISABLED','ADMIN'),
 ('Nisha Shah','nisha@example.test','DEMO_DISABLED','CUSTOMER'),
 ('Arjun Das','arjun@example.test','DEMO_DISABLED','CUSTOMER'),
 ('Campus Cafe','cafe@example.test','DEMO_DISABLED','MERCHANT');
INSERT INTO categories VALUES('FOOD','Food & dining','Meals and refreshments');
INSERT INTO admins(user_id) VALUES(1);
INSERT INTO customers(user_id,dob) VALUES(2,'2003-05-10'),(3,'2002-09-21');
INSERT INTO merchants(user_id,business_name,category_id,approved_by) VALUES(4,'Campus Cafe','FOOD',1);
INSERT INTO bank_accounts(account_number,user_id,bank_name,ifsc_code,balance,is_primary) VALUES
 ('DEMO-C001',2,'Demo Bank','DEMO0000001',10000,TRUE),
 ('DEMO-C002',3,'Demo Bank','DEMO0000001',8000,TRUE),
 ('DEMO-M001',4,'Demo Bank','DEMO0000001',0,TRUE);
INSERT INTO beneficiaries(customer_id,beneficiary_customer_id,beneficiary_name) VALUES(1,2,'Arjun');
CALL pay_merchant('demo-lunch-001',1,1,'DEMO-C001','DEMO-M001',600);
INSERT INTO scheduled_payments(customer_id,beneficiary_id,amount,frequency,start_date,next_due_date)
 VALUES(1,1,500,'MONTHLY','2026-01-01','2026-11-01');
INSERT INTO split_groups(initiated_customer,group_name) VALUES(1,'Campus lunch');
INSERT INTO group_members(group_id,customer_id) VALUES(1,1),(1,2);
INSERT INTO split_expenses(group_id,customer_id,transaction_id,total_amount,split_type) VALUES(1,1,1,600,'EQUAL');
INSERT INTO expense_shares VALUES(1,1,300,'SETTLED'),(1,2,300,'PENDING');
INSERT INTO disputes(transaction_id,raised_by,admin_id,reason,description)
 VALUES(1,1,1,'Receipt requested','Demo request for an itemized receipt');
