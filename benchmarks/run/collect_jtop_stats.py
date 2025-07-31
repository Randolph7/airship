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
