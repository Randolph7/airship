#!/bin/bash

PERF_BIN=~/perf

if tmux has-session -t benchmark 2>/dev/null; then
    tmux kill-session -t benchmark
fi

mkdir -p log

# 自动生成采集脚本 collect_jtop_stats.py（如不存在）
if [ ! -f collect_jtop_stats.py ]; then
cat > collect_jtop_stats.py << 'EOF'
#!/usr/bin/env python3
import time
import csv
from jtop import jtop

fields = [
    'time', 'CPU%', 'GPU%', 'RAM', 'SWAP'
]

def get_row(jetson):
    now = time.strftime('%Y-%m-%d %H:%M:%S')
    cpu = jetson.cpu['usage'] if 'usage' in jetson.cpu else None
    gpu = jetson.gpu['usage'] if 'usage' in jetson.gpu else None
    ram = jetson.memory['RAM'] if 'RAM' in jetson.memory else None
    swap = jetson.memory['SWAP'] if 'SWAP' in jetson.memory else None
    return [now, cpu, gpu, ram, swap]

if __name__ == "__main__":
    duration = 300  # 采集时长（秒），可根据需要调整
    interval = 1    # 采样间隔（秒）
    output = "log/jtop_python.csv"

    with jtop() as jetson, open(output, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(fields)
        start = time.time()
        while time.time() - start < duration and jetson.ok():
            row = get_row(jetson)
            writer.writerow(row)
            time.sleep(interval)
    print(f"采集完成，数据保存在 {output}")
EOF
chmod +x collect_jtop_stats.py
fi

# 自动生成分析脚本 analyze_jtop.py（如不存在或内容不同则覆盖）
cat > analyze_jtop.py << 'EOF'
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
EOF

# 自动生成 tegrastats 分析脚本 analyze_tegrastats.py
cat > analyze_tegrastats.py << 'EOF'
import re
import pandas as pd

cpu_list, gpu_list, ram_list = [], [], []

with open('log/tegrastats.log') as f:
    for line in f:
        # CPU: 提取所有 xx%@xxx
        cpu_matches = re.findall(r'(\d+)%@\d+', line)
        cpu_vals = [int(x) for x in cpu_matches]
        if cpu_vals:
            cpu_list.append(sum(cpu_vals) / len(cpu_vals))  # 取均值
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
EOF

# 启动 python 采集性能数据，后台运行
# python3 collect_jtop_stats.py &
# JTOP_PY_PID=$!

# 启动 tegrastats 采集 CPU/GPU/内存，后台运行
tegrastats --logfile log/tegrastats.log &
TEGRA_PID=$!

# 自动开启jtop交互界面到新的tmux session（如已存在则先kill再新建）
if tmux has-session -t jtop 2>/dev/null; then
    tmux kill-session -t jtop
fi
tmux new-session -d -s jtop 'jtop'

# 当脚本退出时自动结束采集并分析性能日志
trap "kill $TEGRA_PID; python3 analyze_tegrastats.py" EXIT


tmux new-session -d -s benchmark
tmux split-window -v -t benchmark:0.0
tmux split-window -h -t benchmark:0.0
tmux split-window -v -t benchmark:0.0
tmux split-window -v -t benchmark:0.2

tmux send-keys -t benchmark:0.0 "cd ~/benchmark/run && bash enable_nav.sh" C-m
tmux send-keys -t benchmark:0.1 "cd ~/benchmark/run && bash enable_perception.sh" C-m
tmux send-keys -t benchmark:0.2 "cd ~/benchmark/run && bash enable_grasp.sh" C-m
tmux send-keys -t benchmark:0.4 "cd ~/benchmark/run && bash send_inst.sh" C-m
tmux send-keys -t benchmark:0.3 "cd ~/benchmark/run && bash enable_planner.sh" C-m

# 等待各节点进程启动（可根据实际情况调整时间）
sleep 10

# 获取所有 ros2 launch 相关进程PID
PIDS=$(pgrep -d, -f "ros2 launch")

echo "统计以下进程的性能信息：$PIDS"
mkdir -p log

# 后台运行 perf 统计，输出到 log/perf_stat.log
# "$PERF_BIN" stat -I 1000 -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $PIDS > log/perf_stat.log 2>&1 &
# PERF_PID=$!

# 退出时自动结束 perf
# trap "kill $TEGRA_PID 2>/dev/null; kill $PERF_PID 2>/dev/null; python3 analyze_tegrastats.py" EXIT

tmux select-pane -t benchmark:0.4
tmux attach-session -t benchmark
