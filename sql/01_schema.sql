-- MySQL 8.4. Run once on a fresh database; this file never drops existing data.
CREATE DATABASE IF NOT EXISTS nexuspay CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE nexuspay;
SET time_zone = '+00:00';

CREATE TABLE users (
 user_id INT PRIMARY KEY AUTO_INCREMENT,
 name VARCHAR(100) NOT NULL,
 email VARCHAR(255) NOT NULL UNIQUE,
 password_hash VARCHAR(255) NOT NULL,
 role ENUM('ADMIN','BANK_ADMIN','CUSTOMER','MERCHANT') NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;
CREATE TABLE categories (
 category_id VARCHAR(50) PRIMARY KEY,
 category_name VARCHAR(100) NOT NULL UNIQUE,
 description VARCHAR(255)
) ENGINE=InnoDB;
CREATE TABLE admins (
 admin_id INT PRIMARY KEY AUTO_INCREMENT,
 user_id INT NOT NULL UNIQUE,
 admin_scope ENUM('PLATFORM','BANK') NOT NULL DEFAULT 'PLATFORM',
 bank_name VARCHAR(100),
 CHECK((admin_scope='PLATFORM' AND bank_name IS NULL) OR
       (admin_scope='BANK' AND bank_name IS NOT NULL)),
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
CREATE TABLE customers (
 customer_id INT PRIMARY KEY AUTO_INCREMENT,
 user_id INT NOT NULL UNIQUE,
 dob DATE,
 payment_limit DECIMAL(15,2) NOT NULL DEFAULT 10000 CHECK(payment_limit > 0),
 daily_limit DECIMAL(15,2) NOT NULL DEFAULT 50000,
 CHECK(daily_limit >= payment_limit),
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
CREATE TABLE merchants (
 merchant_id INT PRIMARY KEY AUTO_INCREMENT,
 user_id INT NOT NULL UNIQUE,
 business_name VARCHAR(255) NOT NULL,
 category_id VARCHAR(50) NOT NULL,
 approval_status ENUM('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING',
 approved_by INT,
 gst_number VARCHAR(20) UNIQUE,
 CHECK(approval_status <> 'APPROVED' OR approved_by IS NOT NULL),
 FOREIGN KEY(user_id) REFERENCES users(user_id),
 FOREIGN KEY(category_id) REFERENCES categories(category_id),
 FOREIGN KEY(approved_by) REFERENCES admins(admin_id)
) ENGINE=InnoDB;
-- One funding-source relation supports the bank and wallet flows in the SRS.
CREATE TABLE funding_sources (
 source_id INT PRIMARY KEY AUTO_INCREMENT,
 user_id INT NOT NULL,
 source_type ENUM('BANK','WALLET') NOT NULL,
 account_reference VARCHAR(50) NOT NULL UNIQUE,
 bank_name VARCHAR(100),
 ifsc_code VARCHAR(11),
 wallet_name VARCHAR(100),
 balance DECIMAL(15,2) NOT NULL DEFAULT 0 CHECK(balance >= 0),
 is_primary BOOLEAN NOT NULL DEFAULT FALSE,
 primary_owner VARCHAR(40) GENERATED ALWAYS AS
   (CASE WHEN is_primary THEN CONCAT(user_id, ':', source_type) ELSE NULL END) STORED UNIQUE,
 CHECK((source_type='BANK' AND bank_name IS NOT NULL AND ifsc_code IS NOT NULL AND wallet_name IS NULL)
    OR (source_type='WALLET' AND bank_name IS NULL AND ifsc_code IS NULL AND wallet_name IS NOT NULL)),
 FOREIGN KEY(user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;
CREATE TABLE beneficiaries (
 beneficiary_id INT PRIMARY KEY AUTO_INCREMENT,
 customer_id INT NOT NULL,
 destination_source INT NOT NULL,
 beneficiary_name VARCHAR(100) NOT NULL,
 verification_status ENUM('PENDING','VERIFIED','BLOCKED') NOT NULL DEFAULT 'PENDING',
 verified_by INT,
 verified_at DATETIME(6),
 UNIQUE(customer_id, destination_source),
 CHECK(verification_status <> 'VERIFIED' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id),
 FOREIGN KEY(destination_source) REFERENCES funding_sources(source_id),
 FOREIGN KEY(verified_by) REFERENCES admins(admin_id)
) ENGINE=InnoDB;
-- The owner is derived from the beneficiary, avoiding a repeated customer_id.
CREATE TABLE scheduled_payments (
 schedule_id INT PRIMARY KEY AUTO_INCREMENT,
 beneficiary_id INT NOT NULL,
 source_id INT NOT NULL,
 category_id VARCHAR(50) NOT NULL,
 amount DECIMAL(15,2) NOT NULL CHECK(amount > 0),
 frequency ENUM('DAILY','WEEKLY','MONTHLY') NOT NULL,
 start_date DATE NOT NULL,
 end_date DATE,
 next_due_date DATE NOT NULL,
 status ENUM('ACTIVE','PAUSED','CANCELLED','COMPLETED') NOT NULL DEFAULT 'ACTIVE',
 created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 CHECK(end_date IS NULL OR end_date >= start_date),
 CHECK(next_due_date >= start_date),
 FOREIGN KEY(beneficiary_id) REFERENCES beneficiaries(beneficiary_id),
 FOREIGN KEY(source_id) REFERENCES funding_sources(source_id),
 FOREIGN KEY(category_id) REFERENCES categories(category_id),
 INDEX idx_due(status, next_due_date)
) ENGINE=InnoDB;
-- Payment facts are immutable. State changes are appended to transaction_events.
CREATE TABLE transactions (
 transaction_id BIGINT PRIMARY KEY AUTO_INCREMENT,
 request_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL UNIQUE,
 source_id INT NOT NULL,
 destination_source INT NOT NULL,
 category_id VARCHAR(50) NOT NULL,
 amount DECIMAL(15,2) NOT NULL CHECK(amount > 0),
 transaction_type ENUM('P2P','MERCHANT_PAYMENT','BANK_TO_WALLET','WALLET_TO_BANK','REFUND') NOT NULL,
 refund_of BIGINT UNIQUE,
 schedule_id INT,
 scheduled_for DATE,
 created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 CHECK(source_id <> destination_source),
 CHECK((transaction_type='REFUND' AND refund_of IS NOT NULL) OR
       (transaction_type <> 'REFUND' AND refund_of IS NULL)),
 CHECK((schedule_id IS NULL AND scheduled_for IS NULL) OR
       (schedule_id IS NOT NULL AND scheduled_for IS NOT NULL)),
 UNIQUE(schedule_id, scheduled_for),
 FOREIGN KEY(source_id) REFERENCES funding_sources(source_id),
 FOREIGN KEY(destination_source) REFERENCES funding_sources(source_id),
 FOREIGN KEY(category_id) REFERENCES categories(category_id),
 FOREIGN KEY(refund_of) REFERENCES transactions(transaction_id),
 FOREIGN KEY(schedule_id) REFERENCES scheduled_payments(schedule_id),
 INDEX idx_source_time(source_id, created_at),
 INDEX idx_destination_time(destination_source, created_at)
) ENGINE=InnoDB;
CREATE TABLE transaction_events (
 event_id BIGINT PRIMARY KEY AUTO_INCREMENT,
 transaction_id BIGINT NOT NULL,
 status ENUM('INITIATED','AUTHORIZED','PENDING','SUCCESSFUL','FAILED') NOT NULL,
 reason VARCHAR(255),
 created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_id),
 INDEX idx_transaction_events(transaction_id, event_id)
) ENGINE=InnoDB;
CREATE TABLE split_groups (
 group_id INT PRIMARY KEY AUTO_INCREMENT,
 initiated_customer INT NOT NULL,
 group_name VARCHAR(100) NOT NULL,
 FOREIGN KEY(initiated_customer) REFERENCES customers(customer_id)
) ENGINE=InnoDB;
CREATE TABLE group_members (
 group_id INT NOT NULL,
 customer_id INT NOT NULL,
 joined_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 PRIMARY KEY(group_id, customer_id),
 FOREIGN KEY(group_id) REFERENCES split_groups(group_id),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;
CREATE TABLE split_expenses (
 split_id INT PRIMARY KEY AUTO_INCREMENT,
 group_id INT NOT NULL,
 customer_id INT NOT NULL,
 transaction_id BIGINT NOT NULL UNIQUE,
 split_type ENUM('EQUAL','CUSTOM') NOT NULL,
 FOREIGN KEY(group_id, customer_id) REFERENCES group_members(group_id, customer_id),
 FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_id)
) ENGINE=InnoDB;
-- Individual shares have a weak/composite identity within an expense.
CREATE TABLE expense_shares (
 split_id INT NOT NULL,
 customer_id INT NOT NULL,
 share_amount DECIMAL(15,2) NOT NULL CHECK(share_amount > 0),
 acceptance ENUM('PENDING','ACCEPTED','DECLINED') NOT NULL DEFAULT 'PENDING',
 status ENUM('PENDING','SETTLED') NOT NULL DEFAULT 'PENDING',
 settlement_transaction_id BIGINT UNIQUE,
 settled_at DATETIME(6),
 PRIMARY KEY(split_id, customer_id),
 CHECK((status='PENDING' AND settlement_transaction_id IS NULL AND settled_at IS NULL) OR
       (status='SETTLED' AND acceptance='ACCEPTED' AND settled_at IS NOT NULL)),
 FOREIGN KEY(split_id) REFERENCES split_expenses(split_id),
 FOREIGN KEY(customer_id) REFERENCES customers(customer_id),
 FOREIGN KEY(settlement_transaction_id) REFERENCES transactions(transaction_id)
) ENGINE=InnoDB;
CREATE TABLE disputes (
 dispute_id INT PRIMARY KEY AUTO_INCREMENT,
 transaction_id BIGINT NOT NULL UNIQUE,
 raised_by INT NOT NULL,
 admin_id INT,
 reason VARCHAR(100) NOT NULL,
 description VARCHAR(1000),
 status ENUM('OPEN','RESOLVED','REJECTED') NOT NULL DEFAULT 'OPEN',
 resolution_notes VARCHAR(1000),
 refund_transaction_id BIGINT UNIQUE,
 created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 resolved_at DATETIME(6),
 CHECK((status='OPEN' AND resolved_at IS NULL AND refund_transaction_id IS NULL) OR
       (status='RESOLVED' AND resolved_at IS NOT NULL AND admin_id IS NOT NULL AND refund_transaction_id IS NOT NULL) OR
       (status='REJECTED' AND resolved_at IS NOT NULL AND admin_id IS NOT NULL AND refund_transaction_id IS NULL)),
 FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_id),
 FOREIGN KEY(raised_by) REFERENCES customers(customer_id),
 FOREIGN KEY(admin_id) REFERENCES admins(admin_id),
 FOREIGN KEY(refund_transaction_id) REFERENCES transactions(transaction_id)
) ENGINE=InnoDB;
CREATE TABLE notifications (
 notification_id BIGINT PRIMARY KEY AUTO_INCREMENT,
 user_id INT NOT NULL,
 transaction_id BIGINT,
 message TEXT NOT NULL,
 type ENUM('PAYMENT','SCHEDULE','SPLIT','DISPUTE') NOT NULL,
 read_status BOOLEAN NOT NULL DEFAULT FALSE,
 created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 FOREIGN KEY(user_id) REFERENCES users(user_id),
 FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_id)
) ENGINE=InnoDB;
