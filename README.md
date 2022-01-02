# Router ASIC: Design, Verification, and Layout

## Overview
This is an implementation of a simple router (or packet switch). At a high-level, the router does the following:
-	Receive own address from ISP/service provider
-	Receive packets
-	Check if the packet is valid by matching checksum to header
-	Follows simple acknowledgement protocols
-	Lookup the destination address
-	Try to send the packet data to the new address
-	Keep count of the # of good and bad packets

The router computes checksum by counting the # of 1s in the 32-bit packet data. It then compares this computed checksum to the input header

## Design

This FSM Diagram shows the states of the router.

<img src="images/fsm.png" alt="fsm" width="700"/>
