USE nexuspay;
-- The latest appended event is the current state; payment facts stay unchanged.
CREATE VIEW transaction_history AS
SELECT t.*,e.status,e.reason,src.user_id AS payer_user_id,dst.user_id AS payee_user_id
FROM transactions t
JOIN transaction_events e ON e.event_id=(SELECT MAX(last_event.event_id)
 FROM transaction_events last_event WHERE last_event.transaction_id=t.transaction_id)
JOIN funding_sources src ON src.source_id=t.source_id
JOIN funding_sources dst ON dst.source_id=t.destination_source;

-- Preserve a familiar bank-account view while wallets use the same balance model.
CREATE VIEW bank_accounts AS
SELECT source_id,account_reference AS account_number,user_id,bank_name,ifsc_code,balance,is_primary
FROM funding_sources WHERE source_type='BANK';

CREATE VIEW customer_spending AS
SELECT c.customer_id,u.name,COUNT(t.transaction_id) AS payment_count,COALESCE(SUM(t.amount),0) AS total_spent
FROM customers c JOIN users u ON u.user_id=c.user_id
LEFT JOIN transaction_history t ON t.payer_user_id=c.user_id AND t.status='SUCCESSFUL' AND t.refund_of IS NULL AND t.payer_user_id<>t.payee_user_id
GROUP BY c.customer_id,u.name;

CREATE VIEW merchant_revenue AS
SELECT m.merchant_id,m.business_name,COUNT(CASE WHEN t.payee_user_id=m.user_id AND t.refund_of IS NULL THEN 1 END) AS payment_count,
COALESCE(SUM(CASE WHEN t.payee_user_id=m.user_id AND t.refund_of IS NULL THEN t.amount
 WHEN t.payer_user_id=m.user_id AND t.refund_of IS NOT NULL THEN -t.amount ELSE 0 END),0) AS net_revenue
FROM merchants m LEFT JOIN transaction_history t
 ON (t.payee_user_id=m.user_id OR t.payer_user_id=m.user_id) AND t.status='SUCCESSFUL'
GROUP BY m.merchant_id,m.business_name;

CREATE VIEW merchant_annual_summary AS
SELECT m.merchant_id,m.business_name,YEAR(t.created_at) AS report_year,
SUM(CASE WHEN t.payee_user_id=m.user_id AND t.refund_of IS NULL THEN t.amount ELSE 0 END) AS gross_received,
SUM(CASE WHEN t.payer_user_id=m.user_id AND t.refund_of IS NOT NULL THEN t.amount ELSE 0 END) AS refunds_paid
FROM merchants m JOIN transaction_history t
 ON (t.payee_user_id=m.user_id OR t.payer_user_id=m.user_id) AND t.status='SUCCESSFUL'
GROUP BY m.merchant_id,m.business_name,YEAR(t.created_at);

CREATE VIEW outstanding_shares AS
SELECT e.group_id,s.customer_id,s.acceptance,SUM(s.share_amount) AS amount_due
FROM expense_shares s JOIN split_expenses e ON e.split_id=s.split_id
WHERE s.status='PENDING' GROUP BY e.group_id,s.customer_id,s.acceptance;

-- Filter by bank_admin_id in the backend after authenticating the caller.
CREATE VIEW bank_transaction_log AS
SELECT a.admin_id AS bank_admin_id,a.bank_name,t.*
FROM admins a JOIN funding_sources src ON src.bank_name=a.bank_name AND src.source_type='BANK'
JOIN transaction_history t ON t.source_id=src.source_id
WHERE a.admin_scope='BANK'
UNION
SELECT a.admin_id,a.bank_name,t.*
FROM admins a JOIN funding_sources dst ON dst.bank_name=a.bank_name AND dst.source_type='BANK'
JOIN transaction_history t ON t.destination_source=dst.source_id
WHERE a.admin_scope='BANK';
