BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS "files" (
  -- File hash is id:
  "hash" TEXT NOT NULL PRIMARY KEY,
  "name" TEXT NOT NULL,
  "title" TEXT,
  "description" TEXT,
  "extension" TEXT,
  -- MIME type:
  "type" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE IF NOT EXISTS "tags" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "name" TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS "files_tags" (
  "file_hash" TEXT NOT NULL REFERENCES files(hash) ON UPDATE CASCADE ON DELETE CASCADE,
  "tag_id" TEXT NOT NULL REFERENCES tags(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY(file_hash, tag_id)
);

COMMIT;