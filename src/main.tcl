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

# Default port:
set port 8080

# Default db file:
set dbfile $script_path/../doomtown.sqlite

# Default path to files:
set files_path $script_path/../files

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
  }
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

proc add-file {name type content} {
  global upload_path
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
      <div class="app">
        <div class="header">
          <picture>
            <source media="(max-width: 623px)" srcset="/doomtown_header_002_312px.png" />
            <source media="(min-width: 624px)" srcset="/doomtown_header_002_624px.png" />
            <img class="logo" src="/doomtown_header_002_624px.png" alt="DOOMTOWN" />
          </picture>
          <header>
            <h1>Lokales Netzwerk Cottbus</h1>
            <nav>
              <ul>
                <li><a href="/">Home</a></li>
                <li><a href="/files">Dateien</a></li>
                <li><a href="/upload">Upload</a></li>
              </ul>
            </nav>
          </header>
        </div>
  }
}

proc footer {} {
  wapp-trim {
      <div class="footer">
        <p></p>
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

proc show-file-info {name type} {
  wapp-subst {<p>Name: %html($name)<br/>Type: %html($type)</p>}
}

proc wapp-page-upload {} {
  layout {
    wapp-trim {
      <h2>Upload</h2>
      <form method="POST" enctype="multipart/form-data">
        Datei auswählen: <input type="file" name="file"><br/>
        <input type="checkbox" name="showenv" value="1">Show CGI Environment<br>
        <input type="submit" value="Hochladen">
      </form>
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
      if {$file_id!=""} {
        # add first part of mimetype as tag otherwise group_concat will not work:
        add-tag [lindex [split $mimetype '/'] 0] $file_id
        wapp-redirect "/files/$file_id"
      }
    }
  }
}

proc wapp-before-dispatch-hook {} {
  # puts [wapp-debug-env]
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
  set file_id [wapp-param PATH_TAIL]
  set row [db eval "SELECT id,name,path FROM files WHERE id == '$file_id'"]
  lassign $row id name path
  file delete -force $path
  db eval "DELETE FROM files WHERE id == '$file_id'"
  wapp-redirect /files
}

proc wapp-page-files {} {
  wapp-allow-xorigin-params
  layout {
    # Check if /files/$id:
    set file_id [wapp-param PATH_TAIL]
    set static 0
    if { $file_id eq ""} {
      # List files:
      wapp-subst {<h2>Dateien</h2>}
      # wapp-subst {<pre>%html([wapp-debug-env])</pre>}
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
        <ul>
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
          <form method="POST" action="/tags">
            <input type="hidden" name="file_id" value="%html($file_id)"/>
            <input type="text" name="tags" value="%html([lsort $tags])"/>
            <input type="submit" value="Tags speichern" />
          </form>
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
    wapp-subst {<h2>Willkommen in Doomtown.</h2>}
  }
}

proc wapp-page-style.css {} {
  wapp-mimetype text/css
  wapp-cache-control max-age=3600
  wapp-trim {
    * {
      margin: 0;
      padding: 0;
    }

    body {
      background: #999;
      font-family: monospace, courier;
      font-size: 14px;
      line-height: 16px;
    }

    .header {
      margin: 16px 0 0 0;
    }

    header {
      background: #fff;
      border-left: 2px solid black;
      border-right: 2px solid black;
      width: 624px;
      margin: 0 auto 0 auto;
    }

    nav ul {
      list-style: none;
      padding: 16px 16px 0 16px;
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
    }

    .content {
      background: #fff;
      border-left: 2px solid black;
      border-right: 2px solid black;
      width: 624px;
      margin: 0 auto 0 auto;
      min-height: 200px;
    }

    .footer {
      background: #fff;
      border-left: 2px solid black;
      border-right: 2px solid black;
      border-bottom: 2px solid black;
      width: 624px;
      margin: 0 auto 1em auto;
    }

    .footer p {
      padding: 16px 16px 16px 16px;
    }

    @media (max-width: 623px ) {
      body {
        font-size: 12px;
        line-height: 14px;
      }
      .content, .footer, header {
        width: 312px;
        border-left: 1px solid black;
        border-right: 1px solid black;
      }
      .footer {
        border-bottom: 1px solid black;
      }
      h1 {
        font-size: 14px;
      }
    }

    .header h1 {
      text-align: center;
      color: #666;
    }

    .content .wrap {
      padding: 16px 16px 0 16px;
    }

    .content p {
      padding: 1em 0 1em 0;
    }

    .content form {
      padding: 1em 0 1em 0;
    }

    .content ul {
      margin-left: 1em;
    }

    .content pre {
      width: 624px;
      white-space: pre-wrap;
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

proc wapp-page-doomtown_header_002_312px.png {} {
  wapp-mimetype image/png
  wapp-cache-control max-age=3600
  wapp-unsafe [binary decode hex {
    89504e470d0a1a0a0000000d4948445200000138000000400203000000f31783
    e10000000467414d410000b18f0bfc6105000000017352474200aece1ce90000
    00097048597300000ec400000ec401952b0e1b0000055c69545874584d4c3a63
    6f6d2e61646f62652e786d7000000000003c3f787061636b657420626567696e
    3d22efbbbf222069643d2257354d304d7043656869487a7265537a4e54637a6b
    633964223f3e0a3c783a786d706d65746120786d6c6e733a783d2261646f6265
    3a6e733a6d6574612f2220783a786d70746b3d22584d5020436f726520352e35
    2e30223e0a203c7264663a52444620786d6c6e733a7264663d22687474703a2f
    2f7777772e77332e6f72672f313939392f30322f32322d7264662d73796e7461
    782d6e7323223e0a20203c7264663a4465736372697074696f6e207264663a61
    626f75743d22220a20202020786d6c6e733a64633d22687474703a2f2f707572
    6c2e6f72672f64632f656c656d656e74732f312e312f220a20202020786d6c6e
    733a657869663d22687474703a2f2f6e732e61646f62652e636f6d2f65786966
    2f312e302f220a20202020786d6c6e733a746966663d22687474703a2f2f6e73
    2e61646f62652e636f6d2f746966662f312e302f220a20202020786d6c6e733a
    70686f746f73686f703d22687474703a2f2f6e732e61646f62652e636f6d2f70
    686f746f73686f702f312e302f220a20202020786d6c6e733a786d703d226874
    74703a2f2f6e732e61646f62652e636f6d2f7861702f312e302f220a20202020
    786d6c6e733a786d704d4d3d22687474703a2f2f6e732e61646f62652e636f6d
    2f7861702f312e302f6d6d2f220a20202020786d6c6e733a73744576743d2268
    7474703a2f2f6e732e61646f62652e636f6d2f7861702f312e302f7354797065
    2f5265736f757263654576656e7423220a202020657869663a506978656c5844
    696d656e73696f6e3d22333132220a202020657869663a506978656c5944696d
    656e73696f6e3d223634220a202020657869663a436f6c6f7253706163653d22
    31220a202020746966663a496d61676557696474683d22333132220a20202074
    6966663a496d6167654c656e6774683d223634220a202020746966663a526573
    6f6c7574696f6e556e69743d2232220a202020746966663a585265736f6c7574
    696f6e3d2239362f31220a202020746966663a595265736f6c7574696f6e3d22
    39362f31220a20202070686f746f73686f703a436f6c6f724d6f64653d223322
    0a20202070686f746f73686f703a49434350726f66696c653d22735247422049
    454336313936362d322e31220a202020786d703a4d6f64696679446174653d22
    323032342d30322d32335431313a34373a33362b30313a3030220a202020786d
    703a4d65746164617461446174653d22323032342d30322d32335431313a3437
    3a33362b30313a3030223e0a2020203c64633a7469746c653e0a202020203c72
    64663a416c743e0a20202020203c7264663a6c6920786d6c3a6c616e673d2278
    2d64656661756c74223e646f6f776d746f776e5f6865616465725f3030323c2f
    7264663a6c693e0a202020203c2f7264663a416c743e0a2020203c2f64633a74
    69746c653e0a2020203c786d704d4d3a486973746f72793e0a202020203c7264
    663a5365713e0a20202020203c7264663a6c690a20202020202073744576743a
    616374696f6e3d2270726f6475636564220a20202020202073744576743a736f
    6674776172654167656e743d22416666696e6974792050686f746f20312e3130
    2e36220a20202020202073744576743a7768656e3d22323032342d30322d3233
    5431313a34373a33362b30313a3030222f3e0a202020203c2f7264663a536571
    3e0a2020203c2f786d704d4d3a486973746f72793e0a20203c2f7264663a4465
    736372697074696f6e3e0a203c2f7264663a5244463e0a3c2f783a786d706d65
    74613e0a3c3f787061636b657420656e643d2272223f3ecfea4fe40000000950
    4c544547704cffffff000000e6ce63220000000174524e530040e6d866000002
    894944415458c3ed983b72e4201086559369eea12341b9881c39d029e61204ce
    9c1048a7b478fcfd00b4f2cce2646b297b68e8d6a7dfed468299a669baefa97d
    91f5b8719f6dcca0c531c7d338b560527364bdcfdc671b336871ccf1348eed86
    b907acb785fb6c63c6c8088ac738e166798b677042721e27dc622a8ab19efb6c
    63c6c808718f3c3ec1fdb0359213ce9b4ad44f5b23f97770b17290ae62951eb6
    31a830783e3fa32b7af295d15370eb1186e22b56e961136e83e7e303b850e35c
    8a4b6d2d56e961132ec0c3eab61a67d35f5166b3557ad884f3f0b0babdc671f2
    6cb1d0c3261c79585dbe52e228792eff41d4c3066e238f50176a1c256fcdd750
    0f1bb8401ea16eab7156a68c2f2ee162c69347a8db6b1cd50f2318c5b7325504
    c7f81617bab8581757b8f54802e116513f2d2e56ed15ce1de96b707b1717d7d4
    152eae42c2cda27e5a5cf9f923cee45b5a7ab8a37e3ab875bbc6ad2921965e3d
    a89f0ece856b9c4bffae82bb7731f8b5fe1a97ebb6e026af8262bd4b1b978a75
    a07039fe1417eb5ddab854af03c6c5f975ac3a37569d1dabce8c55975e0003d5
    b9b1eaacc24945b54afd292365cc61314e2aaa55ea4f1929630eebbfba7f5cdd
    bd5d0dba58e5da681facd56b1b0ff79ec27a3df41efb15ee665e54575e4a156e
    362faa2bafcc0ab7bca80e2ff413dcb3eab0dd38d9413dab0e9ba113dcb3eae4
    1eb0b35dd4dbc42a547cca883eceedd5269636b30d8e3dfbb6ea18b5d5565b6c
    da6a3738f6ecc1e91875105007003a083438f6ecdeea18754c51c7133aa63438
    f6206d0d8e52d71ca23a38f2c4146f3d1ca5ae39e27570e489290e3d1ca5ae39
    807670e4c1c95ee3ee6658fb9ac477217fdf9cf81665447b4cf348dcfbb48cc4
    bd8dc6f991383b18f70d191820ddc109c6040000000049454e44ae426082
  }]
}

proc wapp-page-doomtown_header_002_624px.png {} {
  wapp-mimetype image/png
  wapp-cache-control max-age=3600
    wapp-unsafe [binary decode hex {
    89504e470d0a1a0a0000000d4948445200000270000000800203000000f670bc
    000000000467414d410000b18f0bfc6105000000017352474200aece1ce90000
    00097048597300000ec400000ec401952b0e1b0000055e69545874584d4c3a63
    6f6d2e61646f62652e786d7000000000003c3f787061636b657420626567696e
    3d22efbbbf222069643d2257354d304d7043656869487a7265537a4e54637a6b
    633964223f3e0a3c783a786d706d65746120786d6c6e733a783d2261646f6265
    3a6e733a6d6574612f2220783a786d70746b3d22584d5020436f726520352e35
    2e30223e0a203c7264663a52444620786d6c6e733a7264663d22687474703a2f
    2f7777772e77332e6f72672f313939392f30322f32322d7264662d73796e7461
    782d6e7323223e0a20203c7264663a4465736372697074696f6e207264663a61
    626f75743d22220a20202020786d6c6e733a64633d22687474703a2f2f707572
    6c2e6f72672f64632f656c656d656e74732f312e312f220a20202020786d6c6e
    733a657869663d22687474703a2f2f6e732e61646f62652e636f6d2f65786966
    2f312e302f220a20202020786d6c6e733a746966663d22687474703a2f2f6e73
    2e61646f62652e636f6d2f746966662f312e302f220a20202020786d6c6e733a
    70686f746f73686f703d22687474703a2f2f6e732e61646f62652e636f6d2f70
    686f746f73686f702f312e302f220a20202020786d6c6e733a786d703d226874
    74703a2f2f6e732e61646f62652e636f6d2f7861702f312e302f220a20202020
    786d6c6e733a786d704d4d3d22687474703a2f2f6e732e61646f62652e636f6d
    2f7861702f312e302f6d6d2f220a20202020786d6c6e733a73744576743d2268
    7474703a2f2f6e732e61646f62652e636f6d2f7861702f312e302f7354797065
    2f5265736f757263654576656e7423220a202020657869663a506978656c5844
    696d656e73696f6e3d22363234220a202020657869663a506978656c5944696d
    656e73696f6e3d22313238220a202020657869663a436f6c6f7253706163653d
    2231220a202020746966663a496d61676557696474683d22363234220a202020
    746966663a496d6167654c656e6774683d22313238220a202020746966663a52
    65736f6c7574696f6e556e69743d2232220a202020746966663a585265736f6c
    7574696f6e3d2239362f31220a202020746966663a595265736f6c7574696f6e
    3d2239362f31220a20202070686f746f73686f703a436f6c6f724d6f64653d22
    33220a20202070686f746f73686f703a49434350726f66696c653d2273524742
    2049454336313936362d322e31220a202020786d703a4d6f6469667944617465
    3d22323032342d30322d32335431313a31393a30362b30313a3030220a202020
    786d703a4d65746164617461446174653d22323032342d30322d32335431313a
    31393a30362b30313a3030223e0a2020203c64633a7469746c653e0a20202020
    3c7264663a416c743e0a20202020203c7264663a6c6920786d6c3a6c616e673d
    22782d64656661756c74223e646f6f776d746f776e5f6865616465725f303032
    3c2f7264663a6c693e0a202020203c2f7264663a416c743e0a2020203c2f6463
    3a7469746c653e0a2020203c786d704d4d3a486973746f72793e0a202020203c
    7264663a5365713e0a20202020203c7264663a6c690a20202020202073744576
    743a616374696f6e3d2270726f6475636564220a20202020202073744576743a
    736f6674776172654167656e743d22416666696e6974792050686f746f20312e
    31302e36220a20202020202073744576743a7768656e3d22323032342d30322d
    32335431313a31393a30362b30313a3030222f3e0a202020203c2f7264663a53
    65713e0a2020203c2f786d704d4d3a486973746f72793e0a20203c2f7264663a
    4465736372697074696f6e3e0a203c2f7264663a5244463e0a3c2f783a786d70
    6d6574613e0a3c3f787061636b657420656e643d2272223f3e5d1e7bfe000000
    09504c544547704cffffff000000e6ce63220000000174524e530040e6d86600
    0002fe4944415478daed9c419284200c455d733f36399d9b6c38e52c466c487e
    802e5b8b50b2989140c2b33fad1985d9b6ff92aa026cfbb605542fedb28f2c67
    3b1a53b79f6566b814ab92b48db68d51bdb4cb3eb29ced20be6e77011764b75d
    dbf680eba57d0fb159ce76105fb6fb8063f303be09ce980065bb0bb8d0e8f6e1
    655c2fedc46db84f3b3e8da27d21b8df96ee04f001c7ad0ff89ed29d002fdcfa
    70396d91170c61abead21e8b38b9281fe6d32dfb9463661f3f705444137d4b5b
    55977600c7d2878848c225d770585712b6ba2eed004ef92059cb311dc2415da5
    adae4bbb8663e503654daee190ae246ca22eed1a4efb40598b313dc2015dab51
    745dda151c6b1f2c6b720da775a57a1855977605077cb0ac895dc39175e14003
    8be0b00f031f43d6e41a4ea530080241a1938a9d18280ebb874b5fc0e5dbfa55
    b89cadfa820b460a330297eff957e1e2a1ab73b8f405dcf1e7cb65b843575f70
    1be3146608aefa79012e5627e9052ee014660c8eca897c018eca2f9617b82dc1
    14660c2e9617cf0b70b1bc98bb81dbd21730f237f16fe0ca94cd0fdcc68d4039
    b5b6ec7250231537e1caf86bc1e5d4dab2cb415ba93882cbfd6939b8a7648dcb
    c13d256bf1406811b8c7648dabc13d26ebe7c1f72270cfc91a17837b4ed6f305
    9f33384bbe9eccad632ba615e7b03983b3e4ebc9dc3ab6625a710e9b33b877ce
    bd73ee9d73ef9c7be7dc3be7de39f733b8a1b4bc95385a29fbc803c7e6cbe0c9
    e1521c49cb5b7056ca3ef290db315cb01f83de236bfd62c5311cc78765ad5fe6
    f9850bf16159c50be475e06e97552c5af00bc70fcb2a17caac0377b7acd65237
    b77034b298af13141e5b319681932b1a471694f6d374e09352626ac77105477a
    85637f1173170ef99c777d3b8e2b38a5eac0c2f90138e0931257db869cc391b5
    a8b6b55963002ea29951f7720e0754ed6e101a82d33ee78589578083aaf636a5
    0dc1691fb9bfc8371c54b5b31172104ef9c8ade26ee1f47f9898a024077053b2
    65ba99e1429cb4ecb3c3f1ac703439dcb4aac6b8bf706bc2f1bc70f4c22d09f7
    0705567b010da0e9a50000000049454e44ae426082
  }]
}

setup-db
wapp-start $wapp_args