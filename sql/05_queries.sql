USE nexuspay;
SET time_zone = '+00:00';
-- Payment history includes both successful and financially rejected attempts.
SELECT t.transaction_id,payer.name AS payer,payee.name AS payee,t.transaction_type,t.amount,t.status,t.reason,t.created_at
FROM transaction_history t JOIN users payer ON payer.user_id=t.payer_user_id
JOIN users payee ON payee.user_id=t.payee_user_id ORDER BY t.transaction_id;
SELECT * FROM customer_spending ORDER BY total_spent DESC;
SELECT * FROM merchant_revenue ORDER BY net_revenue DESC;
SELECT * FROM merchant_annual_summary;
SELECT * FROM outstanding_shares;
SELECT * FROM bank_transaction_log WHERE bank_admin_id=2;
-- Window function.
SELECT name,total_spent,DENSE_RANK() OVER(ORDER BY total_spent DESC) AS spending_rank FROM customer_spending;
-- Correlated subquery: customers with no successful outgoing payments.
SELECT c.customer_id FROM customers c WHERE NOT EXISTS
 (SELECT 1 FROM transaction_history t WHERE t.payer_user_id=c.user_id AND t.status='SUCCESSFUL' AND t.refund_of IS NULL);
-- Reconcile split allocations with the immutable original payment amount.
SELECT e.split_id,t.amount AS total_amount,COALESCE(SUM(s.share_amount),0) AS allocated
FROM split_expenses e JOIN transactions t ON t.transaction_id=e.transaction_id
LEFT JOIN expense_shares s ON s.split_id=e.split_id
GROUP BY e.split_id,t.amount HAVING allocated<>t.amount;
-- Complete lifecycle audit.
SELECT transaction_id,status,reason,created_at FROM transaction_events ORDER BY transaction_id,event_id;
EXPLAIN SELECT * FROM transactions WHERE source_id=1 ORDER BY created_at DESC;
-- Manual examples: these change data; run individually after inspecting the sample.
-- CALL settle_share('settle-lunch-001',1,2,2,5);
-- CALL resolve_dispute(1,1,TRUE,'Extra item confirmed; full refund approved');
-- CALL run_due_payments(); -- invoke periodically from a backend job, in UTC
-- UPDATE scheduled_payments SET status='CANCELLED' WHERE schedule_id=1;
