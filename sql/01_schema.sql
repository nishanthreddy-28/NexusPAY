-- MySQL 8.4+. Fresh installation only: existing tables are never dropped.
CREATE DATABASE IF NOT EXISTS nexuspay CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE nexuspay;
CREATE TABLE users (
 user_id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(100) NOT NULL,
 email VARCHAR(255) NOT NULL UNIQUE, password_hash VARCHAR(255) NOT NULL,
 role ENUM('ADMIN','CUSTOMER','MERCHANT') NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
CREATE TABLE categories (
 category_id VARCHAR(50) PRIMARY KEY, category_name VARCHAR(100) NOT NULL UNIQUE,
 description VARCHAR(255)
) ENGINE=InnoDB;
CREATE TABLE admins (
 admin_id INT PRIMARY KEY AUTO_INCREMENT, user_id INT NOT NULL UNIQUE,
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
CREATE TABLE customers (
 customer_id INT PRIMARY KEY AUTO_INCREMENT, user_id INT NOT NULL UNIQUE, dob DATE,
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
CREATE TABLE merchants (
 merchant_id INT PRIMARY KEY AUTO_INCREMENT, user_id INT NOT NULL UNIQUE,
 business_name VARCHAR(255) NOT NULL, category_id VARCHAR(50) NOT NULL,
 approved_by INT, gst_number VARCHAR(20) UNIQUE,
 FOREIGN KEY(user_id) REFERENCES users(user_id),
 FOREIGN KEY(category_id) REFERENCES categories(category_id),
 FOREIGN KEY(approved_by) REFERENCES admins(admin_id)
) ENGINE=InnoDB;
CREATE TABLE bank_accounts (
 account_number VARCHAR(50) PRIMARY KEY, user_id INT NOT NULL,
 bank_name VARCHAR(100) NOT NULL, ifsc_code VARCHAR(11) NOT NULL,
 balance DECIMAL(15,2) NOT NULL DEFAULT 0 CHECK(balance >= 0),
 is_primary BOOLEAN NOT NULL DEFAULT FALSE,
 primary_owner INT GENERATED ALWAYS AS (CASE WHEN is_primary THEN user_id ELSE NULL END) STORED UNIQUE,
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
CREATE TABLE beneficiaries (
 beneficiary_id INT PRIMARY KEY AUTO_INCREMENT, customer_id INT NOT NULL,
 beneficiary_customer_id INT NOT NULL, beneficiary_name VARCHAR(100) NOT NULL,
 UNIQUE(customer_id, beneficiary_customer_id),
 CHECK(customer_id <> beneficiary_customer_id),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id),
 FOREIGN KEY(beneficiary_customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;
CREATE TABLE transactions (
 transaction_id BIGINT PRIMARY KEY AUTO_INCREMENT, request_key VARCHAR(64) NOT NULL UNIQUE,
 customer_payer INT NOT NULL, payee_id INT NOT NULL, category_id VARCHAR(50) NOT NULL,
 source_account VARCHAR(50) NOT NULL, destination_account VARCHAR(50) NOT NULL,
 amount DECIMAL(15,2) NOT NULL CHECK(amount > 0),
 transaction_type ENUM('MERCHANT_PAYMENT') NOT NULL DEFAULT 'MERCHANT_PAYMENT',
 status ENUM('COMPLETED') NOT NULL DEFAULT 'COMPLETED',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(source_account <> destination_account),
 FOREIGN KEY(customer_payer) REFERENCES customers(customer_id),
 FOREIGN KEY(payee_id) REFERENCES merchants(merchant_id),
 FOREIGN KEY(category_id) REFERENCES categories(category_id),
 FOREIGN KEY(source_account) REFERENCES bank_accounts(account_number),
 FOREIGN KEY(destination_account) REFERENCES bank_accounts(account_number),
 INDEX idx_customer_time(customer_payer, created_at), INDEX idx_merchant_time(payee_id, created_at)
) ENGINE=InnoDB;
CREATE TABLE scheduled_payments (
 schedule_id INT PRIMARY KEY AUTO_INCREMENT, customer_id INT NOT NULL,
 beneficiary_id INT NOT NULL, amount DECIMAL(15,2) NOT NULL CHECK(amount > 0),
 frequency ENUM('DAILY','WEEKLY','MONTHLY') NOT NULL,
 start_date DATE NOT NULL, end_date DATE, next_due_date DATE NOT NULL,
 status ENUM('ACTIVE','PAUSED','CANCELLED') NOT NULL DEFAULT 'ACTIVE',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(end_date IS NULL OR end_date >= start_date), CHECK(next_due_date >= start_date),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id),
 FOREIGN KEY(beneficiary_id) REFERENCES beneficiaries(beneficiary_id),
 INDEX idx_due(status, next_due_date)
) ENGINE=InnoDB;
CREATE TABLE split_groups (
 group_id INT PRIMARY KEY AUTO_INCREMENT, initiated_customer INT NOT NULL,
 group_name VARCHAR(100) NOT NULL,
 FOREIGN KEY(initiated_customer) REFERENCES customers(customer_id)
) ENGINE=InnoDB;
CREATE TABLE group_members (
 group_id INT NOT NULL, customer_id INT NOT NULL,
 joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(group_id, customer_id),
 FOREIGN KEY(group_id) REFERENCES split_groups(group_id),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;
CREATE TABLE split_expenses (
 split_id INT PRIMARY KEY AUTO_INCREMENT, group_id INT NOT NULL,
 customer_id INT NOT NULL, transaction_id BIGINT NOT NULL UNIQUE,
 total_amount DECIMAL(15,2) NOT NULL CHECK(total_amount > 0),
 split_type ENUM('EQUAL','CUSTOM') NOT NULL,
 FOREIGN KEY(group_id, customer_id) REFERENCES group_members(group_id, customer_id),
 FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_id)
) ENGINE=InnoDB;
CREATE TABLE expense_shares (
 split_id INT NOT NULL, customer_id INT NOT NULL,
 share_amount DECIMAL(15,2) NOT NULL CHECK(share_amount > 0),
 status ENUM('PENDING','SETTLED') NOT NULL DEFAULT 'PENDING',
 PRIMARY KEY(split_id, customer_id),
 FOREIGN KEY(split_id) REFERENCES split_expenses(split_id),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;
CREATE TABLE disputes (
 dispute_id INT PRIMARY KEY AUTO_INCREMENT, transaction_id BIGINT NOT NULL,
 raised_by INT NOT NULL, admin_id INT, reason VARCHAR(100) NOT NULL,
 description VARCHAR(1000), status ENUM('OPEN','RESOLVED','REJECTED') NOT NULL DEFAULT 'OPEN',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, resolved_at DATETIME,
 CHECK((status='OPEN' AND resolved_at IS NULL) OR (status <> 'OPEN' AND resolved_at IS NOT NULL)),
 FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_id),
 FOREIGN KEY(raised_by) REFERENCES customers(customer_id),
 FOREIGN KEY(admin_id) REFERENCES admins(admin_id)
) ENGINE=InnoDB;
CREATE TABLE notifications (
 notification_id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id INT NOT NULL,
 message TEXT NOT NULL, type VARCHAR(50) NOT NULL, read_status BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
