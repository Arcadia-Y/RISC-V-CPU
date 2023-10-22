# RISC-V-CPU

A toy RISC-V-CPU designed using Verilog. [Assignment for ACM-ClassCourse-2022](https://github.com/ACMClassCourse-2022/RISC-V-CPU-2023).

## Overview
Below is the diagram for the CPU.
```mermaid
graph
Mem[Memory]
ICache[Instruction Cache]
DCache[Data Cache]
IU[Instruction Unit & PC]
LSB[Load Store Buffer]
RF[Register File]
RS[Reservation Station & ALU]
ROB[Reorder Buffer]

Mem <--> ICache
Mem <--> DCache
ICache <--> IU

IU <--> RS
IU <--> LSB
IU <--> ROB
IU <--> RF

RS <--> ROB
RS <--> LSB
LSB <--> ROB
LSB <--> DCache
ROB --> RF
```
Since the CPU only contains one ALU and one LSB, we connect every two of RS, LSB and ROB for data communication, instead of using a Common Data Bus. 
