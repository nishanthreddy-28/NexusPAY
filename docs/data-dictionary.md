# Data dictionary

All identifiers are integer surrogate keys unless stated otherwise. Money uses DECIMAL(15,2) in INR. Timestamps use the MySQL session time zone; set a consistent time zone in any future application.

- **users:** shared identity, unique email, password hash, and declared role. Demo credentials are disabled placeholders.
- **admins:** one admin profile per linked user; reviews disputes and approves merchants.
- **customers:** one customer profile per linked user, with optional date of birth.
- **categories:** string category key, unique display name, and description.
- **merchants:** one business profile per linked user, category, optional approving admin and GST number.
- **bank_accounts:** string account number key, owner, bank and IFSC, balance, primary flag. A generated nullable unique owner column enforces at most one primary account per user.
- **beneficiaries:** a customer's saved recipient customer; the owner-recipient pair is unique and cannot refer to the same customer twice.
- **transactions:** completed merchant payment, unique caller-supplied request key, payer customer, payee merchant, historical category, source and destination accounts, amount and timestamp. BIGINT supports a larger payment history.
- **scheduled_payments:** customer-owned beneficiary instruction with amount, frequency, date range, next due date, and active/paused/cancelled state. Ownership is validated on insert and update.
- **split_groups:** named group and initiating customer.
- **group_members:** composite group/customer key and join timestamp.
- **split_expenses:** group expense paid by a member, unique linked payment, total, and equal/custom split type.
- **expense_shares:** composite expense/customer key, allocated amount, and pending/settled state.
- **disputes:** linked payment, raising customer, optional assigned admin, reason, description, state, and resolution timestamps.
- **notifications:** user-owned message, type, read flag, and timestamp.

The design notes explain cross-row rules that require application-level enforcement. No cascade deletion is configured for financial history.
