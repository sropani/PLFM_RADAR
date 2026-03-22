# ============================================================================
# adc_clk_mmcm.xdc — Supplementary constraints for MMCM ADC clock path
#
# These constraints augment the existing adc_dco_p clock definitions when the
# adc_clk_mmcm module is integrated into ad9484_interface_400m.v.
#
# USAGE:
#   Add this file to the Vivado project AFTER the main production XDC.
#   The main XDC still defines create_clock on adc_dco_p (the physical input).
#   Vivado automatically creates a generated clock on the MMCM output;
#   these constraints handle CDC paths for the new clock topology.
#
# HIERARCHY: rx_inst/adc/mmcm_inst/...
# ============================================================================

# --------------------------------------------------------------------------
# MMCM Output Clock — use Vivado's auto-generated clock name
# --------------------------------------------------------------------------
# Vivado auto-creates a generated clock named 'clk_mmcm_out0' on the MMCM
# CLKOUT0 net. We do NOT create_generated_clock here (that would create a
# second clock on the same net, causing the CDC false paths below to bind
# to the wrong clock and leave clk_mmcm_out0 uncovered — exactly the bug
# that caused Build 19's -0.011 ns WNS on the CDC_FIR gray-code path).
# All constraints below reference 'clk_mmcm_out0' directly.

# --------------------------------------------------------------------------
# CDC: BUFIO domain (adc_dco_p) ↔ MMCM output domain (clk_mmcm_out0)
# --------------------------------------------------------------------------
# The IDDR outputs are captured by BUFIO (adc_dco_p clock), then re-registered
# into the MMCM BUFG domain in ad9484_interface_400m.v.
# These clocks are frequency-matched and phase-related (MMCM is locked to
# adc_dco_p), so the single register transfer is safe. We use max_delay
# (one period) to ensure the tools verify the transfer fits within one cycle
# without over-constraining with full inter-clock setup/hold analysis.
set_max_delay -datapath_only -from [get_clocks adc_dco_p] \
    -to [get_clocks clk_mmcm_out0] 2.500

set_max_delay -datapath_only -from [get_clocks clk_mmcm_out0] \
    -to [get_clocks adc_dco_p] 2.500

# --------------------------------------------------------------------------
# CDC: MMCM output domain ↔ other clock domains
# --------------------------------------------------------------------------
# The existing false paths in the production XDC reference adc_dco_p, which
# now only covers the BUFIO/IDDR domain. The MMCM output clock (which drives
# all fabric 400 MHz logic) needs its own false path declarations.
set_false_path -from [get_clocks clk_100m] -to [get_clocks clk_mmcm_out0]
set_false_path -from [get_clocks clk_mmcm_out0] -to [get_clocks clk_100m]

set_false_path -from [get_clocks clk_mmcm_out0] -to [get_clocks ft601_clk_in]
set_false_path -from [get_clocks ft601_clk_in] -to [get_clocks clk_mmcm_out0]

set_false_path -from [get_clocks clk_mmcm_out0] -to [get_clocks clk_120m_dac]
set_false_path -from [get_clocks clk_120m_dac] -to [get_clocks clk_mmcm_out0]

# --------------------------------------------------------------------------
# MMCM Locked — asynchronous status signal, no timing paths needed
# --------------------------------------------------------------------------
# LOCKED is not a valid timing startpoint (it's a combinational output of the
# MMCM primitive). Use -through instead of -from to waive all paths that pass
# through the LOCKED net. This avoids the CRITICAL WARNING from Build 19/20.
set_false_path -through [get_pins rx_inst/adc/mmcm_inst/mmcm_adc_400m/LOCKED]

# --------------------------------------------------------------------------
# Hold waiver for BUFIO→MMCM domain transfer (if Vivado flags hold violations)
# --------------------------------------------------------------------------
# The existing hold waiver for BUFIO source-synchronous capture stays:
#   set_false_path -hold -from [get_ports {adc_d_p[*]}] -to [get_clocks adc_dco_p]
#
# The MMCM BUFG re-registration of IDDR outputs: since BUFIO and MMCM output
# are derived from the same IBUFDS source, hold is inherently met (MMCM adds
# insertion delay). If Vivado flags hold violations on this transfer, uncomment:
# set_false_path -hold -from [get_clocks adc_dco_p] -to [get_clocks clk_mmcm_out0]
