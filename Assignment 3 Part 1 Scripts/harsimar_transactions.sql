-- Transaction (a): Internet Expense
INSERT INTO transactions (date, account_debit, amount_debit, account_credit, amount_credit, description)
VALUES ('2023-10-10', 'Internet Expense', 80.00, 'Accounts Payable', 80.00, 'Internet bill for October - to be paid later');

-- Transaction (b): Payroll Liability
INSERT INTO transactions (date, account_debit, amount_debit, account_credit, amount_credit, description)
VALUES ('2023-10-10', 'Payroll Expense', 2125.00, 'Payroll Liability', 2125.00, 'Midmonth payroll recorded as liability');
