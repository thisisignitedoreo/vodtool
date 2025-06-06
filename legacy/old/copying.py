#!/usr/bin/env python3

import pyclip
import time
import sys

def parse_info(vodid):
    file = open(f'vods/{vodid}.txt', encoding="utf-8").read()
    file = file[1:] if file.startswith('\n') else file
    segments = file.split('\n\n')
    return segments[-1], segments[:-1]

if __name__ == "__main__":
    vodid = sys.argv[1]
    name, segment_names = parse_info(vodid)

    pyclip.copy(name)
    input('copied name; enter -> ')

    for k, i in enumerate(segment_names, start=1):
        pyclip.copy(i)
        time.sleep(1)
        input(f'copied segment name #{k}; enter -> ')

