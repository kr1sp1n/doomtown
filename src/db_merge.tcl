# This will merge sqlite db2 into db1.
# It can handle the same tag names in both dbs by
# updating the tags.id on conflict through cascading.

package require sqlite3

if { $argc < 2 } {
  puts "Merge sqlite db2 into db1."
  puts "usage: db_merge.tcl db1 db2"
  exit 1
}

lassign $argv dbfile1 dbfile2

sqlite3 db $dbfile1

db eval "
  PRAGMA foreign_keys = ON;
  ATTACH '$dbfile2' AS db2;
  BEGIN TRANSACTION;

  INSERT OR IGNORE INTO files SELECT * FROM db2.files;
  INSERT INTO tags SELECT * FROM db2.tags WHERE true ON CONFLICT (name) DO UPDATE SET id = excluded.id;
  INSERT OR IGNORE INTO files_tags SELECT * FROM db2.files_tags;

  COMMIT;
  DETACH db2;
"