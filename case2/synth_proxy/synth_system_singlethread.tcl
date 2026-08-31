# Reduce synthesis concurrency in a detached run. Vivado may still create an
# auxiliary helper; these supported settings are not a Job-isolation mechanism.
set_param general.maxThreads 1
set_param synth.maxThreads 1
source [file join [file dirname [file normalize [info script]]] synth_system_ip_stub.tcl]
