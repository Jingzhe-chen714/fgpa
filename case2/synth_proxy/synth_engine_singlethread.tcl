set_param general.maxThreads 1
set_param synth.maxThreads 1
source [file join [file dirname [file normalize [info script]]] synth_engine.tcl]
