-- Insert test events for Confluent Cloud CDC testing
DO $$
DECLARE
  i INTEGER;
BEGIN
  FOR i IN 1..5 LOOP
    INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
    VALUES (
      'confluent-test-' || i,
      'user.event',
      'CREATE',
      NOW() - INTERVAL '1 minute' * i,
      NOW() - INTERVAL '1 minute' * i,
      jsonb_build_object('test_id', i, 'timestamp', extract(epoch from now()), 'source', 'confluent_test')
    );
  END LOOP;
END $$;

-- Verify inserted events
SELECT id, event_name, event_type, created_date, saved_date, header_data
FROM event_headers
WHERE id LIKE 'confluent-test-%'
ORDER BY created_date;
