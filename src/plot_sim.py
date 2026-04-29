import os
import sys
import json
import argparse
import glob
import re
import matplotlib.pyplot as plt

def main():
    parser = argparse.ArgumentParser(description="Plot BER vs Eb/N0 from simulation results.")
    parser.add_argument("--dir", type=str, required=True, help="Directory containing the simulation results (e.g., ebn0_0dB, ebn0_1dB...)")
    parser.add_argument("--symbol_counts", type=int, help="Number of symbols per example")
    parser.add_argument("--example_counts", type=int, help="Number of examples")
    
    args = parser.parse_args()
    
    base_dir = args.dir
    if not os.path.exists(base_dir):
        print(f"Error: Directory {base_dir} does not exist.")
        sys.exit(1)
        
    ebn0_range = range(0, 31)
    
    sc_json = None
    ec_json = None
    json_has_counts = True
    
    # Pre-scan to check symbol_counts and example_counts consistency
    for ebn0 in ebn0_range:
        folder = os.path.join(base_dir, f"ebn0_{ebn0}dB")
        if not os.path.exists(folder):
            continue
        
        config_path = os.path.join(folder, "config_meta.json")
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if 'symbol_counts' in data and 'example_counts' in data:
                    if sc_json is None and ec_json is None:
                        sc_json = data['symbol_counts']
                        ec_json = data['example_counts']
                    elif sc_json != data['symbol_counts'] or ec_json != data['example_counts']:
                        print("Error: Inconsistent symbol_counts or example_counts in config_meta.json files.")
                        sys.exit(1)
                else:
                    json_has_counts = False
                    
    symbol_counts = None
    example_counts = None
    
    if json_has_counts and sc_json is not None and ec_json is not None:
        symbol_counts = sc_json
        example_counts = ec_json
    else:
        if args.symbol_counts is not None and args.example_counts is not None:
            symbol_counts = args.symbol_counts
            example_counts = args.example_counts
        else:
            print("Error: symbol_counts and example_counts must be provided either via config_meta.json (consistently) or via command line arguments.")
            sys.exit(1)

    total_bits = symbol_counts * example_counts

    ber_data = {
        "awgn": [],
        "multipath": [],
        "eq_matlab": [],
        "baseline": [],
        "tree": [],
        "folding": [],
        "unfolding": [],
        "systolic": []
    }
    
    ebn0_list = []
    
    methods_hw = {
        "baseline": "baseline_error_bits.txt",
        "tree": "tree_error_bits.txt",
        "folding": "folding_error_bits.txt",
        "unfolding": "unfolding_error_bits.txt",
        "systolic": "systolic_array_error_bits.txt"
    }

    for ebn0 in ebn0_range:
        folder = os.path.join(base_dir, f"ebn0_{ebn0}dB")
        if not os.path.exists(folder):
            print(f"Warning: Missing folder for Eb/N0 = {ebn0}dB, skipping.")
            continue
            
        config_path = os.path.join(folder, "config_meta.json")
        if not os.path.exists(config_path):
            print(f"Error: Missing config_meta.json in {folder}")
            sys.exit(1)
            
        with open(config_path, 'r', encoding='utf-8') as f:
            meta = json.load(f)
            
        if 'bit_errors' not in meta:
            print(f"Error: Missing bit_errors in {config_path}")
            sys.exit(1)
            
        errs = meta['bit_errors']
        if "awgn_no_multipath" not in errs or "awgn_multipath_no_filter" not in errs or "awgn_multipath_with_filter" not in errs:
            print(f"Error: Missing some software bit_errors in {config_path}")
            sys.exit(1)
            
        awgn_err = float(errs["awgn_no_multipath"])
        multi_err = float(errs["awgn_multipath_no_filter"])
        eq_err = float(errs["awgn_multipath_with_filter"])
        
        hw_errs = {}
        for hw_key, hw_file in methods_hw.items():
            hw_path = os.path.join(folder, hw_file)
            if not os.path.exists(hw_path):
                print(f"Error: Missing hardware error bits file {hw_file} in {folder}")
                sys.exit(1)
            with open(hw_path, 'r') as f:
                content = f.read().strip()
                try:
                    hw_errs[hw_key] = float(content)
                except ValueError:
                    print(f"Error: Invalid number format in {hw_path}")
                    sys.exit(1)
                    
        ebn0_list.append(ebn0)
        ber_data["awgn"].append(awgn_err / total_bits)
        ber_data["multipath"].append(multi_err / total_bits)
        ber_data["eq_matlab"].append(eq_err / total_bits)
        for hw_key in methods_hw:
            ber_data[hw_key].append(hw_errs[hw_key] / total_bits)

    # Plot
    plt.figure(figsize=(9.8, 5.4), facecolor='w')
    ax = plt.gca()
    
    plt.yscale('log')
    plt.xlim(0, 30.5)
    plt.ylim(1.0e-7, 1)

    # Colors defined in equalizer_scale.m + custom ones for HW
    c_theory = [0.10, 0.10, 0.10]
    c_multi  = [0.12, 0.42, 0.82]
    c_eq     = [0.00, 0.60, 0.30]
    
    # Extend colors for HW implementations
    c_base = [0.80, 0.20, 0.20]
    c_tree = [0.80, 0.50, 0.10]
    c_fold = [0.50, 0.10, 0.80]
    c_unfold = [0.20, 0.80, 0.80]
    c_sys = [0.90, 0.10, 0.60]

    mk_sz = 4

    plt.plot(ebn0_list, ber_data["awgn"], '-o', color=c_theory, linewidth=2.0, markersize=mk_sz, markerfacecolor='w', label='AWGN')
    plt.plot(ebn0_list, ber_data["multipath"], '-o', color=c_multi, linewidth=2.0, markersize=mk_sz, markerfacecolor='w', label='Multipath (No Filter)')
    plt.plot(ebn0_list, ber_data["eq_matlab"], '-o', color=c_eq, linewidth=2.0, markersize=mk_sz, markerfacecolor='w', label='Eq Filter (MATLAB)')
    
    plt.plot(ebn0_list, ber_data["baseline"], '-s', color=c_base, linewidth=1.5, markersize=mk_sz, markerfacecolor='w', label='Eq Filter (Baseline)')
    plt.plot(ebn0_list, ber_data["tree"], '-^', color=c_tree, linewidth=1.5, markersize=mk_sz, markerfacecolor='w', label='Eq Filter (Tree)')
    plt.plot(ebn0_list, ber_data["folding"], '-v', color=c_fold, linewidth=1.5, markersize=mk_sz, markerfacecolor='w', label='Eq Filter (Folding)')
    plt.plot(ebn0_list, ber_data["unfolding"], '-d', color=c_unfold, linewidth=1.5, markersize=mk_sz, markerfacecolor='w', label='Eq Filter (Unfolding)')
    plt.plot(ebn0_list, ber_data["systolic"], '-x', color=c_sys, linewidth=1.5, markersize=mk_sz, markerfacecolor='w', label='Eq Filter (Systolic)')

    # Add threshold lines
    plt.axhline(y=1e-6, color='r', linestyle='--', linewidth=1.5)
    plt.vlines(x=23, ymin=1e-7, ymax=1, color='g', linestyle='--', linewidth=1.5)

    plt.legend(loc='lower left', frameon=False)
    plt.title('BER-Eb/N0 Performance', fontweight='bold', fontname='Times New Roman')
    plt.xlabel('Eb/N0 (dB)', fontname='Times New Roman')
    plt.ylabel('Bit Error Rate', fontname='Times New Roman')
    
    plt.grid(True, which='major', alpha=0.20)
    plt.grid(True, which='minor', alpha=0.12)
    
    for label in (ax.get_xticklabels() + ax.get_yticklabels()):
        label.set_fontname('Times New Roman')
        
    out_svg = os.path.join(base_dir, 'ber_performance.svg')
    plt.savefig(out_svg, format='svg', bbox_inches='tight')
    print(f"Successfully generated plot: {out_svg}")

if __name__ == "__main__":
    main()