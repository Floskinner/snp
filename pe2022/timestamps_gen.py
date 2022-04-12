import random

start_sec = 0
start_usec = 0

for _ in range(10_000):
    print(f"{start_sec}.{start_usec}")
    start_sec += random.randint(1, 1_000)
    start_usec += random.randint(0, 100)