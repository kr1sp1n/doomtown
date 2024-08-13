BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS "files" (
  "id" TEXT,
  "name" TEXT,
  "host" TEXT,
  "path" TEXT,
  "hash" TEXT,
  -- MIME type:
  "type" TEXT,
  "created_at" TEXT,
  "updated_at"  TEXT
);
COMMIT;