# EECS 470 Final Project – R10K-Style Out-of-Order CPU

This repository is a personal archive of my final project for  
**EECS 470: Computer Architecture** at the University of Michigan.

The project implements a **R10K-inspired out-of-order superscalar CPU**
with an emphasis on performance, memory-level parallelism, and
microarchitectural experimentation.

---

## Microarchitecture Overview

- **Out-of-order execution** based on the R10K design
- Parameterized **N-way superscalar** pipeline
- Register renaming with physical register file
- Reservation stations, ROB, and load/store queue

---

## Memory System

- **2-bank, 4-way set-associative write-back data cache**
- Non-blocking cache with **MSHRs**
- Hardware **prefetcher** for memory latency hiding

---

## Branch Prediction

- **BTB (Branch Target Buffer)**
- Gshare
- Tournament
- Early branch resolution support

---

## Tooling & Debugging

- Cycle-level **GUI debugger**
- Extensive waveform-based and architectural state tracing

---

## Notes

This repository preserves the original commit history and experimental
branches as an academic and personal milestone.  
It is not intended for reuse or redistribution.

