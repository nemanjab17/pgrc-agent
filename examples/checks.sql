-- One boolean SQL per line, run against the *restored* database.
-- Point the agent at this file with PGRC_CHECK_SQL=/checks.sql
SELECT count(*) > 0 FROM customers
SELECT count(*) > 0 FROM orders
-- No order may reference a customer that did not survive the restore:
SELECT NOT EXISTS (SELECT 1 FROM orders o LEFT JOIN customers c ON c.id = o.customer_id WHERE c.id IS NULL)
