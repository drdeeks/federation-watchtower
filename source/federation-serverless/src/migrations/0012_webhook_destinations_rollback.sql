-- Rollback for 0012_webhook_destinations.sql. No inbound foreign keys
-- reference this table, so a straight drop is sufficient.

DROP TABLE IF EXISTS webhook_destinations;
