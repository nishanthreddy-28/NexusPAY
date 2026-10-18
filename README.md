# NexusPAY

A MySQL DBMS project for managing digital payment records, bank accounts, beneficiaries, and shared expenses.

The database connects customers and merchants with their accounts and payments. It also stores group expenses, each member's share, scheduled payment instructions, disputes, and notifications.

## Database design

The 15 tables are organised around:

- **Users:** users, customers, merchants, and admins.
- **Payments:** bank accounts, categories, transactions, beneficiaries, and scheduled payments.
- **Shared expenses:** split groups, group members, split expenses, and expense shares.
- **Support:** disputes and notifications.

[View the ER diagram](ER_diagram.pdf). This is the initial design; the SQL separates individual expense shares into their own table and removes the circular group-to-expense reference.

## Files

```text
sql/
  01_schema.sql    Tables, keys, constraints, and indexes
  02_routines.sql  Payment procedure and beneficiary ownership triggers
  03_views.sql     Spending, revenue, and pending-share reports
  04_seed.sql      Sample data
  05_queries.sql   Joins, summaries, subqueries, and index example
ER_diagram.pdf
README.md
LICENSE
```

## Run the project

Use MySQL 8.4 and a fresh database. Open the SQL files in MySQL Workbench and execute them in the numbered order. Refresh the Schemas panel to see `nexuspay`.

Alternatively, run these commands from the repository folder:

```bash
mysql -u root -p < sql/01_schema.sql
mysql -u root -p < sql/02_routines.sql
mysql -u root -p < sql/03_views.sql
mysql -u root -p < sql/04_seed.sql
mysql -u root -p < sql/05_queries.sql
```

Run the setup scripts once. Running them again against the same database will cause duplicate-table or duplicate-record errors.

## Sample scenario

Nisha pays Rs. 600 to Campus Cafe from an account with Rs. 10,000. Her balance becomes Rs. 9,400 and the cafe receives Rs. 600. The lunch is split equally with Arjun, whose Rs. 300 share remains pending.

```sql
USE nexuspay;
SELECT * FROM customer_spending;
SELECT * FROM merchant_revenue;
SELECT * FROM outstanding_shares;

-- Another payment of Rs. 125 to the cafe
CALL pay_merchant('payment-002', 1, 1, 'DEMO-C001', 'DEMO-M001', 125.00);
```

The procedure checks account ownership and available balance, then records the payment and updates both accounts in one transaction. If an operation fails, the changes are rolled back. The payment reference must be unique to prevent a second debit for the same request. Call the procedure outside an existing transaction.

## DBMS concepts used

Primary and foreign keys, unique and check constraints, joins, aggregate functions, subqueries, views, a window function, indexes, stored procedures, triggers, and transactions with row locking.

The SQL was tested on MySQL 8.4.11, including successful payments and rollback checks for duplicate requests, insufficient funds, and invalid account ownership.

## Scope

This project implements the database only. Scheduled payments are stored instructions, and expense settlement status is recorded without transferring money. Group-share totals and membership need application-level validation. There is no frontend or connection to a real bank.

## License

[MIT](LICENSE)
