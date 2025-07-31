import pandas as pd
import sys
import ast

csv_path = sys.argv[1] if len(sys.argv) > 1 else 'log/jtop_python.csv'
out_path = sys.argv[2] if len(sys.argv) > 2 else 'log/jtop_python_summary.txt'

def extract_used(val):
    if pd.isna(val):
        return None
    if isinstance(val, (int, float)):
        return val
    try:
        d = ast.literal_eval(val)
        if isinstance(d, dict) and 'used' in d:
            return d['used']
    except Exception:
        pass
    return None

try:
    df = pd.read_csv(csv_path)
except Exception as e:
    print(f"Failed to read {csv_path}: {e}")
    sys.exit(1)

fields = ['RAM', 'SWAP']
with open(out_path, 'w') as f:
    f.write(f"jtop summary for {csv_path}\n")
    for field in fields:
        if field in df.columns:
            col = df[field]
            if field in ['RAM', 'SWAP']:
                col = col.apply(extract_used)
            col = pd.to_numeric(col, errors='coerce')
            f.write(f"\n{field} statistics (used):\n")
            f.write(f"  Mean: {col.mean():.2f}\n")
            f.write(f"  Max: {col.max():.2f}\n")
            f.write(f"  Min: {col.min():.2f}\n")
        else:
            f.write(f"{field} not found in columns.\n")
