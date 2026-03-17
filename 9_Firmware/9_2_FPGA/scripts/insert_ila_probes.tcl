################################################################################
# insert_ila_probes.tcl
#
# AERIS-10 Radar FPGA — Post-Synthesis ILA Debug Core Insertion
# Target: XC7A200T-2FBG484I
# Design: radar_system_top (Build 13 frozen netlist)
#
# Usage:
#   vivado -mode batch -source insert_ila_probes.tcl
#
# This script:
#   1. Opens the post-synth DCP from Build 13
#   2. Inserts 4 ILA debug cores across 2 clock domains
#   3. Runs full implementation with Build 13 directives
#   4. Generates bitstream, reports, and .ltx probe file
#
# ILA 0: ADC Capture          — 400 MHz (rx_inst/clk_400m)   — 9 bits
# ILA 1: DDC Output           — 100 MHz (clk_100m_buf)       — 37 bits
# ILA 2: Matched Filter Out   — 100 MHz (clk_100m_buf)       — 35 bits
# ILA 3: Doppler Output       — 100 MHz (clk_100m_buf)       — 45 bits
#
# Author: auto-generated for Jason Stone
# Date:   2026-03-18
################################################################################

# ==============================================================================
# 0. Configuration — all paths and parameters in one place
# ==============================================================================

set project_base   "/home/jason-stone/PLFM_RADAR_work/vivado_project"
set synth_dcp      "${project_base}/aeris10_radar.runs/impl_1/radar_system_top.dcp"
set synth_xdc      "${project_base}/synth_only.xdc"
set output_dir     "${project_base}/aeris10_radar.runs/impl_ila"
set top_module     "radar_system_top"
set part           "xc7a200tfbg484-2"

