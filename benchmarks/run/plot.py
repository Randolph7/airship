import matplotlib.pyplot as plt
from datetime import datetime
import matplotlib.dates as mdates


def parse_log(file, label):
    starts, ends, delays = [], [], []
    with open(file) as f:
        for line in f:
            if 'start:' in line and 'end:' in line and 'latency:' in line:
                try:
                    start = line.split('start: ')[1].split(',')[0]
                    end = line.split('end: ')[1].split(',')[0]
                    latency = float(line.split('latency: ')[1].split(' ')[0])
                    starts.append(datetime.strptime(start, "%Y-%m-%d %H:%M:%S"))
                    ends.append(datetime.strptime(end, "%Y-%m-%d %H:%M:%S"))
                    delays.append(latency)
                except Exception as e:
                    print(f"Parse error: {e} in line: {line}")
    return starts, ends, delays, label

logs = [
    ('/tmp/nav_callback_delay.log', 'navigation'),
    ('/tmp/grasp_callback_delay.log', 'grasp'),
    ('/tmp/seg_callback_delay.log', 'segmentation'),
    ('/tmp/llm_callback_delay.log', 'llm_planner'),
]

plt.figure(figsize=(12, 7))
markers = ['o', 's', '^', 'D']
colors = ['tab:blue', 'tab:orange', 'tab:green', 'tab:red']
plots = []
for idx, (file, label) in enumerate(logs):
    try:
        starts, ends, delays, label = parse_log(file, label)
        # 画点
        p = plt.scatter(starts, delays, marker=markers[idx % len(markers)], color=colors[idx % len(colors)], label=label, s=80, alpha=0.8)
        # 画线段
        for s, e, d in zip(starts, ends, delays):
            plt.plot([s, e], [d, d], color=colors[idx % len(colors)], alpha=0.5, linewidth=2)
        plots.append((p, starts, ends, delays, label))
    except Exception as e:
        print(f"Skip {file}: {e}")

plt.xlabel('Start/End Time', fontsize=14)
plt.ylabel('Callback Latency (ms, log scale)', fontsize=14)
plt.title('Callback Latency Timeline of Each Node', fontsize=16)
plt.yscale('log')
plt.legend(fontsize=14)
plt.tight_layout()
plt.grid(True, which="both", ls="--", linewidth=0.5)
plt.gca().xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
plt.gcf().autofmt_xdate()

# Add interactive hover
try:
    import mplcursors
    cursor = mplcursors.cursor([p[0] for p in plots], hover=True)
    @cursor.connect("add")
    def on_add(sel):
        for p, starts, ends, delays, label in plots:
            if sel.artist == p:
                idx = sel.index
                sel.annotation.set(text=f"{label}\nStart: {starts[idx]}\nEnd: {ends[idx]}\nLatency: {delays[idx]:.2f} ms")
                break
except ImportError:
    print("mplcursors not installed, hover info disabled.")

plt.show()