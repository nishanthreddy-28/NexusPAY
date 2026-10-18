USE nexuspay;
-- JOIN: detailed payment history.
SELECT t.transaction_id,u.name AS customer,m.business_name,t.amount,t.created_at
FROM transactions t JOIN customers c ON c.customer_id=t.customer_payer
JOIN users u ON u.user_id=c.user_id JOIN merchants m ON m.merchant_id=t.payee_id;
-- Aggregation and reusable views.
SELECT * FROM customer_spending ORDER BY total_spent DESC;
SELECT * FROM merchant_revenue ORDER BY revenue DESC;
SELECT * FROM outstanding_shares;
-- Window function: rank customers by spend.
SELECT name,total_spent,DENSE_RANK() OVER(ORDER BY total_spent DESC) AS spending_rank FROM customer_spending;
-- Correlated subquery: customers with no payments.
SELECT c.customer_id FROM customers c WHERE NOT EXISTS
 (SELECT 1 FROM transactions t WHERE t.customer_payer=c.customer_id);
-- Reconciliation: a split must allocate its entire total.
SELECT e.split_id,e.total_amount,COALESCE(SUM(s.share_amount),0) AS allocated
FROM split_expenses e LEFT JOIN expense_shares s ON s.split_id=e.split_id
GROUP BY e.split_id,e.total_amount HAVING allocated <> e.total_amount;
-- Index demonstration.
EXPLAIN SELECT * FROM transactions WHERE customer_payer=1 ORDER BY created_at DESC;
-- Scheduled payments are stored instructions; no scheduler executes them.
SELECT * FROM scheduled_payments WHERE status='ACTIVE' AND next_due_date <= CURRENT_DATE;
