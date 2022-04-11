import time
import random

start_time = time.time()

for _ in range(100):
    timestamp_str = str(start_time)
    print(timestamp_str)
    start_time += random.randint(0, 1000000)