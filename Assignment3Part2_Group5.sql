/*
Assignment 3 Part 2

Aryan Bhanot
Melbourne Marsden
Rishi Chaudhari
Harsimar Sahota

Date: 9 August 2025

This script processes accounting transactions from the holding table (NEW_TRANSACTIONS),
with complete error checking and logging. For each valid transaction, it creates a record
in TRANSACTION_HISTORY, adds detail lines to TRANSACTION_DETAIL, updates the relevant
account balances in the ACCOUNT table, and removes completed transactions from NEW_TRANSACTIONS.
Erroneous transactions are left in the holding table and only the first error per transaction
is logged in WKIS_ERROR_LOG.
*/

DECLARE
    -- constants for transaction types
    const_debit  CONSTANT CHAR(1) := 'D';
    const_credit CONSTANT CHAR(1) := 'C';

    -- record structure for a transaction detail line
    v_detail_row new_transactions%ROWTYPE;

    -- error handling variables
    v_error_found   BOOLEAN := FALSE;
    v_error_message VARCHAR2(200);

    -- variables for debit/credit sum checks
    v_total_debits  NUMBER := 0;
    v_total_credits NUMBER := 0;

    -- for account validation
    v_account_exists NUMBER;

    -- cursor for distinct transactions in NEW_TRANSACTIONS
    CURSOR c_transactions IS
        SELECT DISTINCT transaction_no, transaction_date, description
        FROM new_transactions
        ORDER BY transaction_no;

    -- cursor for all details of a transaction
    CURSOR c_trans_details (p_trans_no NUMBER) IS
        SELECT *
        FROM new_transactions
        WHERE transaction_no = p_trans_no;

    -- flag for first error per transaction
    v_error_logged BOOLEAN := FALSE;

BEGIN
    -- loop through transactions from cursor
    FOR trans IN c_transactions LOOP

        -- reset error/validation flags at the start of each transaction
        v_error_found  := FALSE;
        v_error_logged := FALSE;
        v_error_message := NULL;
        v_total_debits := 0;
        v_total_credits := 0;

        -- Nested block to handle transaction detail validation and processing
        BEGIN
            -- Check for missing transaction number (should be impossible with DISTINCT, but required!)
            IF trans.transaction_no IS NULL THEN
                v_error_message := 'Missing transaction number.';
                v_error_found := TRUE;
                v_error_logged := TRUE;
                -- Insert error record
                INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                VALUES (trans.transaction_no, trans.transaction_date, trans.description, v_error_message);
            END IF;

            -- Process each line of the transaction (only if txn number exists)
            IF NOT v_error_found THEN
                -- For error detection, validate ALL rows of a transaction and accumulate debits & credits
                FOR detail IN c_trans_details(trans.transaction_no) LOOP
                    v_detail_row := detail;

                    -- Check transaction type validity (C or D)
                    IF detail.transaction_type NOT IN (const_credit, const_debit) AND NOT v_error_logged THEN
                        v_error_message := 'Invalid transaction type (must be C or D): ' || detail.transaction_type;
                        v_error_found := TRUE;
                        v_error_logged := TRUE;
                        INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                        VALUES (trans.transaction_no, trans.transaction_date, trans.description, v_error_message);
                        -- Only log first error per transaction
                    END IF;

                    -- Check for negative transaction amount
                    IF detail.transaction_amount < 0 AND NOT v_error_logged THEN
                        v_error_message := 'Negative transaction amount: ' || detail.transaction_amount;
                        v_error_found := TRUE;
                        v_error_logged := TRUE;
                        INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                        VALUES (trans.transaction_no, trans.transaction_date, trans.description, v_error_message);
                    END IF;

                    -- Validate account existence
                    SELECT COUNT(*)
                    INTO v_account_exists
                    FROM account
                    WHERE account_no = detail.account_no;

                    IF v_account_exists = 0 AND NOT v_error_logged THEN
                        v_error_message := 'Account number does not exist: ' || detail.account_no;
                        v_error_found := TRUE;
                        v_error_logged := TRUE;
                        INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                        VALUES (trans.transaction_no, trans.transaction_date, trans.description, v_error_message);
                    END IF;

                    -- Accumulate debits and credits amounts
                    IF detail.transaction_type = const_debit THEN
                        v_total_debits := v_total_debits + NVL(detail.transaction_amount, 0);
                    ELSIF detail.transaction_type = const_credit THEN
                        v_total_credits := v_total_credits + NVL(detail.transaction_amount, 0);
                    END IF;

                END LOOP; -- End inner details loop

                -- After processing all lines, check for balanced transaction
                IF v_total_debits <> v_total_credits AND NOT v_error_logged THEN
                    v_error_message := 'Unbalanced transaction: Debits (' || v_total_debits ||
                                       ') and Credits (' || v_total_credits || ') must be equal.';
                    v_error_found := TRUE;
                    v_error_logged := TRUE;
                    INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                    VALUES (trans.transaction_no, trans.transaction_date, trans.description, v_error_message);
                END IF;
            END IF;

            -- If transaction is clean, process inserts/updates and remove from holding table
            IF NOT v_error_found THEN
                -- Insert transaction history (once per transaction)
                INSERT INTO transaction_history (transaction_no, transaction_date, description)
                VALUES (trans.transaction_no, trans.transaction_date, trans.description);

                -- For each row, insert detail and update account balances
                FOR detail IN c_trans_details(trans.transaction_no) LOOP
                    -- Insert detail record
                    INSERT INTO transaction_detail (account_no, transaction_no, transaction_type, transaction_amount)
                    VALUES (detail.account_no, trans.transaction_no, detail.transaction_type, detail.transaction_amount);

                    -- Get account's default transaction type
                    DECLARE
                        v_default_type account_type.default_trans_type%TYPE;
                    BEGIN
                        SELECT at.default_trans_type
                        INTO v_default_type
                        FROM account a
                        JOIN account_type at ON a.account_type_code = at.account_type_code
                        WHERE a.account_no = detail.account_no;

                        -- Update account balance according to default type logic
                        IF detail.transaction_type = v_default_type THEN
                            UPDATE account
                            SET account_balance = account_balance + detail.transaction_amount
                            WHERE account_no = detail.account_no;
                        ELSE
                            UPDATE account
                            SET account_balance = account_balance - detail.transaction_amount
                            WHERE account_no = detail.account_no;
                        END IF;
                    END;
                END LOOP;

                -- Remove processed transaction rows from holding table
                DELETE FROM new_transactions
                WHERE transaction_no = trans.transaction_no;
            END IF;

        EXCEPTION
            -- Unexpected errors caught for this transaction only; leave rows in NEW_TRANSACTIONS
            WHEN OTHERS THEN
                INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                VALUES (trans.transaction_no, trans.transaction_date, trans.description,
                        'Unanticipated error: ' || SQLERRM);
                -- Do NOT stop main loop, continue to next transaction
        END;

    END LOOP; -- End of transaction loop

    -- Final commit
    COMMIT;

EXCEPTION
    -- handle any truly unexpected script-level error
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Unanticipated error in main block: ' || SQLERRM);
        ROLLBACK;
END;
/