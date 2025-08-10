/*
Assignment 3 Part 1

Melbourne Marsden
Aryan Bhanot
Rishi Chaudhari
Harsimar Sahota

Date: July 30, 2025

This script processes accounting transactions from the holding table (NEW_TRANSACTIONS).
For each transaction, it creates a record in TRANSACTION_HISTORY, adds detail lines to
TRANSACTION_DETAIL, updates the correct account balances in the ACCOUNT table,
and finally then removes the completed transaction from the holding table.
*/


DECLARE
    -- This cursor selects the distinct transactions from the holding table.
    -- So if a transaction took place over multiple lines, it will only
    -- return one record per transaction number, along with its date and description.
    CURSOR c_transactions IS
        SELECT DISTINCT transaction_no, transaction_date, description
        FROM new_transactions
        ORDER BY transaction_no;

    -- Selects all individual detail lines for each specific transaction number.
    -- It takes the transaction number as a parameter to return only the details
    -- for the transaction currently being processed.
    CURSOR c_trans_details (p_trans_num NUMBER) IS
        SELECT account_no, transaction_type, transaction_amount
        FROM new_transactions
        WHERE transaction_no = p_trans_num;

    -- Stores the default transaction type (debit or credit) for an account.
    v_default_type   account_type.default_trans_type%TYPE;

BEGIN
    -- Loop through each unique transaction found by the c_transactions cursor.
    FOR trans IN c_transactions LOOP

        -- Insert one record for the transaction into the TRANSACTION_HISTORY table.
        -- All the data needed comes straight from the basic transactions cursor.
        INSERT INTO transaction_history (transaction_no, transaction_date, description)
        VALUES (trans.transaction_no, trans.transaction_date, trans.description);

        -- The inner loop processes each detail line for the current transaction.
        -- It uses the c_trans_details cursor, passing it the current transaction number.
        FOR detail IN c_trans_details(trans.transaction_no) LOOP

            -- Insert the individual transaction line into the TRANSACTION_DETAIL table.
            INSERT INTO transaction_detail (account_no, transaction_no, transaction_type, transaction_amount)
            VALUES (detail.account_no, trans.transaction_no, detail.transaction_type, detail.transaction_amount);

            -- Retrieve the account's default transaction type by looking it up in the ACCOUNT_TYPE table.
            SELECT at.default_trans_type
            INTO   v_default_type
            FROM   account a
            JOIN   account_type at ON a.account_type_code = at.account_type_code
            WHERE  a.account_no = detail.account_no;

            -- If the transaction type matches the account's type, the balance increases.
            -- Otherwise, it decreases.
            IF detail.transaction_type = v_default_type THEN
                -- Increase the balance.
                UPDATE account
                SET    account_balance = account_balance + detail.transaction_amount
                WHERE  account_no = detail.account_no;
            ELSE
                -- Decrease the balance.
                UPDATE account
                SET    account_balance = account_balance - detail.transaction_amount
                WHERE  account_no = detail.account_no;
            END IF;

        END LOOP; -- End of the inner loop for transaction details.

        -- Once the iteration is complete, delete the transaction from the holding table.
        DELETE FROM new_transactions
        WHERE transaction_no = trans.transaction_no;

    END LOOP; -- End of the outer loop for the transaction summaries.

    -- After all transactions are processed, commit the changes.
    COMMIT;

END;
/