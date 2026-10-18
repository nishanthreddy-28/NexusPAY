-- Run once on a freshly seeded database. This example adds one payment.
USE nexuspay;
SELECT '1. Balances after the sample lunch payment' AS step;
SELECT account_number, balance FROM bank_accounts ORDER BY account_number;
SELECT '2. Pending share from the lunch' AS step;
SELECT * FROM outstanding_shares;
SELECT '3. Nisha pays another Rs. 125 to Campus Cafe' AS step;
CALL pay_merchant('demo-extra-payment',1,1,'DEMO-C001','DEMO-M001',125.00);
SELECT account_number, balance FROM bank_accounts ORDER BY account_number;
SELECT '4. Updated customer spending' AS step;
SELECT * FROM customer_spending ORDER BY customer_id;
SELECT '5. Updated merchant revenue' AS step;
SELECT * FROM merchant_revenue ORDER BY merchant_id;
