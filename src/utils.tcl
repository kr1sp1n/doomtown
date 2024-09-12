set routes [list]

proc sort-route {} {
  global routes
  set routes [lsort -index 1 $routes]
}

proc setup-route {method path code} {
  global routes
  set routes [linsert $routes end [list $method $path $code]]
  set procname "wapp-page-$method-[join [split $path /] -]"
  eval "proc $procname {} {$code}"
  sort-route
}

proc GET {path code} {
  setup-route GET $path $code
}

proc POST {path code} {
  setup-route POST $path $code
}

# Handle defined routes:
proc wapp-before-dispatch-hook {} {
  # puts [wapp-debug-env]
  global routes
  # set procname wapp-page-[wapp-param PATH_HEAD]
  foreach {route} $routes {
    set method [lindex $route 0]
    set path [lindex $route 1]
    if {[wapp-param REQUEST_METHOD] != $method} continue

    set notequal 0
    foreach a [split [wapp-param PATH_INFO] /] b [split $path /] {
      if [regexp {:([^:]+)} $b match var] {
        wapp-set-param PATH_PARAMS [dict create $var $a]
      } else {
        if {$a != $b} {
          set notequal 1
          break
        }
      }
    }
    
    if {$notequal eq 1} continue
    wapp-set-param PATH_HEAD "$method-[string map {/ -} $path]"
    break
  }
}