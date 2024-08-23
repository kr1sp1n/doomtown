set script_path [ file dirname [ file normalize [ info script ] ] ]

source $script_path/wapp.tcl

package require uuid
package require sqlite3
package require sha256

# package require Thread

# TODO: rewrite

# proc wapp-deliver-file-content { wapp chan } {
#   set mimetype [dict get $wapp .mimetype]
#   set filepath [dict get $wapp .filepath]

#   thread::detach $chan

#   thread::create [subst -nocommands {
#     thread::attach $chan
    
#     set contentLength [file size $filepath]
#     set inchan [open $filepath rb]
#     puts $chan "Content-Type: $mimetype\r"
#     puts $chan "Content-Length: \$contentLength\r"
#     puts $chan "\r"
#     fcopy \$inchan $chan
#     close \$inchan
#     flush $chan
#     close $chan
#   }]
# }

sqlite3 db $script_path/../doomtown.sqlite
# Enable otherwise "ON DELETE CASCADE" will not work:
db eval "PRAGMA foreign_keys = ON;"

proc setup-db {} {
  global script_path
  set fp [open "$script_path/schema.sql" r]
  set schema [read $fp]
  close $fp
  db eval $schema
}

proc add-file {name type content} {
  global script_path
  set id [uuid::uuid generate]
  set hash [sha2::sha256 $content]

  set now [clock seconds]
  set created_at [clock format $now -gmt 1 -format "%Y-%m-%dT%H:%M:%SZ"]

  set exist [db eval "SELECT id FROM files WHERE hash == '$hash'"]
  if {[string trim $exist] != ""} {
    wapp-trim {
      <p>File %html($name) already exists.</p>
    }
    return
  } else {
    set upload_path "files/uploaded"
    set file_path "$upload_path/$id"
    set extension [split $name .]
    if { [llength $extension ] > 0 } {
      set extension [lindex $extension end]
    }
    set file_path "$file_path.$extension"
    set file [open "$script_path/../$file_path" "w"]
    fconfigure $file -translation binary
    puts -nonewline $file $content
    close $file
    db eval "INSERT INTO files (id,name,type,hash,path,created_at,updated_at) VALUES ('$id','$name','$type','$hash','$file_path','$created_at','$created_at')"
    return $id
  }
}

proc add-tag {name file_id} {
  # check if tag with name already exists:
  set tag_id [db eval {SELECT id FROM tags WHERE name == :name}]
  if {$tag_id == ""} {
    set tag_id [uuid::uuid generate]
    db eval "
      BEGIN TRANSACTION;
      INSERT INTO tags (id,name) VALUES ('$tag_id','$name');
      COMMIT;
    "
  }
  # Insert but ignore if already exists:
  db eval "
    BEGIN TRANSACTION;
    INSERT OR IGNORE INTO files_tags (file_id,tag_id) VALUES ('$file_id','$tag_id');
    COMMIT;
  "
  return $tag_id
}

proc header {} {
  wapp-trim {
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta http-equiv="content-type" content="text/html; charset=UTF-8">
      <link href="%url([wapp-param SCRIPT_NAME]/style.css)" rel="stylesheet">
      <title>doomtown</title>
    </head>
    <body>
    <h1><a href="/">doomtown</a></h1>
    <ul>
      <li><a href="/files">Dateien</a></li>
      <li><a href="/upload">Upload</a></li>
    </ul>
  }
}

proc footer {} {
  wapp-trim {
    </body>
    </html>
  }
}

proc layout {content} {
  header
  eval $content
  footer
}

proc show-text {content} {
  wapp-trim {
    <pre>
      %html([encoding convertfrom utf-8 $content])
    </pre>
  }
}

proc show-audio {type path} {
  wapp-trim {
    <audio controls>
      <source src="/%url($path)" type="%html($type)">
      Your browser does not support the audio element.
    </audio>
  }
}

proc show-file-info {name type} {
  wapp-subst {<p>Name: %html($name)<br/>Type: %html($type)</p>}
}

proc wapp-page-upload {} {
  wapp-content-security-policy {default-src 'self'; img-src 'self' data:}
  layout {
    wapp-trim {
      <h2>Upload</h2>
      <p>
        <form method="POST" enctype="multipart/form-data">
          Datei auswählen: <input type="file" name="file"><br/>
          <input type="checkbox" name="showenv" value="1">Show CGI Environment<br>
          <input type="submit" value="Hochladen">
        </form>
      </p>
    }
    if {[wapp-param showenv 0]} {
      wapp-trim {
        <h1>Wapp Environment</h1>
        <pre>%html([wapp-debug-env])</pre>
      }
    }
    # File upload query parameters come in three parts:  The *.mimetype,
    # the *.filename, and the *.content.
    set mimetype [wapp-param file.mimetype {}]
    set filename [wapp-param file.filename {}]
    set content [wapp-param file.content {}]
    if {$filename!=""} {
      set file_id [add-file $filename $mimetype $content]
      # add first part of mimetype as tag otherwise group_concat will not work:
      add-tag [lindex [split $mimetype '/'] 0] $file_id
      wapp-redirect "/files/$file_id"
    }
  }
}

