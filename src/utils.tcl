proc addCode {list code} {
  return [linsert $list end "\n[string trim $code \n\r]"]
}

proc doCheck {method path} {
  set check {
    puts [wapp-debug-env]
    if {[wapp-param REQUEST_METHOD] != $method} return
    if {[wapp-param PATH_INFO] != $path} return
  }
  regsub -all {\$method} $check \{[list $method]\} check
  regsub -all {\$path} $check \{[list $path]\} check
  # puts $check
  return $check
}

proc bodyCheck {method path code} {
  set bodylist [list]
  set bodylist [addCode $bodylist [doCheck $method $path]]
  set bodylist [addCode $bodylist $code]
  return [join $bodylist \n]
}

proc GET {path code} {
  # TODO:
  set procname wapp-page-test

  set body [bodyCheck GET $path $code]
  eval "proc $procname {} {$body}"
}