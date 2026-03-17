import serial
import csv
import re
from datetime import datetime

# ── 配置 ──────────────────────────────────────────
PORT   = "COM3"   # VCOM1 对应的串口
BAUD   = 115200
OUTPUT = r"C:\Users\xhu70\Projects\twel_data_collection\data\sensor_data.csv"
# ──────────────────────────────────────────────────

# 匹配固件格式: "T=22.50C H=45.23% P=1013.25hPa"
PATTERN = re.compile(
    r"T=([-\d.]+)C\s+H=([-\d.]+)%\s+P=([-\d.]+)hPa"
)

def main():
    print(f"Opening {PORT} at {BAUD} baud...")
    print(f"Saving to: {OUTPUT}")
    print("Press Ctrl+C to stop.\n")

    with serial.Serial(PORT, BAUD, timeout=2) as ser, \
         open(OUTPUT, "a", newline="", encoding="utf-8") as f:

        writer = csv.writer(f)

        # 只在空文件时写表头
        if f.tell() == 0:
            writer.writerow(["timestamp", "temperature_c", "humidity_pct", "pressure_hpa"])
            f.flush()

        while True:
            try:
                raw = ser.readline().decode("utf-8", errors="ignore").strip()
            except Exception as e:
                print(f"[Serial error] {e}")
                continue

            if not raw:
                continue

            m = PATTERN.search(raw)
            if not m:
                # 打印非传感器行（系统日志等），方便调试
                print(f"[skip] {raw}")
                continue

            t  = float(m.group(1))
            h  = float(m.group(2))
            p  = float(m.group(3))
            ts = datetime.now().isoformat(timespec="seconds")

            writer.writerow([ts, t, h, p])
            f.flush()   # 每条立即写盘，防止断电丢数据

            print(f"{ts}  T={t:6.2f}°C  H={h:5.2f}%  P={p:8.2f}hPa")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped. Data saved.")
    except serial.SerialException as e:
        print(f"\n[Error] Cannot open {PORT}: {e}")
        print("Check: 1) Board is connected  2) PORT is correct  3) No other app using the port")