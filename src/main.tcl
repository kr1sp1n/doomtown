set script_path [ file dirname [ file normalize [ info script ] ] ]

source $script_path/wapp.tcl

package require uuid
package require sqlite3
package require sha256
package require Thread

proc wapp-deliver-file-content { wapp chan } {
  set mimetype [dict get $wapp .mimetype]
  set filepath [dict get $wapp .filepath]

  thread::detach $chan

  thread::create [subst -nocommands {
    thread::attach $chan
    
    set contentLength [file size $filepath]
    set inchan [open $filepath rb]
    puts $chan "Content-Type: $mimetype\r"
    puts $chan "Content-Length: \$contentLength\r"
    puts $chan "\r"
    fcopy \$inchan $chan
    close \$inchan
    flush $chan
    close $chan
  }]
}

sqlite3 db $script_path/../doomtown.sqlite

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
    db eval "INSERT INTO files (id,name,type,hash,path,created_at) VALUES ('$id','$name','$type','$hash','$file_path','$created_at')"
  }
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

proc wapp-page-style.css {} {
  wapp-mimetype text/css
  wapp-cache-control max-age=3600
  wapp-trim {
    body {
      font-family: monospace, courier;
    }
  }
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
      add-file $filename $mimetype $content
      show-file-info $filename $mimetype
      if {[string match image/* $mimetype]} {
        # If the mimetype is an image, display the image using an
        # in-line <img> mark.  Note that the content-security-policy
        # must be changed to allow "data:" for type img-src in order
        # for this to work.
        imageAsBase64 $mimetype $content
      }
      if {[string match text/* $mimetype]} {
        # Just show it as text:
        show-text $content
      }
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

proc wapp-page-files {} {
  wapp-content-security-policy {default-src 'self'; img-src 'self' data:}
  layout {
    # Check if /files/$id:
    set file_id [wapp-param PATH_TAIL]
    set static 0
    if { $file_id eq ""} {
      # List files:
      wapp-subst {<h2>Dateien</h2><ul>}
      # wapp-subst {<pre>%html([wapp-debug-env])</pre>}
      db eval {SELECT id, name, created_at FROM files ORDER BY created_at DESC} {
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
      # Show file details:
      set row [db eval "SELECT id,name,type,path FROM files WHERE id == '$file_id'"]
      if {[llength $row] == 0} {
        wapp-subst {<p>File not found.</p>}
      } else {
        lassign $row id name type path
        if {$static} {
          wapp-reset
          wapp-mimetype $type

          return
        }
        show-file-info $name $type
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

setup-db
wapp-start $argv