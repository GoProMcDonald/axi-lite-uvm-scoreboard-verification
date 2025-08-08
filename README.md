# AXI4-Lite UVM Verification with Scoreboard

## Overview
This project demonstrates a complete **UVM-based verification environment** for an AXI4-Lite DUT.  
It includes:
- A **driver** that drives AXI4-Lite transactions
- A **monitor** that captures bus activity
- A **scoreboard** that compares expected (exp) and actual (act) transactions
- Waveform viewing with EPWave
- Report summary with pass/fail statistics

The DUT is a simple AXI4-Lite slave model, with read and write transaction handling.

---

## Features
- **UVM Agent** with driver, sequencer, monitor
- **Transaction cloning** to feed scoreboard expected queue
- **Scoreboard**:
  - Stores expected write transactions
  - Matches read transactions with expected values
  - Reports mismatches via UVM report mechanism
- **EPWave Integration** for waveform analysis
- Fully synthesizable DUT for simulation

---

├── design.sv # AXI4-Lite Slave DUT
├── axi_if.sv # AXI4-Lite interface
├── axi_seq_item.svh # UVM transaction definition
├── axi_driver.svh # UVM driver
├── axi_monitor.svh # UVM monitor
├── axi_scoreboard.svh # UVM scoreboard
├── axi_env.svh # UVM environment
├── axi_test.svh # UVM test
├── tb_top.sv # Top-level testbench
└── README.md


---

## How It Works
1. **Sequence** generates AXI4-Lite read/write transactions.
2. **Driver** drives transactions to DUT via virtual interface.
3. **Monitor** samples bus signals, sends observed transactions to scoreboard.
4. **Scoreboard**:
   - Pushes write data into expected queue
   - On a read transaction, pops expected value and compares with DUT output
   - Reports match/mismatch via UVM_INFO / UVM_ERROR
5. **EPWave** displays bus signal waveforms; scoreboard events are in console output.

---
<img width="1002" height="584" alt="image" src="https://github.com/user-attachments/assets/285defbc-9bb5-469e-a1db-b9167519c062" />
<img width="1816" height="680" alt="image" src="https://github.com/user-attachments/assets/f7d936c4-045b-4212-9f15-060714a9d9a7" />

## Running the Simulation
1. Open project in your simulator (VCS, Questa, Xcelium, Riviera-PRO, etc.)
2. Compile:
   ```bash
   vlog +incdir+$UVM_HOME/src design.sv tb_top.sv


## File Structure
