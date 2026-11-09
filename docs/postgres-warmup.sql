-- PostgreSQL Warmup Exercises

-- 1. Create Events Table
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    source VARCHAR(100) NOT NULL,
    external_id VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL,
    payload JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_source_external UNIQUE (source, external_id)
);

-- 2. Insert Duplicate Test (Error demonstration)
-- INSERT INTO events (source, external_id, status, payload) 
-- VALUES ('github', 'evt_999', 'pending', '{"event": "push"}');

-- 3. INSERT ... ON CONFLICT DO NOTHING
INSERT INTO events (source, external_id, status, payload) 
VALUES ('github', 'evt_999', 'processed', '{"event": "push"}')
ON CONFLICT (source, external_id) DO NOTHING;

-- 4. Insert Rows and Run GROUP BY
INSERT INTO events (source, external_id, status, payload) VALUES
('github', 'ext_001', 'pending', '{"action": "open"}'),
('gitlab', 'ext_002', 'completed', '{"action": "merge"}'),
('github', 'ext_003', 'failed', '{"action": "close"}'),
('bitbucket', 'ext_004', 'pending', '{"action": "open"}'),
('gitlab', 'ext_005', 'completed', '{"action": "push"}'),
('github', 'ext_006', 'pending', '{"action": "open"}')
ON CONFLICT (source, external_id) DO NOTHING;

SELECT status, COUNT(*) AS count 
FROM events 
GROUP BY status;

-- 5. Notes on Concurrency:
-- A unique constraint enforces atomicity at the database index level, 
-- whereas check-then-insert logic in application code suffers from race conditions 
-- where two concurrent requests check simultaneously, see no existing record, 
-- and both attempt to insert.