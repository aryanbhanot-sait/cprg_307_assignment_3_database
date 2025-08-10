-- Authors: Sahilpreet Singh
--         : Vorain Gautam 




-- Assignment - 3 - Part - 2 -- CPRG-307-E
-- Date: April 21, 2025
-- This is the coded solution for the problem of We Keep It Storage (WKIS) company.
-- This solution successfully processes the new transactions, and stores them in transaction_history
-- and transaction_detail tables. It also updates the account balances in the account table.
-- For the Erroneous transactions, it logs the error in the wkis_error_log table and does not remove them
-- from the new_transactions table. Unanticipated errors are also handled and rolled back.


DECLARE
    -- variables and constants
    v_current_row new_transactions%ROWTYPE; -- current transaction for debugging
    e_invalid_transaction EXCEPTION; -- exception for invalid transactions
    v_error_message VARCHAR2(200);
    v_account_exists NUMBER;
    v_is_valid BOOLEAN; -- flag variable
    v_total_debits NUMBER := 0;
    v_total_credits NUMBER := 0;
    const_credit CONSTANT CHAR(1) := 'C';
    const_debit CONSTANT CHAR(1) := 'D';

    -- Cursor to loop through transactions in new_transactions
    CURSOR cur_transactions IS
        SELECT * FROM new_transactions
        ORDER BY transaction_no;
BEGIN
    -- loop through transactions from cursor
    FOR rec_transaction IN cur_transactions LOOP
        -- initialize variables flag
        v_current_row := rec_transaction;
        v_is_valid := TRUE;

        -- validation and error handling
        BEGIN
            -- check that transaction number is not null
            IF rec_transaction.transaction_no IS NULL THEN
                v_error_message := 'Missing transaction number';
                RAISE e_invalid_transaction;
            END IF;

            -- check that debits and credits are same
            SELECT SUM(transaction_amount)
            INTO v_total_debits
            FROM new_transactions
            WHERE transaction_no = rec_transaction.transaction_no
              AND transaction_type = const_debit;

            SELECT SUM(transaction_amount)
            INTO v_total_credits
            FROM new_transactions
            WHERE transaction_no = rec_transaction.transaction_no
              AND transaction_type = const_credit;

            IF v_total_debits <> v_total_credits THEN
                v_error_message := 'Unbalanced transaction: Debits and Credits must be equal';
                RAISE e_invalid_transaction;
            END IF;

            -- check that account number exists in account table
            SELECT COUNT(*)
            INTO v_account_exists
            FROM account
            WHERE account_no = rec_transaction.account_no;

            IF v_account_exists = 0 THEN
                v_error_message := 'Account number does not exists: ' || rec_transaction.account_no;
                RAISE e_invalid_transaction;
            END IF;

            -- check that transaction amount is negative
            IF rec_transaction.transaction_amount < 0 THEN
                v_error_message := 'Negative transaction amount: ' || rec_transaction.transaction_amount;
                RAISE e_invalid_transaction;
            END IF;

            -- check for the transaction type
            IF rec_transaction.transaction_type NOT IN (const_credit, const_debit) THEN
                v_error_message := 'Invalid transaction type (must be either C or D ): ' || rec_transaction.transaction_type;
                RAISE e_invalid_transaction;
            END IF;

        EXCEPTION
            -- Log errors of invalid transactions in wkis_error_log
            WHEN e_invalid_transaction THEN
                INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
                VALUES (v_current_row.transaction_no, v_current_row.transaction_date, v_current_row.description, v_error_message);
                v_is_valid := FALSE;
        END;

        -- for valid transactions
        IF v_is_valid THEN
            -- alter the transaction history or create a row
            UPDATE transaction_history
            SET transaction_date = rec_transaction.transaction_date,
                description = rec_transaction.description
            WHERE transaction_no = rec_transaction.transaction_no;

            IF SQL%ROWCOUNT = 0 THEN
                INSERT INTO transaction_history (transaction_no, transaction_date, description)
                VALUES (rec_transaction.transaction_no, rec_transaction.transaction_date, rec_transaction.description);
            END IF;

            -- transaction details and update account balances depending on transaction type

            -- if credit then
            IF rec_transaction.transaction_type = const_credit THEN
                INSERT INTO transaction_detail (account_no, transaction_no, transaction_type, transaction_amount)
                VALUES (rec_transaction.account_no,rec_transaction.transaction_no,const_credit,rec_transaction.transaction_amount);

                UPDATE account
                SET account_balance = account_balance + rec_transaction.transaction_amount
                WHERE account_no = rec_transaction.account_no;


            -- if debit then
            ELSIF rec_transaction.transaction_type = const_debit THEN
                INSERT INTO transaction_detail (account_no,transaction_no,transaction_type,transaction_amount)
                VALUES (rec_transaction.account_no,rec_transaction.transaction_no,const_debit,rec_transaction.transaction_amount);

                UPDATE account
                SET account_balance = account_balance - rec_transaction.transaction_amount
                WHERE account_no = rec_transaction.account_no;
            END IF;

            -- remove valid transactions from new_transactions
            DELETE FROM new_transactions
            WHERE transaction_no = rec_transaction.transaction_no
            AND transaction_type = rec_transaction.transaction_type;
        END IF;
    END LOOP;

    -- save/commit all the changes
    COMMIT;

EXCEPTION
    -- handle any unanticipated errors
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Unanticipated Error in transaction : ' || v_current_row.transaction_no || ' - ' || SQLERRM);
        ROLLBACK;
END;
/


