USE nexuspay;
CREATE VIEW customer_spending AS
 SELECT c.customer_id,u.name,COUNT(t.transaction_id) AS payment_count,COALESCE(SUM(t.amount),0) AS total_spent
 FROM customers c JOIN users u ON u.user_id=c.user_id
 LEFT JOIN transactions t ON t.customer_payer=c.customer_id GROUP BY c.customer_id,u.name;
CREATE VIEW merchant_revenue AS
 SELECT m.merchant_id,m.business_name,COUNT(t.transaction_id) AS payment_count,COALESCE(SUM(t.amount),0) AS revenue
 FROM merchants m LEFT JOIN transactions t ON t.payee_id=m.merchant_id GROUP BY m.merchant_id,m.business_name;
CREATE VIEW outstanding_shares AS
 SELECT e.group_id,s.customer_id,SUM(s.share_amount) AS amount_due
 FROM expense_shares s JOIN split_expenses e ON e.split_id=s.split_id
 WHERE s.status='PENDING' GROUP BY e.group_id,s.customer_id;