proc wapp-before-dispatch-hook {} {
  # puts [wapp-debug-env]
}

proc loadFile {path} {
  global script_path
  set file [open "$script_path/../$path" r]
  fconfigure $file -translation binary
  set content [read $file]
  close $file
  return $content
}

proc imageAsBase64 {type content} {
  set b64 [binary encode base64 $content]
  wapp-trim {
    <p>
      <img src='data:%html($type);base64,%html($b64)'>
    </p>
  }
}

proc wapp-page-tags {} {
  if {[wapp-param REQUEST_METHOD] eq "POST"} {
    set file_id [wapp-param file_id]
    if { $file_id == ""} {
      layout {
        wapp-subst {No file_id given.}
      }
    } else {
      set tags [split [wapp-param tags] " "]
      foreach {tag} $tags {
        add-tag $tag $file_id
      }
      wapp-redirect "/files/$file_id"
    }
    # wapp-subst {<pre>%html([wapp-debug-env])</pre>}
  } else {
    layout {
      wapp-subst {TODO: Show tag list.}
    }
  }
}

# DELETE file
proc wapp-page-delete {} {
  global script_path
  set file_id [wapp-param PATH_TAIL]
  set row [db eval "SELECT id,name,path FROM files WHERE id == '$file_id'"]
  lassign $row id name path
  file delete -force "$script_path/../$path"
  db eval "DELETE FROM files WHERE id == '$file_id'"
  wapp-redirect /files
}

proc wapp-page-files {} {
  wapp-content-security-policy {default-src 'self'; img-src 'self' data:}
  wapp-allow-xorigin-params
  layout {
    # Check if /files/$id:
    set file_id [wapp-param PATH_TAIL]
    set static 0
    if { $file_id eq ""} {
      # List files:
      wapp-subst {<h2>Dateien</h2><ul>}
      # wapp-subst {<pre>%html([wapp-debug-env])</pre>}
      set query "SELECT id, name, created_at FROM files"
      set search [wapp-param search]
      if {$search != ""} {
        set query "$query WHERE name LIKE '%$search%'"
      }
      # Search form:
      wapp-trim {
        <p>
          <form method="GET">
            <input type="text" name="search" value="%html($search)"/>
            <input type="submit" value="Suchen" />
          </form>
        </p>
      }
      set query "$query ORDER BY created_at DESC"
      db eval $query {
        wapp-trim {
          <li>%html($created_at) <a href="%url(/files/$id)">%html($name)</a></li>
        }
      }
      wapp-subst {</ul>}
    } else {
      if {[string match uploaded/* $file_id]} {
        # Extract file id:
        set file_id [lindex [split [lindex [split $file_id .] end-1] /] end]
        set static 1
      }

      # Get file details and will only work if at least 1 tag is present:
      set row [db eval "
        SELECT files.id, files.name, files.type, files.path, GROUP_CONCAT(tags.name,' ') AS tags
        FROM files
        JOIN files_tags ON files.id = files_tags.file_id 
        JOIN tags ON tags.id = files_tags.tag_id
        WHERE files.id == '$file_id'
        GROUP BY files.id
        ORDER BY files.id;
      "]
      if {[llength $row] == 0} {
        wapp-subst {<p>File not found.</p>}
      } else {
        lassign $row id name type path tags
        # Response file:
        if {$static} {
          wapp-reset
          wapp-mimetype $type
          wapp-unsafe [loadFile $path]
          return
        }
        # Show file details:
        wapp-subst {<h2>Datei</h2>}
        show-file-info $name $type
        wapp-trim {
          <p>
            <form method="POST" action="/tags">
              <input type="hidden" name="file_id" value="%html($file_id)"/>
              <input type="text" name="tags" value="%html([lsort $tags])"/>
              <input type="submit" value="Tags speichern" />
            </form>
          </p>
        }
        wapp-trim {
          <p><a href="/delete/%url($file_id)">Datei löschen</a></p>
        }
        if {[string match image/* $type]} {
          imageAsBase64 $type [loadFile $path]
        }
        if {[string match text/* $type]} {
          set content [loadFile $path]
          show-text $content
        }
        if {[string match audio/* $type]} {
          show-audio $type $path
        }
      }
    }
  }
}

proc wapp-default {} {
  layout {
    wapp-subst {<h2>Hello, World!</h2>}
  }
}

proc wapp-page-style.css {} {
  wapp-mimetype text/css
  wapp-cache-control max-age=3600
  wapp-trim {
    body {
      font-family: monospace, courier;
    }
  }
}

proc wapp-page-favicon.ico {} {
  wapp-mimetype image/gif
  wapp-cache-control max-age=3600
  wapp-unsafe [binary decode hex {
    47494638396108000800f10200000000ffffffffff0000000021f90405080002
    002c000000000800080000020c448c718b99ccdc828d2a090a003b
  }]
}

setup-db
wapp-start $argv