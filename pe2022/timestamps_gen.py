import time
import random

start_time = time.time()

for _ in range(100):
    print(start_time)
    start_time += random.randint(0, 1000000)