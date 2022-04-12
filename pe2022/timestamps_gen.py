import time
import random

start_time = 0.0

for _ in range(10_000):
    print(round(start_time, 6))
    start_time += random.uniform(0, 1000000)