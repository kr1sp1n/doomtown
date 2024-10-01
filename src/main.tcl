package require uuid
package require sqlite3
package require sha256

set script_path [ file dirname [ file normalize [ info script ] ] ]

source $script_path/wapp.tcl
source $script_path/utils.tcl

# Default port:
set port 8080

# Default db file:
set dbfile $script_path/../doomtown.sqlite

# Default path to files:
set files_path $script_path/../files

# Default admin key:
set admin_key ""

# Parse start arguments:
set n [llength $argv]
for {set i 0} {$i<$n} {incr i} {
  set term [lindex $argv $i]
  if {[string match --* $term]} {set term [string range $term 1 end]}
  switch -glob -- $term {
    -port {
      incr i;
      set port [lindex $argv $i]
    }
    -db {
      incr i;
      set dbfile [lindex $argv $i]
    }
    -files {
      incr i;
      set files_path [lindex $argv $i]
    }
    -admin {
      incr i;
      set admin_key [lindex $argv $i]
    }
  }
}

if {$admin_key eq ""} {
  puts "WARNING: No admin key set."
}

# Setup subdirs in files path:
set upload_path $files_path/upload
set static_path $files_path/static
file mkdir $upload_path
file mkdir $static_path

# Args for wapp server:
set wapp_args [list --server $port]

sqlite3 db $dbfile
# Enable otherwise "ON DELETE CASCADE" will not work:
db eval "PRAGMA foreign_keys = ON;"

proc setup-db {} {
  global script_path
  set fp [open "$script_path/schema.sql" r]
  set schema [read $fp]
  close $fp
  db eval $schema
}

GET /contact {
  layout {
    wapp-subst {<h2>Kontakt</h2>}
    wapp-trim {
      <p>Krispin <a href="mailto:krispin@posteo.de">krispin@posteo.de</a></p>
    }
  }
}

GET /files {
  layout {
    wapp-allow-xorigin-params
    wapp-subst {<h2>Dateien</h2>}
    set query "SELECT id, name, created_at FROM files"
    set search [wapp-param search]
    if {$search != ""} {
      set query "$query WHERE name LIKE '%$search%'"
    }
    # Search form:
    wapp-trim {
      <form method="GET">
        <input type="text" name="search" value="%html($search)"/>
        <input type="submit" value="Suchen" />
      </form>
    }
    wapp-subst {<ul>}
    set query "$query ORDER BY created_at DESC"
    db eval $query {
      wapp-trim {
        <li>%html($created_at) <a href="%url(/files/$id)">%html($name)</a></li>
      }
    }
    wapp-subst {</ul>}
  }
}

GET /apps {
  layout {
    wapp-subst {<h2>Programme</h2>}
    wapp-trim {
      <p>Ein Programm ist eine HTML-Datei. Die Datei kann Javascript und CSS enthalten.</p>
    }
    wapp-subst {<ul>}
    set query "SELECT id, name, title, description FROM files WHERE type = 'text/html' ORDER BY name ASC"
    db eval $query {
      set display $name
      if {$title != ""} {
        set display $title
      }
      if {$description != ""} {
        set description " - $description"
      }
      wapp-trim {
        <li><a href="%url(/files/raw/$id)" target="_blank">%html($display)</a>%html($description)</li>
      }
    }
    wapp-subst {</ul>}
  }
}

POST /files/update {
  set file_id [wapp-param file_id]
  set title [wapp-param title]
  set description [wapp-param description]
  set row [db eval "UPDATE files SET title = '$title', description = '$description' WHERE id = '$file_id'"]
  puts $row
  # lassign $row id name path
  # file delete -force $path
  # db eval "DELETE FROM files WHERE id == '$file_id'"
  wapp-redirect /files/$file_id
}

POST /files/delete {
  set file_id [wapp-param file_id]
  set row [db eval "SELECT id,name,path FROM files WHERE id == '$file_id'"]
  lassign $row id name path
  file delete -force $path
  db eval "DELETE FROM files WHERE id == '$file_id'"
  wapp-redirect /files
}

