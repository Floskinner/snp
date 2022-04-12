import time
import random

start_time = 0.0

for _ in range(10_000):
    print(start_time)
    start_time += random.uniform(0, 1000000)