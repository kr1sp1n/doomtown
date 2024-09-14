package require sqlite3

lassign $argv dbfile1 dbfile2

sqlite3 db1 $dbfile1
sqlite3 db2 $dbfile2

# Apply schema:
set fp [open "src/schema.sql" r]
set schema [read $fp]
close $fp

db1 eval $schema
db2 eval $schema

db1 eval "
  INSERT INTO files (id,name, path, hash, type) VALUES ('1','image1','/image1.png', '123', 'png');
  INSERT INTO tags (id,name) VALUES ('1','image');
  INSERT INTO files_tags (file_id,tag_id) VALUES ('1','1');
"

db2 eval "
  INSERT INTO files (id,name, path, hash, type) VALUES ('2','image2','/image2.png', '456', 'png');
  INSERT INTO tags (id,name) VALUES ('2','image');
  INSERT INTO files_tags (file_id,tag_id) VALUES ('2','2');
"

puts "TEST: merge $dbfile2 into $dbfile1"

source "src/db_merge.tcl"

set row [db1 eval "SELECT id, name FROM tags WHERE id = '2'"]
if {[llength $row] == 0} {
  puts "FAIL: row == 0"
  exit 1
} else {
  lassign $row id name
  if {$id == "2" && $name == "image"} {
    puts "SUCCESS: id of tag '$name' is '$id'"
  } else {
    puts "FAIL: id of tag '$name' is '$id'"
  }
}