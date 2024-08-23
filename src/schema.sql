BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS "files" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "name" TEXT NOT NULL,
  "host" TEXT,
  "path" TEXT NOT NULL,
  "hash" TEXT NOT NULL UNIQUE,
  -- MIME type:
  "type" TEXT NOT NULL,
  "created_at" TEXT NOT NULL,
  "updated_at"  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "tags" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "name" TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS "files_tags" (
  "file_id" TEXT NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  "tag_id" TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY(file_id, tag_id)
);

COMMIT;