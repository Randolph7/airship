import re
import pandas as pd

cpu_list, gpu_list, ram_list = [], [], []

with open('log/tegrastats.log') as f:
    for line in f:
        # CPU: Extract all xx%@xxx
        cpu_matches = re.findall(r'(\d+)%@\d+', line)
        cpu_vals = [int(x) for x in cpu_matches]
        if cpu_vals:
            cpu_list.append(sum(cpu_vals) / len(cpu_vals))  # Take average
        # GPU: GR3D_FREQ xx%
        gpu_match = re.search(r'GR3D_FREQ (\d+)%', line)
        if gpu_match:
            gpu_list.append(int(gpu_match.group(1)))
        # RAM: RAM used/totalMB
        ram_match = re.search(r'RAM (\d+)/(\d+)MB', line)
        if ram_match:
            ram_list.append(int(ram_match.group(1)))

def stat(arr, name, f):
    if arr:
        s = pd.Series(arr)
        f.write(f'{name}: mean={s.mean():.2f}, max={max(arr)}, min={min(arr)}\n')
    else:
        f.write(f'{name}: no data\n')

with open('log/tegrastats_summary.txt', 'w') as f:
    stat(cpu_list, 'CPU%', f)
    stat(gpu_list, 'GPU%', f)
    stat(ram_list, 'RAM(MB)', f)