GET /files/raw/:id {
  # TODO: secure with better CSP
  wapp-content-security-policy off
  set file_id [dict get [wapp-param PATH_PARAMS] id]
  set row [get-file $file_id]
  if {[llength $row] == 0} {
    wapp-subst {<p>File not found.</p>}
    return
  } else {
    lassign $row id name title description type path tags
    # Response raw file:
    wapp-reset
    wapp-mimetype $type
    wapp-unsafe [loadFile $path]
  }
}

# Save apps:
POST /files/raw/:id {
  set file_id [dict get [wapp-param PATH_PARAMS] id]
  set row [get-file $file_id]
  if {[llength $row] == 0} {
    wapp-subst {<p>File not found.</p>}
    return
  } else {
    lassign $row id name title description type path tags
    set content [wapp-param file]
    if {$content != ""} {
      update-raw-file $file_id $content
    }
  }
}

GET /files/:id {
  layout {
    wapp-allow-xorigin-params
    set file_id [dict get [wapp-param PATH_PARAMS] id]
    set row [get-file $file_id]
    if {[llength $row] == 0} {
      wapp-subst {<p>Datei nicht gefunden.</p>}
      return
    } else {
      lassign $row id name title description type path tags
      # Show file details:
      wapp-subst {<h2>Datei</h2>}
      wapp-trim {
        <form method="POST" action="/files/update">
          <input type="hidden" name="file_id" value="%html($file_id)"/>
          <p>
            Name: %html($name)<br/>
            Typ: %html($type)<br/><br/>
            Titel:<br/>
            <input name="title" type="text" value="%html($title)"/><br/>
            Beschreibung:<br/>
            <textarea name="description">%html($description)</textarea><br/><br/>
            <input type="submit" value="Speichern" />
          </p>
        </form>
      }
      wapp-subst {<p>Stichwörter:&nbsp;}
      foreach {tag} [split [lsort $tags] " "] {
        wapp-trim {
          <a href="">%html($tag)</a>&nbsp;
        }
      }
      wapp-subst {</p>}
      wapp-trim {
        <form method="POST" action="/tags">
          <input type="hidden" name="file_id" value="%html($file_id)"/>
          <input type="text" name="tags" value=""/>
          <input type="submit" value="Stichwörter hinzufügen" />
          <p>Es können mehrere Stichwörter durch Leerzeichen getrennt eingegeben werden.</p>
        </form>
      }
      if {[is_admin]} {
        wapp-trim {
          <form method="POST" action="/files/delete">
            <input type="hidden" name="file_id" value="%html($file_id)"/>
            <input class="red" type="submit" value="Datei löschen" />
          </form>
        }
      }
      wapp-trim {
        <p>
          <a href="/files/raw/%html($file_id)" target="_blank">Datei anschauen</a>
        </p>
      }
      if {[string match image/* $type]} {
        wapp-subst {<a href="/files/raw/%html($file_id)">}
          imageAsBase64 $type [loadFile $path]
        wapp-subst {</a>}
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

GET /tags {
  layout {
    wapp-subst {<h2>Stichwörter</h2>}
    set query "SELECT id, name FROM tags"
    set search [wapp-param search]
    if {$search != ""} {
      set query "$query WHERE name LIKE '%$search%'"
    }
    # Search form:
    wapp-trim {
      <form method="GET">
        <input type="text" name="search" value="%html($search)"/>
        <input type="submit" value="Suchen" />
      </form>
    }
    wapp-subst {<ul>}
    set query "$query ORDER BY name ASC"
    db eval $query {
      wapp-trim {
        <li><a href="%url(/tags/$id)">%html($name)</a></li>
      }
    }
    wapp-subst {</ul>}
  }
}

proc is_admin {} {
  global admin_key
  # puts [wapp-debug-env]
  return [expr {$admin_key eq [wapp-param admin]}]
}

GET /tags/:id {
  layout {
    wapp-allow-xorigin-params
    set tag_id [dict get [wapp-param PATH_PARAMS] id]

    if {[is_admin]} {
      wapp-trim {
        <form method="POST" action="/tags/delete">
          <input type="hidden" name="tag_id" value="%html($tag_id)"/>
          <input type="submit" class="red" value="Stichwort löschen" />
        </form>
      }
    }

    set query "
      SELECT tags.name, files.id, files.name
      FROM tags
      JOIN files_tags ON tags.id = files_tags.tag_id 
      JOIN files ON files.id = files_tags.file_id
      WHERE tags.id == '$tag_id'
    "
    set rows [db eval $query]
    if {[llength $rows] == 0} {
      wapp-subst {<p>Keine Dateien zu diesem Stichwort gefunden.</p>}
    } else {
      set tag_name ""
      wapp-trim {
        <h2>Stichwort '%html([lindex $rows 0])'</h2>
      }
      wapp-subst {<p>Dateien mit diesem Stichwort:</p>}
      wapp-subst {<ul>}
      foreach {tag_name file_id file_name} $rows {
        wapp-trim {
          <li><a href="%url(/files/$file_id)">%html($file_name)</a></li>
        }
      }
      wapp-subst {</ul>}
    }
  }
}

POST /tags/delete {
  set tag_id [wapp-param tag_id]
  set row [db eval "SELECT id,name FROM tags WHERE id == '$tag_id'"]
  lassign $row id name
  db eval "DELETE FROM tags WHERE id == '$tag_id'"
  wapp-redirect /tags
}

POST /tags {
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
}

GET /upload {
  layout {
    wapp-trim {
      <h2>Upload</h2>
      <form method="POST" enctype="multipart/form-data">
        <p>
          Datei auswählen: <input type="file" name="file" />
        </p>
        <p>
          <input type="submit" value="Hochladen" />
        </p>
      </form>
    }
  }
}

POST /upload {
  # File upload query parameters come in three parts:  The *.mimetype,
  # the *.filename, and the *.content.
  set mimetype [wapp-param file.mimetype {}]
  set filename [wapp-param file.filename {}]
  set content [wapp-param file.content {}]
  if {$filename!=""} {
    set file_id [add-file $filename $mimetype $content]
    if {$file_id!=""} {
      # add first part of mimetype as tag otherwise group_concat will not work:
      add-tag [lindex [split $mimetype '/'] 0] $file_id
      wapp-redirect "/files/$file_id"
    }
  }
}

proc wapp-default {} {
  layout {
    wapp-trim {
      <h2>Willkommen in Doomtown</h2>
      <p>
        Dies ist ein lokales Netzwerk, ohne Verbindung zum Internet.
        Es wird nur über einen mobilen WLAN-Router bereitgestellt.
        Der Router taucht ab und zu einfach so in der Stadt auf.
        Du kannst anonym Dateien hochladen und sie bleiben für die Nachwelt erhalten.
        Schreibe Texte, lade Bilder hoch oder suche nach Dateien von anderen Menschen.
      </p>
    }
  }
}

proc get-file {file_id} {
  # Get file details and will only work if at least 1 tag is present:
  set row [db eval "
    SELECT files.id, files.name, files.title, files.description, files.type, files.path, GROUP_CONCAT(tags.name,' ') AS tags
    FROM files
    JOIN files_tags ON files.id = files_tags.file_id 
    JOIN tags ON tags.id = files_tags.tag_id
    WHERE files.id == '$file_id'
    GROUP BY files.id
    ORDER BY files.id;
  "]
  return $row
}

proc update-raw-file {id content} {
  global upload_path
  set hash [sha2::sha256 $content]
  set now [clock seconds]
  set updated_at [clock format $now -gmt 1 -format "%Y-%m-%dT%H:%M:%SZ"]
  set row [get-file $id]
  lassign $row id name title description type path tags
  set file [open $path "w"]
  fconfigure $file -translation binary
  puts -nonewline $file $content
  close $file
  db eval "UPDATE files SET updated_at = '$updated_at', hash = '$hash' WHERE id = '$id';"
  return $id
}

proc add-file {name type content} {
  global upload_path
  set id [uuid::uuid generate]
  set hash [sha2::sha256 $content]

  set exist [db eval "SELECT id FROM files WHERE hash == '$hash'"]
  if {[string trim $exist] != ""} {
    wapp-trim {
      <p>File %html($name) already exists.</p>
    }
    return
  } else {
    set file_path "$upload_path/$id"
    set extension [split $name .]
    if { [llength $extension ] > 0 } {
      set extension [lindex $extension end]
    }
    set file_path "$file_path.$extension"
    set file [open $file_path "w"]
    fconfigure $file -translation binary
    puts -nonewline $file $content
    close $file
    db eval "INSERT INTO files (id,name,type,hash,path) VALUES ('$id','$name','$type','$hash','$file_path')"
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
      <div class="app">
        <div class="header">
          <img class="logo" src="/header.gif" alt="DOOMTOWN" />
          <header>
            <h1>Lokales Netzwerk Cottbus</h1>
            <nav>
              <ul>
                <li><a href="/">Index</a></li>
                <li><a href="/files">Dateien</a></li>
                <li><a href="/apps">Programme</a></li>
                <li><a href="/tags">Stichwörter</a></li>
                <li><a href="/upload">Upload</a></li>
                <li><a href="/contact">Kontakt</a></li>
              </ul>
            </nav>
          </header>
        </div>
  }
}

proc footer {} {
  wapp-trim {
      <div class="footer">
        <p class="small">
          Wir behalten uns das Recht vor, Inhalte zu löschen, 
          die diskriminierend, rassistisch oder jugendgefährdend sind.
        </p>
      </div>
    </div>
    </body>
    </html>
  }
}

proc layout {content} {
  wapp-content-security-policy {default-src 'self'; img-src 'self' data:}
  header
  wapp-subst {<div class="content"><div class="wrap">}
  eval $content
  wapp-subst {</div></div>}
  footer
}

proc show-text {content} {
  wapp-trim {
    <p>
      <pre>
        %html([encoding convertfrom utf-8 $content])
      </pre>
    </p>
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

proc loadFile {path} {
  set file [open $path r]
  fconfigure $file -translation binary
  set content [read $file]
  close $file
  return $content
}

proc imageAsBase64 {type content} {
  set b64 [binary encode base64 $content]
  wapp-trim {
    <img class="image" src='data:%html($type);base64,%html($b64)'>
  }
}

proc wapp-page-style.css {} {
  wapp-mimetype text/css
  wapp-cache-control max-age=3600
  wapp-unsafe {
    * {
      margin: 0;
      padding: 0;
    }

    body {
      background: #999;
      font-family: monospace, courier;
      font-size: 1em;
    }

    .small {
      font-size: 0.6em;
    }

    input[type=button], input[type=submit], input[type=reset], input[type=reset], button {
      padding: 0.5em 1em;
      background-color: #009966;
      border: 1px solid #666;
      color: white;
      text-decoration: none;
      cursor: pointer;
    }

    input[type=text] {
      line-height: 2em;
      padding-left: 0.2em;
    }

    input[type=submit].red {
      background-color: #f00;
    }

    .app {
      width: 80%;
      background: #fff;
      margin: 0 auto 0 auto;
      border-left: 2px solid black;
      border-right: 2px solid black;
      border-bottom: 2px solid black;
    }

    .header {
      padding: 1em 0 0 0;
    }

    nav ul {
      list-style: none;
      padding: 1em 1em 0 1em;
    }

    nav li {
      display: inline;
      margin-right: 1em;
    }

    .logo {
      display: block;
      margin-left: auto;
      margin-right: auto;
      image-rendering: pixelated;
      width: 60%;
      max-width: 600px;
    }

    .footer {
      padding: 2em 1em 1em 1em;
    }

    h1 {
      font-size: 1.3em;
    }

    @media (max-width: 800px ) {
      body {
        font-size: 1.1em;
      }

      .app {
        width: 100%;
        margin: 0;
        border: 0px;
      }

      .logo {
        width: 80%;
      }
    }

    .header h1 {
      text-align: center;
      margin-top: 1em;
      color: #666;
    }

    .content .wrap {
      padding: 1em 1em 0 1em;
    }

    .content p {
      padding: 1em 0 1em 0;
    }

    .content form {
      padding: 1em 0 1em 0;
    }

    .content ul {
      margin: 1em 0 0 1em;
    }

    .content pre {
      white-space: pre-wrap;
      font-size: 1.2em;
    }

    .content .image {
      width: 50%;
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

proc wapp-page-header.gif {} {
  wapp-mimetype image/gif
  wapp-cache-control max-age=3600
  wapp-unsafe [binary decode base64 {
    R0lGODlhGAEwAPEAAAAAAP///yZFySZFySH5BAEAAAIALAAAAAAYATAAAAL/hI9p
    we0PI1NI2kfPxXtnIH3iuEBi14BqAKIpFbpWxpKV3JG4o6PlXqNFbMQbZiRbrZKw
    YQs4aRZ/UJ4NSPRRXUjntHcEX5SsndC0xZ2/VWuW+R5r4J/Qtxu+5spLbhOd5qfg
    Fgd1J1jkYaSIl3c3CJg4xlem9udoeBlUaHnIyDaTkKMX+bj44jlD+aQFWcqKeLpJ
    Spfq9RgqmitGaBroC8uzaqaJKvt5DBqLe2tq5+rY2Ov8astBVjtXHSwHPR1Y2aq7
    /TweDQ58kg1efjyrfc696678LX92tIxeHOVtTA8jC75R/rqZs9cOHsGD/zTUiZdw
    nzyIzRQ2lMiwn64e/wORWTQIsOA7dhUx3nh48R6/TQtDZhypUuQalB1Bfpx3sybM
    Ti9nXtIJ1F3KiDF7rsSHdCVRni6b3lxakhXNo1SF7owKlRzWaRT1TdyqNaw4p1se
    BpUp8qpYhGC7GlvrkSRcjWS/zlWbUkVVo2j78v1b10nblk8HDzVs0+THemzvAh2W
    1a0wbOvsXqPENOdeq44hRz0LWHNaMkUDx6A8tvAQz6kVu7bc2ATreJtFh0Y3O7bu
    FLnjwuaNunVp25wlA8eME7Tpu8OGv1YV3LeZ3smdW8/MjrTv29cRN68eeTJyr2qo
    g/euM/zxPom5q6f7VDt6pfLJl4/e/j1ewtnN2/8jDuBzq+EHn4CyEXgeF/7N51dx
    u02w4H/dOUYfdcrFF+GDkyDIoHuVQTfedqeFqOGFBl7GnnH5fZiEeSb+BiGC6Q1I
    ongpHkZhgxgSOCNz3oF4Y4ETKsijUiMG+Z1+LyrpopE+PoliODm+dKSUKgJpZZRD
    llhbf0Wm9WOYNCK55H017rcHj03qeGKJa1Ip5pVVTlQmkWeiueGdSU65nJz1yRmn
    hlhuiaOdZDp54Jl/Xlkno286WCh/MO7Jp2paJuiDf4tGyqmQ+lEqaKCd5nkom5OC
    OuqgTMrYJaGeihqjnrDiSWtNv7SKnauxluphpW2mKSugvhIqS6OSrnqnsaPxKktq
    ltKxOGw0jCLK5WgW4tphn5lyCGW1veLFLKZusmqqktga6uyK9kUr5A/hmmvtl996
    qy2wSH6abYAtcHSucMjeG27A1K6XrrjPRitQv8f+uOmr7D6M7qQ9TmtqOrq+Z7F1
    UxC18awTh7pNxyGngy9cGbfHCW20CMsyyCPzIuFGK7us28nbSfMZzjSnOmu7Oudl
    Dsw7OwwTY9WpIynSJbfM89EocVzs0x7/YbNXHwMNJtELr0tMyi9f3DRFVVeWdc4O
    Xq31wVjMbLZN/n44dq6Qfs311m9XIXTOC9V9M8ltKL022mjTuvTNZPsBrXAFAAA7
  }]
}


setup-db
wapp-start $wapp_args