# Timestamp for output file naming
set timestamp      [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
set run_tag        "build13_ila_${timestamp}"

# ILA parameters
set ila_depth      4096
set trigger_pos    512     ;# 512 pre-trigger samples

# ==============================================================================
# 1. Helper procedures
# ==============================================================================

# Resolve a net with fallback wildcard patterns. Returns the net object or
# raises an error with diagnostic info if nothing is found.
proc resolve_net {primary_pattern args} {
    # Try the primary pattern first
    set nets [get_nets -quiet $primary_pattern]
    if {[llength $nets] > 0} {
        puts "INFO: Resolved net '$primary_pattern' -> [lindex $nets 0]"
        return [lindex $nets 0]
    }

    # Try each fallback pattern
    foreach fallback $args {
        set nets [get_nets -quiet $fallback]
        if {[llength $nets] > 0} {
            puts "INFO: Primary '$primary_pattern' not found. Resolved via fallback '$fallback' -> [lindex $nets 0]"
            return [lindex $nets 0]
        }
    }

    # Nothing found — dump available nets in the hierarchy for diagnostics
    set hier_prefix [lindex [split $primary_pattern "/"] 0]
    puts "ERROR: Could not resolve net '$primary_pattern'"
    puts "       Available nets under '${hier_prefix}/*' (first 40):"
    set nearby [get_nets -quiet -hierarchical "${hier_prefix}/*"]
    set count 0
    foreach n $nearby {
        puts "         $n"
        incr count
        if {$count >= 40} { puts "         ... (truncated)"; break }
    }
    error "Net resolution failed for '$primary_pattern'. See log above for nearby nets."
}

# Resolve a bus (vector) of nets. Returns a list of net objects.
# pattern should contain %d which will be replaced with bit indices.
# Example: resolve_bus "rx_inst/adc/adc_data_cmos\[%d\]" 7 0
#          tries bits 7 down to 0
proc resolve_bus {pattern msb lsb args} {
    set net_list {}
    for {set i $msb} {$i >= $lsb} {incr i -1} {
        set bit_pattern [string map [list "%d" $i] $pattern]
        # Build fallback list for this bit
        set bit_fallbacks {}
        foreach fb $args {
            lappend bit_fallbacks [string map [list "%d" $i] $fb]
        }
        lappend net_list [resolve_net $bit_pattern {*}$bit_fallbacks]
    }
    return $net_list
}

# Connect a list of nets to an ILA probe port, creating additional probe ports
# as needed. The first probe port (DATA) is already created by create_debug_core.
# probe_index: starting probe port index (0 = use existing PROBE0)
# Returns the next available probe index.
proc connect_probe_nets {ila_name probe_index net_list probe_label} {
    set width [llength $net_list]
    puts "INFO: Connecting $width nets to ${ila_name}/probe${probe_index} ($probe_label)"

    if {$probe_index > 0} {
        create_debug_port $ila_name probe
    }

    set_property port_width $width [get_debug_ports ${ila_name}/probe${probe_index}]
    connect_debug_port ${ila_name}/probe${probe_index} $net_list

    return [expr {$probe_index + 1}]
}

# ==============================================================================
# 2. Open the synthesized checkpoint
# ==============================================================================

puts "======================================================================"
puts " AERIS-10 ILA Insertion — Starting at [clock format [clock seconds]]"
puts "======================================================================"

# Create output directory
file mkdir $output_dir

# Open the frozen Build 13 post-synth DCP
puts "\nINFO: Opening post-synth DCP: $synth_dcp"
open_checkpoint $synth_dcp

# Verify the part
set loaded_part [get_property PART [current_design]]
puts "INFO: Design part = $loaded_part"
if {$loaded_part ne $part} {
    puts "WARNING: Expected part '$part', got '$loaded_part'. Continuing anyway."
}

# Read the synthesis-only constraints (pin assignments, clocks, etc.)
puts "INFO: Reading XDC: $synth_xdc"
read_xdc $synth_xdc

# ==============================================================================
# 3. Verify clock nets exist before inserting ILA cores
# ==============================================================================

puts "\n--- Verifying clock nets ---"

# 400 MHz clock — BUFG output inside ADC interface
set clk_400m_net [resolve_net \
    "rx_inst/clk_400m" \
    "rx_inst/adc/clk_400m" \
    "rx_inst/ad9484_interface_400m_inst/clk_400m" \
    "rx_inst/*/O" \
]

# 100 MHz system clock — BUFG output
set clk_100m_net [resolve_net \
    "clk_100m_buf" \
    "bufg_100m/O" \
    "clk_100m_BUFG" \
]

puts "INFO: 400 MHz clock net = $clk_400m_net"
puts "INFO: 100 MHz clock net = $clk_100m_net"

# ==============================================================================
# 4. ILA 0 — ADC Capture (400 MHz domain)
#
# Monitors raw ADC data at the CMOS interface output.
# 8-bit ADC data + 1-bit valid = 9 probed bits.
# 4096 samples at 400 MHz => ~10.24 us capture window —
# sufficient for one chirp segment observation.
# ==============================================================================

puts "\n====== ILA 0: ADC Capture (400 MHz) ======"

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU    true  [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1    [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER        false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH         $ila_depth [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL       true  [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES  0     [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN          false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN         false [get_debug_cores u_ila_0]

# Clock: 400 MHz BUFG output from ADC interface
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets $clk_400m_net]

# Probe 0: adc_data_cmos[7:0] — raw 8-bit ADC sample from AD9484
set adc_data_nets [resolve_bus \
    "rx_inst/adc/adc_data_cmos\[%d\]" 7 0 \
    "rx_inst/adc/adc_data_400m\[%d\]" \
    "rx_inst/ad9484_interface_400m_inst/adc_data_cmos\[%d\]" \
    "rx_inst/*/adc_data_cmos\[%d\]" \
]
set probe_idx 0
set probe_idx [connect_probe_nets u_ila_0 $probe_idx $adc_data_nets "ADC raw data\[7:0\]"]

# Probe 1: adc_valid — data valid strobe
set adc_valid_net [resolve_net \
    "rx_inst/adc/adc_valid" \
    "rx_inst/ad9484_interface_400m_inst/adc_valid" \
    "rx_inst/*/adc_valid" \
]
set probe_idx [connect_probe_nets u_ila_0 $probe_idx [list $adc_valid_net] "ADC valid"]

puts "INFO: ILA 0 configured — 9 probe bits on 400 MHz clock"

# ==============================================================================
# 5. ILA 1 — DDC Output (100 MHz domain)
#
# Monitors the digital down-converter output after CIC+FIR decimation.
# 18-bit I + 18-bit Q + 1-bit valid = 37 probed bits.
# With 4x decimation the effective sample rate is 25 MSPS,
# so 4096 samples => ~163.8 us — covers multiple chirp periods.
# ==============================================================================

puts "\n====== ILA 1: DDC Output (100 MHz) ======"

create_debug_core u_ila_1 ila
set_property ALL_PROBE_SAME_MU    true  [get_debug_cores u_ila_1]
set_property ALL_PROBE_SAME_MU_CNT 1    [get_debug_cores u_ila_1]
set_property C_ADV_TRIGGER        false [get_debug_cores u_ila_1]
set_property C_DATA_DEPTH         $ila_depth [get_debug_cores u_ila_1]
set_property C_EN_STRG_QUAL       true  [get_debug_cores u_ila_1]
set_property C_INPUT_PIPE_STAGES  0     [get_debug_cores u_ila_1]
set_property C_TRIGIN_EN          false [get_debug_cores u_ila_1]
set_property C_TRIGOUT_EN         false [get_debug_cores u_ila_1]

# Clock: 100 MHz system clock
set_property port_width 1 [get_debug_ports u_ila_1/clk]
connect_debug_port u_ila_1/clk [get_nets $clk_100m_net]

# Probe 0: ddc_out_i[17:0] — DDC I-channel baseband output
set ddc_i_nets [resolve_bus \
    "rx_inst/ddc_out_i\[%d\]" 17 0 \
    "rx_inst/ddc_400m_inst/ddc_out_i\[%d\]" \
    "rx_inst/*/ddc_out_i\[%d\]" \
]
set probe_idx 0
set probe_idx [connect_probe_nets u_ila_1 $probe_idx $ddc_i_nets "DDC I\[17:0\]"]

# Probe 1: ddc_out_q[17:0] — DDC Q-channel baseband output
set ddc_q_nets [resolve_bus \
    "rx_inst/ddc_out_q\[%d\]" 17 0 \
    "rx_inst/ddc_400m_inst/ddc_out_q\[%d\]" \
    "rx_inst/*/ddc_out_q\[%d\]" \
]
set probe_idx [connect_probe_nets u_ila_1 $probe_idx $ddc_q_nets "DDC Q\[17:0\]"]

# Probe 2: ddc_valid_i — DDC output valid strobe (I path; Q valid assumed coincident)
set ddc_valid_net [resolve_net \
    "rx_inst/ddc_valid_i" \
    "rx_inst/ddc_400m_inst/ddc_valid_i" \
    "rx_inst/*/ddc_valid_i" \
    "rx_inst/ddc_valid" \
]
set probe_idx [connect_probe_nets u_ila_1 $probe_idx [list $ddc_valid_net] "DDC valid"]

puts "INFO: ILA 1 configured — 37 probe bits on 100 MHz clock"

# ==============================================================================
# 6. ILA 2 — Matched Filter Output (100 MHz domain)
#
# Monitors the pulse-compression matched filter output.
# 16-bit I + 16-bit Q + 1-bit valid + 2-bit segment index = 35 probed bits.
# This allows verifying correct chirp segment correlation and range profile.
# ==============================================================================

puts "\n====== ILA 2: Matched Filter Output (100 MHz) ======"

create_debug_core u_ila_2 ila
set_property ALL_PROBE_SAME_MU    true  [get_debug_cores u_ila_2]
set_property ALL_PROBE_SAME_MU_CNT 1    [get_debug_cores u_ila_2]
set_property C_ADV_TRIGGER        false [get_debug_cores u_ila_2]
set_property C_DATA_DEPTH         $ila_depth [get_debug_cores u_ila_2]
set_property C_EN_STRG_QUAL       true  [get_debug_cores u_ila_2]
set_property C_INPUT_PIPE_STAGES  0     [get_debug_cores u_ila_2]
set_property C_TRIGIN_EN          false [get_debug_cores u_ila_2]
set_property C_TRIGOUT_EN         false [get_debug_cores u_ila_2]

# Clock: 100 MHz system clock (shared with ILA 1)
set_property port_width 1 [get_debug_ports u_ila_2/clk]
connect_debug_port u_ila_2/clk [get_nets $clk_100m_net]

# Probe 0: pc_i_w[15:0] — matched filter range-compressed I output
set mf_i_nets [resolve_bus \
    "rx_inst/mf_dual/pc_i_w\[%d\]" 15 0 \
    "rx_inst/matched_filter_multi_segment_inst/pc_i_w\[%d\]" \
    "rx_inst/*/pc_i_w\[%d\]" \
]
set probe_idx 0
set probe_idx [connect_probe_nets u_ila_2 $probe_idx $mf_i_nets "MF I\[15:0\]"]

# Probe 1: pc_q_w[15:0] — matched filter range-compressed Q output
set mf_q_nets [resolve_bus \
    "rx_inst/mf_dual/pc_q_w\[%d\]" 15 0 \
    "rx_inst/matched_filter_multi_segment_inst/pc_q_w\[%d\]" \
    "rx_inst/*/pc_q_w\[%d\]" \
]
set probe_idx [connect_probe_nets u_ila_2 $probe_idx $mf_q_nets "MF Q\[15:0\]"]

# Probe 2: pc_valid_w — matched filter output valid
set mf_valid_net [resolve_net \
    "rx_inst/mf_dual/pc_valid_w" \
    "rx_inst/matched_filter_multi_segment_inst/pc_valid_w" \
    "rx_inst/*/pc_valid_w" \
]
set probe_idx [connect_probe_nets u_ila_2 $probe_idx [list $mf_valid_net] "MF valid"]

# Probe 3: segment_request[1:0] — chirp segment being correlated (0-3)
set seg_nets [resolve_bus \
    "rx_inst/mf_dual/segment_request\[%d\]" 1 0 \
    "rx_inst/matched_filter_multi_segment_inst/segment_request\[%d\]" \
    "rx_inst/*/segment_request\[%d\]" \
]
set probe_idx [connect_probe_nets u_ila_2 $probe_idx $seg_nets "MF segment\[1:0\]"]

puts "INFO: ILA 2 configured — 35 probe bits on 100 MHz clock"

# ==============================================================================
# 7. ILA 3 — Doppler Output (100 MHz domain)
#
# Monitors the Doppler processor output (post-FFT).
# 32-bit spectrum + 1-bit valid + 5-bit Doppler bin + 6-bit range bin
# + 1-bit frame sync = 45 probed bits.
# Allows verification of the range-Doppler map generation.
# ==============================================================================

puts "\n====== ILA 3: Doppler Output (100 MHz) ======"

create_debug_core u_ila_3 ila
set_property ALL_PROBE_SAME_MU    true  [get_debug_cores u_ila_3]
set_property ALL_PROBE_SAME_MU_CNT 1    [get_debug_cores u_ila_3]
set_property C_ADV_TRIGGER        false [get_debug_cores u_ila_3]
set_property C_DATA_DEPTH         $ila_depth [get_debug_cores u_ila_3]
set_property C_EN_STRG_QUAL       true  [get_debug_cores u_ila_3]
set_property C_INPUT_PIPE_STAGES  0     [get_debug_cores u_ila_3]
set_property C_TRIGIN_EN          false [get_debug_cores u_ila_3]
set_property C_TRIGOUT_EN         false [get_debug_cores u_ila_3]

# Clock: 100 MHz system clock (shared with ILA 1, ILA 2)
set_property port_width 1 [get_debug_ports u_ila_3/clk]
connect_debug_port u_ila_3/clk [get_nets $clk_100m_net]

# Probe 0: doppler_output[31:0] — Doppler FFT magnitude/spectrum output
set dop_out_nets [resolve_bus \
    "rx_inst/doppler_proc/doppler_output\[%d\]" 31 0 \
    "rx_inst/doppler_processor_inst/doppler_output\[%d\]" \
    "rx_inst/*/doppler_output\[%d\]" \
]
set probe_idx 0
set probe_idx [connect_probe_nets u_ila_3 $probe_idx $dop_out_nets "Doppler spectrum\[31:0\]"]

# Probe 1: doppler_valid — Doppler output valid strobe
set dop_valid_net [resolve_net \
    "rx_inst/doppler_proc/doppler_valid" \
    "rx_inst/doppler_processor_inst/doppler_valid" \
    "rx_inst/*/doppler_valid" \
]
set probe_idx [connect_probe_nets u_ila_3 $probe_idx [list $dop_valid_net] "Doppler valid"]

# Probe 2: doppler_bin[4:0] — Doppler frequency bin index (0-31)
set dop_bin_nets [resolve_bus \
    "rx_inst/doppler_proc/doppler_bin\[%d\]" 4 0 \
    "rx_inst/doppler_processor_inst/doppler_bin\[%d\]" \
    "rx_inst/*/doppler_bin\[%d\]" \
]
set probe_idx [connect_probe_nets u_ila_3 $probe_idx $dop_bin_nets "Doppler bin\[4:0\]"]

# Probe 3: range_bin[5:0] — range bin index (0-63)
set rng_bin_nets [resolve_bus \
    "rx_inst/doppler_proc/range_bin\[%d\]" 5 0 \
    "rx_inst/doppler_processor_inst/range_bin\[%d\]" \
    "rx_inst/*/range_bin\[%d\]" \
]
set probe_idx [connect_probe_nets u_ila_3 $probe_idx $rng_bin_nets "Range bin\[5:0\]"]

# Probe 4: new_frame_pulse — top-level frame synchronization pulse
set frame_net [resolve_net \
    "rx_inst/new_frame_pulse" \
    "rx_inst/radar_receiver_final_inst/new_frame_pulse" \
    "rx_inst/*/new_frame_pulse" \
    "new_frame_pulse" \
]
set probe_idx [connect_probe_nets u_ila_3 $probe_idx [list $frame_net] "Frame sync pulse"]

puts "INFO: ILA 3 configured — 45 probe bits on 100 MHz clock"

# ==============================================================================
# 8. Implement the modified design
# ==============================================================================

puts "\n======================================================================"
puts " Implementation — matching Build 13 directives"
puts "======================================================================"

# Save the post-ILA-insertion checkpoint for reference
set ila_dcp "${output_dir}/${top_module}_ila_inserted.dcp"
write_checkpoint -force $ila_dcp
puts "INFO: Saved ILA-inserted checkpoint: $ila_dcp"

# --- opt_design (Explore) ---
puts "\n--- opt_design -directive Explore ---"
opt_design -directive Explore

write_checkpoint -force "${output_dir}/${top_module}_opt.dcp"

# --- place_design (ExtraTimingOpt) ---
puts "\n--- place_design -directive ExtraTimingOpt ---"
place_design -directive ExtraTimingOpt

write_checkpoint -force "${output_dir}/${top_module}_placed.dcp"

# Post-place timing estimate
report_timing_summary -file "${output_dir}/timing_post_place.rpt" -max_paths 20

# --- phys_opt_design (AggressiveExplore) — post-place ---
puts "\n--- phys_opt_design -directive AggressiveExplore (post-place) ---"
phys_opt_design -directive AggressiveExplore

write_checkpoint -force "${output_dir}/${top_module}_physopt.dcp"

# --- route_design (AggressiveExplore) ---
puts "\n--- route_design -directive AggressiveExplore ---"
route_design -directive AggressiveExplore

write_checkpoint -force "${output_dir}/${top_module}_routed.dcp"

# Post-route timing check
report_timing_summary -file "${output_dir}/timing_post_route.rpt" -max_paths 50

# --- post-route phys_opt_design (AggressiveExplore) ---
puts "\n--- phys_opt_design -directive AggressiveExplore (post-route) ---"
phys_opt_design -directive AggressiveExplore

# Final routed + physopt checkpoint
set final_dcp "${output_dir}/${top_module}_postroute_physopt.dcp"
write_checkpoint -force $final_dcp
puts "INFO: Final checkpoint: $final_dcp"

# ==============================================================================
# 9. Generate reports for comparison with Build 13
# ==============================================================================

puts "\n======================================================================"
puts " Reports"
puts "======================================================================"

# Timing summary (compare WNS/TNS/WHS/THS against Build 13)
report_timing_summary \
    -file "${output_dir}/timing_summary_final.rpt" \
    -max_paths 100 \
    -report_unconstrained

# Per-clock-domain timing (critical for multi-clock radar design)
report_timing \
    -file "${output_dir}/timing_per_clock.rpt" \
    -max_paths 20 \
    -sort_by group

# Utilization (expect ~2-4% increase from ILA cores on XC7A200T)
report_utilization \
    -file "${output_dir}/utilization.rpt"

report_utilization \
    -file "${output_dir}/utilization_hierarchical.rpt" \
    -hierarchical

# DRC
report_drc \
    -file "${output_dir}/drc.rpt"

# Clock interaction / CDC (important with 400 MHz <-> 100 MHz crossing)
report_clock_interaction \
    -file "${output_dir}/clock_interaction.rpt" \
    -delay_type min_max

# Clock networks (verify BUFG usage)
report_clock_networks \
    -file "${output_dir}/clock_networks.rpt"

# Power estimate
report_power \
    -file "${output_dir}/power.rpt"

# ILA core summary
report_debug_core \
    -file "${output_dir}/debug_core_summary.rpt"

puts "INFO: All reports written to $output_dir"

# ==============================================================================
# 10. Write debug probes file (.ltx) for Vivado Hardware Manager
# ==============================================================================

puts "\n--- Writing debug probes .ltx file ---"

set ltx_file "${output_dir}/${top_module}.ltx"
write_debug_probes -force $ltx_file
puts "INFO: Debug probes file: $ltx_file"

# Also copy the .ltx next to the bitstream for convenience
file copy -force $ltx_file "${output_dir}/debug_nets.ltx"

# ==============================================================================
# 11. Generate bitstream
# ==============================================================================

puts "\n======================================================================"
puts " Bitstream Generation"
puts "======================================================================"

set bitstream_file "${output_dir}/${top_module}.bit"

write_bitstream -force $bitstream_file

puts "INFO: Bitstream written: $bitstream_file"

# Also generate a .bin file for SPI flash programming if needed
write_cfgmem -force \
    -format BIN \
    -size 32 \
    -interface SPIx4 \
    -loadbit "up 0x0 $bitstream_file" \
    "${output_dir}/${top_module}.bin"

puts "INFO: SPI flash image: ${output_dir}/${top_module}.bin"

# ==============================================================================
# 12. Final summary
# ==============================================================================

puts "\n======================================================================"
puts " AERIS-10 ILA Insertion Complete"
puts "======================================================================"
puts ""
puts " Output directory:  $output_dir"
puts " Final DCP:         $final_dcp"
puts " Bitstream:         $bitstream_file"
puts " Debug probes:      $ltx_file"
puts " Run tag:           $run_tag"
puts ""
puts " ILA Cores Inserted:"
puts "   u_ila_0 : ADC Capture       (400 MHz, 9 bits,  depth=$ila_depth)"
puts "   u_ila_1 : DDC Output        (100 MHz, 37 bits, depth=$ila_depth)"
puts "   u_ila_2 : Matched Filter    (100 MHz, 35 bits, depth=$ila_depth)"
puts "   u_ila_3 : Doppler Output    (100 MHz, 45 bits, depth=$ila_depth)"
puts ""
puts " Compare these reports against Build 13 baseline:"
puts "   - timing_summary_final.rpt  (WNS/TNS/WHS/THS)"
puts "   - utilization.rpt           (BRAM/LUT/FF overhead)"
puts "   - clock_interaction.rpt     (CDC paths)"
puts ""
puts " To load in Hardware Manager:"
puts "   1. Program bitstream: $bitstream_file"
puts "   2. Load probes file:  $ltx_file"
puts "   3. Set trigger position to $trigger_pos for pre/post capture"
puts ""
puts " Finished at [clock format [clock seconds]]"
puts "======================================================================"

close_design
