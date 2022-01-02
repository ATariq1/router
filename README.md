# Router ASIC: Design, Verification, and Layout
This repo contains the SystemVerilog HDL code for simple router. The router design has the following components:
- FSM design
- UVM testbench for constrained random verification
- Synthesized netlist using Cadence RC
- Layout using Cadence Innovus for a 45nm technology node
- Spice netlist and gate-level simulation with all parasitic capacitances using Cadence Virtuoso

## Design
This is an implementation of a simple router (or packet switch). At a high-level, the router does the following:
-	Receive own address from ISP/service provider
-	Receive packets
-	Check if the packet is valid by matching checksum to header
-	Follows simple acknowledgement protocols
-	Lookup the destination address
-	Try to send the packet data to the new address
-	Keep count of the # of good and bad packets

The router computes checksum by counting the # of 1s in the 32-bit packet data. It then compares this computed checksum to the input header
This FSM Diagram shows the states of the router.

<img src="images/fsm.png" alt="fsm" width="700"/>

## UVM Testbench
The UVM testbench tests the router using randomly generated data packets. Specifically, the test looks at how the router responds to valid and invalid inputs.

<img src="images/uvm_block_diagram.png" alt="uvm" width="700"/>

## Synthesis and Layout

## Spice Extraction and Simulation
