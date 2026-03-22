#!/usr/bin/env python3
"""
Generate Doppler processor co-simulation golden reference data.

Uses the bit-accurate Python model (fpga_model.py) to compute the expected
Doppler FFT output. Also generates the input hex files consumed by the
Verilog testbench (tb_doppler_cosim.v).

Two output modes:
  1. "clean" — straight Python model (correct windowing alignment)
  2. "buggy" — replicates the RTL's windowing pipeline misalignment:
     * Sample 0: fft_input = 0 (from reset mult value)
     * Sample 1: fft_input = window_multiply(data[wrong_rbin_or_0], window[0])
     * Sample k (k>=2): fft_input = window_multiply(data[k-2], window[k-1])

Default mode is "clean".  The comparison script uses correlation-based
metrics that are tolerant of the pipeline shift.

Usage:
    cd ~/PLFM_RADAR/9_Firmware/9_2_FPGA/tb/cosim
    python3 gen_doppler_golden.py            # clean model
    python3 gen_doppler_golden.py --buggy    # replicate RTL pipeline bug

Author: Phase 0.5 Doppler co-simulation suite for PLFM_RADAR
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fpga_model import (
    DopplerProcessor, FFTEngine, sign_extend, HAMMING_WINDOW
)
from radar_scene import Target, generate_doppler_frame


# =============================================================================
# Constants
# =============================================================================

DOPPLER_FFT_SIZE = 32
RANGE_BINS = 64
CHIRPS_PER_FRAME = 32
TOTAL_SAMPLES = CHIRPS_PER_FRAME * RANGE_BINS  # 2048


# =============================================================================
# I/O helpers
# =============================================================================

def write_hex_32bit(filepath, samples):
    """Write packed 32-bit hex file: {Q[31:16], I[15:0]} per line."""
    with open(filepath, 'w') as f:
        f.write(f"// {len(samples)} packed 32-bit samples (Q:I) for $readmemh\n")
        for (i_val, q_val) in samples:
            packed = ((q_val & 0xFFFF) << 16) | (i_val & 0xFFFF)
            f.write(f"{packed:08X}\n")
    print(f"  Wrote {len(samples)} packed samples to {filepath}")


def write_csv(filepath, headers, *columns):
    """Write CSV with header row."""
    with open(filepath, 'w') as f:
        f.write(','.join(headers) + '\n')
        for i in range(len(columns[0])):
            row = ','.join(str(col[i]) for col in columns)
            f.write(row + '\n')
    print(f"  Wrote {len(columns[0])} rows to {filepath}")


def write_hex_16bit(filepath, data):
    """Write list of signed 16-bit integers as 4-digit hex, one per line."""
    with open(filepath, 'w') as f:
        for val in data:
            v = val & 0xFFFF
            f.write(f"{v:04X}\n")


# =============================================================================
# Buggy-model helpers  (match RTL pipeline misalignment)
# =============================================================================

def window_multiply(data_16, window_16):
    """Hamming window multiply matching RTL."""
    d = sign_extend(data_16 & 0xFFFF, 16)
    w = sign_extend(window_16 & 0xFFFF, 16)
    product = d * w
    rounded = product + (1 << 14)
    result = rounded >> 15
    return sign_extend(result & 0xFFFF, 16)


def buggy_process_frame(chirp_data_i, chirp_data_q):
    """
    Replicate the RTL's exact windowing pipeline for all 64 range bins.

    For each range bin we model the three-stage pipeline:
      Stage A (BRAM registered read):
        mem_rdata captures doppler_i_mem[mem_read_addr] one cycle AFTER
        mem_read_addr is presented.
      Stage B (multiply):
        mult_i <= mem_rdata_i * window_coeff[read_doppler_index]
        -- read_doppler_index is the CURRENT cycle's value, but mem_rdata_i
        -- is from the PREVIOUS cycle's address.
      Stage C (round+shift):
        fft_input_i <= (mult_i + (1<<14)) >>> 15
        -- uses the PREVIOUS cycle's mult_i.

    Additionally, at the S_ACCUMULATE->S_LOAD_FFT transition (rbin=0) or
    S_OUTPUT->S_LOAD_FFT transition (rbin>0), the BRAM address during the
    transition cycle depends on the stale read_doppler_index and read_range_bin
    values.

    This function models every detail to produce bit-exact FFT inputs.
    """
    # Build the 32-pt FFT engine (matching fpga_model.py)
    import math as _math
    cos_rom_32 = []
    for k in range(8):
        val = round(32767.0 * _math.cos(2.0 * _math.pi * k / 32.0))
        cos_rom_32.append(sign_extend(val & 0xFFFF, 16))

    fft32 = FFTEngine.__new__(FFTEngine)
    fft32.N = 32
    fft32.LOG2N = 5
    fft32.cos_rom = cos_rom_32
    fft32.mem_re = [0] * 32
    fft32.mem_im = [0] * 32

    # Build flat BRAM contents: addr = chirp_index * 64 + range_bin
    bram_i = [0] * TOTAL_SAMPLES
    bram_q = [0] * TOTAL_SAMPLES
    for chirp in range(CHIRPS_PER_FRAME):
        for rb in range(RANGE_BINS):
            addr = chirp * RANGE_BINS + rb
            bram_i[addr] = sign_extend(chirp_data_i[chirp][rb] & 0xFFFF, 16)
            bram_q[addr] = sign_extend(chirp_data_q[chirp][rb] & 0xFFFF, 16)

    doppler_map_i = []
    doppler_map_q = []

    # State carried across range bins (simulates the RTL registers)
    # After reset: read_doppler_index=0, read_range_bin=0, mult_i=0, mult_q=0,
    # fft_input_i=0, fft_input_q=0
    # The BRAM read is always active: mem_rdata <= doppler_i_mem[mem_read_addr]
    # mem_read_addr = read_doppler_index * 64 + read_range_bin

    # We need to track what read_doppler_index and read_range_bin are at each
    # transition, since the BRAM captures data one cycle before S_LOAD_FFT runs.

    # Before processing starts (just entered S_LOAD_FFT from S_ACCUMULATE):
    # At the S_ACCUMULATE clock that transitions:
    #   read_doppler_index <= 0 (NBA)
    #   read_range_bin <= 0 (NBA)
    # These take effect NEXT cycle. At the transition clock itself,
    # read_doppler_index and read_range_bin still had their old values.
    # From reset, both were 0. So BRAM captures addr=0*64+0=0.
    #
    # For rbin>0 transitions from S_OUTPUT:
    #   At S_OUTPUT clock:
    #     read_doppler_index <= 0  (was 0, since it wrapped from 32->0 in 5 bits)
    #     read_range_bin <= prev_rbin + 1 (NBA, takes effect next cycle)
    #   At S_OUTPUT clock, the current read_range_bin = prev_rbin,
    #   read_doppler_index = 0 (wrapped). So BRAM captures addr=0*64+prev_rbin.

    for rbin in range(RANGE_BINS):
        # Determine what BRAM data was captured during the transition clock
        # (one cycle before S_LOAD_FFT's first execution cycle).
        if rbin == 0:
            # From S_ACCUMULATE: both indices were 0 (from reset or previous NBA)
            # BRAM captures addr = 0*64+0 = 0  -> data[chirp=0][rbin=0]
            transition_bram_addr = 0 * RANGE_BINS + 0
        else:
            # From S_OUTPUT: read_doppler_index=0 (wrapped), read_range_bin=rbin-1
            # BRAM captures addr = 0*64+(rbin-1) -> data[chirp=0][rbin-1]
            transition_bram_addr = 0 * RANGE_BINS + (rbin - 1)

        transition_data_i = bram_i[transition_bram_addr]
        transition_data_q = bram_q[transition_bram_addr]

        # Now simulate the 32 cycles of S_LOAD_FFT for this range bin.
        # Register pipeline state at entry:
        mult_i_reg = 0  # From reset (rbin=0) or from end of previous S_FFT_WAIT
        mult_q_reg = 0

        fft_in_i_list = []
        fft_in_q_list = []

        for k in range(DOPPLER_FFT_SIZE):
            # read_doppler_index = k at this cycle's start
            # mem_read_addr = k * 64 + rbin

            # What mem_rdata holds THIS cycle:
            if k == 0:
                # BRAM captured transition_bram_addr last cycle
                rd_i = transition_data_i
                rd_q = transition_data_q
            else:
                # BRAM captured addr from PREVIOUS cycle: (k-1)*64 + rbin
                prev_addr = (k - 1) * RANGE_BINS + rbin
                rd_i = bram_i[prev_addr]
                rd_q = bram_q[prev_addr]

            # Stage B: multiply (uses current read_doppler_index = k)
            new_mult_i = sign_extend(rd_i & 0xFFFF, 16) * \
                         sign_extend(HAMMING_WINDOW[k] & 0xFFFF, 16)
            new_mult_q = sign_extend(rd_q & 0xFFFF, 16) * \
                         sign_extend(HAMMING_WINDOW[k] & 0xFFFF, 16)

            # Stage C: round+shift (uses PREVIOUS cycle's mult)
            fft_i = (mult_i_reg + (1 << 14)) >> 15
            fft_q = (mult_q_reg + (1 << 14)) >> 15

            fft_in_i_list.append(sign_extend(fft_i & 0xFFFF, 16))
            fft_in_q_list.append(sign_extend(fft_q & 0xFFFF, 16))

            # Update pipeline registers for next cycle
            mult_i_reg = new_mult_i
            mult_q_reg = new_mult_q

        # 32-point FFT
        fft_out_re, fft_out_im = fft32.compute(
            fft_in_i_list, fft_in_q_list, inverse=False
        )

        doppler_map_i.append(fft_out_re)
        doppler_map_q.append(fft_out_im)

    return doppler_map_i, doppler_map_q


# =============================================================================
# Test scenario definitions
# =============================================================================

def make_scenario_stationary():
    """Single stationary target at range bin ~10.  Doppler peak at bin 0."""
    targets = [Target(range_m=500, velocity_mps=0.0, rcs_dbsm=20.0)]
    return targets, "Single stationary target at ~500m (rbin~10), Doppler bin 0"


def make_scenario_moving():
    """Single target with moderate Doppler shift."""
    # v = 15 m/s → fd = 2*v*fc/c ≈ 1050 Hz
    # PRI = 167 us → Doppler bin = fd * N_chirps * PRI = 1050 * 32 * 167e-6 ≈ 5.6
    targets = [Target(range_m=500, velocity_mps=15.0, rcs_dbsm=20.0)]
    return targets, "Single moving target v=15m/s (~1050Hz Doppler, bin~5-6)"


def make_scenario_two_targets():
    """Two targets at different ranges and velocities."""
    targets = [
        Target(range_m=300, velocity_mps=10.0, rcs_dbsm=20.0),
        Target(range_m=800, velocity_mps=-20.0, rcs_dbsm=15.0),
    ]
    return targets, "Two targets: 300m/+10m/s, 800m/-20m/s"


SCENARIOS = {
    'stationary': make_scenario_stationary,
    'moving': make_scenario_moving,
    'two_targets': make_scenario_two_targets,
}


# =============================================================================
# Main generator
# =============================================================================

def generate_scenario(name, targets, description, base_dir, use_buggy_model=False):
    """Generate input hex + golden output for one scenario."""
    print(f"\n{'='*60}")
    print(f"Scenario: {name} — {description}")
    model_label = "BUGGY (RTL pipeline)" if use_buggy_model else "CLEAN"
    print(f"Model: {model_label}")
    print(f"{'='*60}")

    # Generate Doppler frame (32 chirps x 64 range bins)
    frame_i, frame_q = generate_doppler_frame(targets, seed=42)

    print(f"  Generated frame: {len(frame_i)} chirps x {len(frame_i[0])} range bins")

    # ---- Write input hex file (packed 32-bit: {Q, I}) ----
    # RTL expects data streamed chirp-by-chirp: chirp0[rb0..rb63], chirp1[rb0..rb63], ...
    packed_samples = []
    for chirp in range(CHIRPS_PER_FRAME):
        for rb in range(RANGE_BINS):
            packed_samples.append((frame_i[chirp][rb], frame_q[chirp][rb]))

    input_hex = os.path.join(base_dir, f"doppler_input_{name}.hex")
    write_hex_32bit(input_hex, packed_samples)

    # ---- Run through Python model ----
    if use_buggy_model:
        doppler_i, doppler_q = buggy_process_frame(frame_i, frame_q)
    else:
        dp = DopplerProcessor()
        doppler_i, doppler_q = dp.process_frame(frame_i, frame_q)

    print(f"  Doppler output: {len(doppler_i)} range bins x "
          f"{len(doppler_i[0])} doppler bins")

    # ---- Write golden output CSV ----
    # Format: range_bin, doppler_bin, out_i, out_q
    # Ordered same as RTL output: all doppler bins for rbin 0, then rbin 1, ...
    flat_rbin = []
    flat_dbin = []
    flat_i = []
    flat_q = []

    for rbin in range(RANGE_BINS):
        for dbin in range(DOPPLER_FFT_SIZE):
            flat_rbin.append(rbin)
            flat_dbin.append(dbin)
            flat_i.append(doppler_i[rbin][dbin])
            flat_q.append(doppler_q[rbin][dbin])

    golden_csv = os.path.join(base_dir, f"doppler_golden_py_{name}.csv")
    write_csv(golden_csv,
              ['range_bin', 'doppler_bin', 'out_i', 'out_q'],
              flat_rbin, flat_dbin, flat_i, flat_q)

    # ---- Write golden hex (for optional RTL $readmemh comparison) ----
    golden_hex = os.path.join(base_dir, f"doppler_golden_py_{name}.hex")
    write_hex_32bit(golden_hex, list(zip(flat_i, flat_q)))

    # ---- Find peak per range bin ----
    print(f"\n  Peak Doppler bins per range bin (top 5 by magnitude):")
    peak_info = []
    for rbin in range(RANGE_BINS):
        mags = [abs(doppler_i[rbin][d]) + abs(doppler_q[rbin][d])
                for d in range(DOPPLER_FFT_SIZE)]
        peak_dbin = max(range(DOPPLER_FFT_SIZE), key=lambda d: mags[d])
        peak_mag = mags[peak_dbin]
        peak_info.append((rbin, peak_dbin, peak_mag))

    # Sort by magnitude descending, show top 5
    peak_info.sort(key=lambda x: -x[2])
    for rbin, dbin, mag in peak_info[:5]:
        i_val = doppler_i[rbin][dbin]
        q_val = doppler_q[rbin][dbin]
        print(f"    rbin={rbin:2d}, dbin={dbin:2d}, mag={mag:6d}, "
              f"I={i_val:6d}, Q={q_val:6d}")

    # ---- Write frame data for debugging ----
    # Also write per-range-bin FFT input (for debugging pipeline alignment)
    if use_buggy_model:
        # Write the buggy FFT inputs for debugging
        debug_csv = os.path.join(base_dir, f"doppler_fft_inputs_{name}.csv")
        # Regenerate to capture FFT inputs
        dp_debug = DopplerProcessor()
        clean_i, clean_q = dp_debug.process_frame(frame_i, frame_q)
        # Show the difference between clean and buggy
        print(f"\n  Comparing clean vs buggy model outputs:")
        mismatches = 0
        for rbin in range(RANGE_BINS):
            for dbin in range(DOPPLER_FFT_SIZE):
                if (doppler_i[rbin][dbin] != clean_i[rbin][dbin] or
                    doppler_q[rbin][dbin] != clean_q[rbin][dbin]):
                    mismatches += 1
        total = RANGE_BINS * DOPPLER_FFT_SIZE
        print(f"    {mismatches}/{total} output samples differ "
              f"({100*mismatches/total:.1f}%)")

    return {
        'name': name,
        'description': description,
        'model': 'buggy' if use_buggy_model else 'clean',
        'peak_info': peak_info[:5],
    }


def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))

    use_buggy = '--buggy' in sys.argv

    print("=" * 60)
    print("Doppler Processor Co-Sim Golden Reference Generator")
    print(f"Model: {'BUGGY (RTL pipeline replication)' if use_buggy else 'CLEAN'}")
    print("=" * 60)

    scenarios_to_run = list(SCENARIOS.keys())

    # Check if a specific scenario was requested
    for arg in sys.argv[1:]:
        if arg.startswith('--'):
            continue
        if arg in SCENARIOS:
            scenarios_to_run = [arg]
            break

    results = []
    for name in scenarios_to_run:
        targets, description = SCENARIOS[name]()
        r = generate_scenario(name, targets, description, base_dir,
                              use_buggy_model=use_buggy)
        results.append(r)

    print(f"\n{'='*60}")
    print("Summary:")
    print(f"{'='*60}")
    for r in results:
        print(f"  {r['name']:<15s} [{r['model']}] top peak: "
              f"rbin={r['peak_info'][0][0]}, dbin={r['peak_info'][0][1]}, "
              f"mag={r['peak_info'][0][2]}")

    print(f"\nGenerated {len(results)} scenarios.")
    print(f"Files written to: {base_dir}")
    print("=" * 60)


if __name__ == '__main__':
    main()
