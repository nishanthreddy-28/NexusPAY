# NexusPAY - Digital Payment Database

NexusPAY is a DBMS project for storing payment records, bank account details, beneficiaries, and shared expenses using MySQL.

The project looks at a simple payment scenario: a customer pays a merchant, the payment is recorded, and the account balances are updated. If the payment was for a group expense, each person's share can be stored separately. It also includes tables for scheduled payments, disputes, and notifications.

## Problem statement

Payment information is connected to several other records. A payment needs a payer, a receiving merchant, bank accounts, an amount, and a date. A shared expense also needs a group and the amount owed by each member. Storing these details without clear relationships can lead to duplicate records or payments linked to the wrong person.

The aim of this project is to design these relationships and use SQL constraints and transactions to keep the records consistent.

## Tools used

- MySQL 8.4
- SQL for table creation, sample data, queries, views, procedures, and triggers
- MySQL command-line client or MySQL Workbench to run the scripts

The scripts were tested on MySQL 8.4.11. Docker is also available as an optional way to run the database.

## Database design

The database has 15 tables:

- `users`, `customers`, `merchants`, `admins` - user details and their respective profiles.
- `bank_accounts`, `categories`, `transactions` - accounts, payment categories, and merchant payments.
- `beneficiaries`, `scheduled_payments` - saved recipients and payment schedules.
- `split_groups`, `group_members`, `split_expenses`, `expense_shares` - groups, expenses, and individual shares.
- `disputes`, `notifications` - payment complaints and user messages.

The [original ER diagram](docs/ER_diagram.pdf) shows the initial design. The [database design notes](docs/design.md) explain the relationships used in the SQL, including the separate table for individual expense shares. Field descriptions are in the [data dictionary](docs/data-dictionary.md).

## Files

```text
sql/
  01_schema.sql       Creates the database and tables
  02_routines.sql     Payment procedure and schedule ownership triggers
  03_views.sql        Customer spending, merchant revenue, and pending shares
  04_seed.sql         Sample records
  05_queries.sql      Queries for retrieving and analysing the records
  06_demo.sql         A payment example with before-and-after balances

docs/
  ER_diagram.pdf      Initial ER diagram
  design.md           Relationships and design decisions
  data-dictionary.md  Description of each table
  sample-output.txt   Output from running the payment example

tests/
  verify.sql          Checks for payments and failed transactions
```

## How to run

Start with a MySQL server where the `nexuspay` database does not already contain project tables. Open a terminal in this repository and run the following commands in order. Enter your MySQL password when prompted.

```bash
mysql -u root -p < sql/01_schema.sql
mysql -u root -p < sql/02_routines.sql
mysql -u root -p < sql/03_views.sql
mysql -u root -p < sql/04_seed.sql
mysql -u root -p < sql/05_queries.sql
```

In MySQL Workbench, open each file and execute the complete script in the same order. Refresh the Schemas panel to see `nexuspay`.

Run the schema and sample-data scripts once for a new database. They are not migration scripts and will report errors if the tables or sample records already exist.

## Example: paying for a group lunch

The sample data includes two customers, Nisha and Arjun, and a merchant called Campus Cafe.

Nisha starts with Rs. 10,000 and pays Rs. 600 to the cafe. Her balance becomes Rs. 9,400, and the cafe receives Rs. 600. The lunch is split equally: Nisha's Rs. 300 share is marked as settled, and Arjun's Rs. 300 share is pending.

To view the records:

```sql
USE nexuspay;

SELECT * FROM customer_spending;
SELECT * FROM merchant_revenue;
SELECT * FROM outstanding_shares;
```

To make another payment of Rs. 125:

```sql
CALL pay_merchant(
    'my-payment-002', 1, 1,
    'DEMO-C001', 'DEMO-M001', 125.00
);
```

The first argument is a unique reference for the payment request. Using it again causes an error and does not debit the account twice. Call this procedure outside an existing transaction because it starts and commits its own transaction.

For a complete before-and-after example, run this once after loading the sample data:

```bash
mysql -u root -p < sql/06_demo.sql
```

The results are saved in [sample-output.txt](docs/sample-output.txt). The demo adds a payment, so run the verification script on a separate, freshly seeded database.

## DBMS concepts covered

Primary and foreign keys connect the tables. Unique and check constraints prevent duplicate emails, repeated payment references, and invalid amounts. Joins retrieve payment details across customers and merchants. Aggregate functions and views calculate spending and revenue. The query file also includes a subquery, a window function, and an `EXPLAIN` example for the payment-history index.

The payment procedure uses a transaction so that the debit, credit, payment record, and notification either all succeed or all roll back. It checks account ownership and available balance before completing the payment. Triggers check that a scheduled payment uses a beneficiary saved by that customer.

To run the checks on a freshly seeded database:

```bash
mysql -u root -p < tests/verify.sql
```

This script adds one Rs. 25 payment and checks the resulting balances. It also checks duplicate requests, insufficient balance, incorrect account ownership, and incorrect beneficiary ownership. A successful run prints a `PASS` message. Recreate the demo database before running it again.

## Current limitations

This repository contains the database part of the project. There is no frontend or connection to a real bank. Scheduled payments are stored but are not executed automatically. Marking an expense share as settled does not transfer money.

Some rules still need application-level checks, such as ensuring that all shares belong to group members and add up to the expense total. These are described in the design notes.

## Optional Docker setup

```bash
cp .env.example .env
# Set a local password in .env before starting.
docker compose up -d --wait
```

Connect to `127.0.0.1:3307` as `root` using the password in `.env`. The setup loads the schema, routines, views, and sample data automatically on the first start. Run `docker compose down` to stop it while keeping the data. `docker compose down -v` deletes the local database volume; use it only when deliberately resetting the demo.

The repository also includes a GitHub Actions workflow that loads the SQL and runs the verification script on MySQL 8.4.

## License

[MIT](LICENSE)
