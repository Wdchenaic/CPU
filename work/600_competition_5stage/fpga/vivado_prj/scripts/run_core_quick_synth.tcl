set script_dir [file dirname [file normalize [info script]]]
set vivado_prj_dir [file normalize [file join $script_dir ..]]
set proj_root [file normalize [file join $vivado_prj_dir .. ..]]
set run_dir [file normalize [file join $vivado_prj_dir runs core_quick_synth]]

if {[llength $argv] >= 1} {
    set part_name [lindex $argv 0]
} else {
    set part_name xc7z020clg400-1
}

if {[llength $argv] >= 2} {
    set top_name [lindex $argv 1]
} else {
    set top_name panda_risc_v
}

file mkdir $run_dir

create_project -in_memory competition_core_quick $run_dir -part $part_name
set_msg_config -id {Synth 8-3917} -new_severity WARNING

set rtl_dirs [list     [file join $proj_root rtl]     [file join $proj_root rtl generic]     [file join $proj_root rtl ifu]     [file join $proj_root rtl decoder_dispatcher]     [file join $proj_root rtl exu]     [file join $proj_root rtl system]     [file join $proj_root rtl debug]     [file join $proj_root rtl cache]     [file join $proj_root rtl peripherals] ]

foreach dir $rtl_dirs {
    foreach f [lsort [glob -nocomplain -directory $dir *.v]] {
        read_verilog $f
    }
}

synth_design -top $top_name -part $part_name -mode out_of_context

report_utilization -file [file join $run_dir utilization_synth.rpt]
report_utilization -hierarchical -file [file join $run_dir utilization_hier_synth.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $run_dir timing_synth.rpt]
write_checkpoint -force [file join $run_dir post_synth.dcp]

puts "Core quick synth completed."
puts "Reports:"
puts "  [file join $run_dir utilization_synth.rpt]"
puts "  [file join $run_dir utilization_hier_synth.rpt]"
puts "  [file join $run_dir timing_synth.rpt]"
