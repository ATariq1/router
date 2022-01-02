`timescale 1ns/1ps
// Ideally this router should run at a very fast frequency
// That is why I chose to do checksum in multiple clock cycles instead of 1
// Aiming for 2 to 3 GHz depending on implementation and technology node limitations
module router_tb();

	bit clk;

	router_if bus( .clk);

	// instantiate router instance
	router dut( .bus );

always begin
	clk = 0;
	#1;
	clk = 1;
	#1;
end

initial begin

	//=============================================================================
	// SETUP PHASE:
	//=============================================================================

	// Putting router into reset phase for 10 clock cycles
	bus.reset_n    <= 0;

	// initializing the input variables.
	// In the beginning: 
	bus.config_in  <= 0;    // router is in state where it does not recieve config
	bus.ack_in     <= 0;    // no acknowledgement
	bus.receive    <= 0;    // no packets received 

	// packet inputs are all empty
	bus.header_in  <=  6'b0;
	bus.address_in <= 12'b0;
	bus.data_in    <= 32'b0;

	#20;

	// Letting router *stay* in OFFLINE mode remain there for another 4 clock cycles
	bus.reset_n <= 1;
	#8;

	//=============================================================================
	// OFFLINE -> CONFIG -> OFFLINE
	//=============================================================================

	// wait for a posedge to enter config mode and stay for 2 clock cycles
	@(posedge clk)
	bus.config_in <= 1;
	#4;

	// The router will go back into offline mode becaus it received all 0 data in the config mode 
	wait(dut.current_state == dut.CONFIG);
	bus.config_in <= 0;
	bus.receive   <= 1;
	# 4;

	//=============================================================================
	// OFFLINE -> CONFIG -> READY
	//=============================================================================

	// receive config signal to enter config mode
	@(posedge clk)
	bus.receive   <= 0;
	bus.config_in <= 1;
	#4;

	// in this test the router will be assigned an address of all 1s
	@(posedge clk)
	bus.config_in <= 0; // ensure router does not go into config mode again
	bus.receive   <= 1;
	bus.data_in   <= 32'h00000_fff;
	// wait for router to enter ready and stay there for 2 clock cycles
	// receive is low because we do not want the router to start listening yet
	@(posedge bus.ready)
	bus.receive <= 0;
	# 4;


	// at this point the router has been assigned an address of 12'hfff and is ready to receive packets

	//=============================================================================
	// READY -> CHECKSUM -> ERROR -> READY
	//=============================================================================
	// now the router is in ready and waiting for real data packets
	// in this example, the packet will not pass the checksum. 
	// because there are 12 "1"s in the data packet but the header says there should be 13
	@(posedge clk)
	bus.receive    <= 1;
	bus.data_in    <= 32'h00000_fff;
	bus.header_in  <= 6'd13;
	bus.address_in <= 12'hf0f;

	@(posedge bus.bad_packet)
	assert(bus.bad_packet == 1);

	// make sure bad packet count incremented when in ready state
	@(posedge bus.ready)
	bus.receive <= 0;
	assert(bus.packets_fail == 1);
	#4;

	//=============================================================================
	// READY -> CHECKSUM -> ACK
	//=============================================================================
	// in this test a packet with all ones will be sent to the router
	// this ensures it can handle the corner case with 32 "1"s
	// this section goes up to the ACK state where the acknowledgement will be sent

	@(posedge clk)
	bus.receive    <= 1;
	bus.data_in    <= 32'hff_ff_ff_ff;
	bus.header_in  <= 6'd32;
	bus.address_in <= 12'hf0f;

	wait(dut.current_state == dut.CHECKSUM);
	bus.receive <= 0;

	@(posedge bus.ack_out)
	assert(dut.computed_header == 32);
	assert(bus.ack_out == 1);


	//=============================================================================
	// ACK -> LOOKUP -> TRANSMIT -> CONFIRM -> READY
	//=============================================================================
	// This is a continuation of the previous test
	// we will see the packet being sent and the router return to ready state after 1 successfullB attempt to send
	@(posedge bus.lookup)
	// make sure that the masker is resolving to the right address
	assert( dut.lookup_address == 12'h30C)

	@(posedge bus.transmit)
	// make sure that the router has stored the new address
	assert(bus.address_out == 12'h30C);
	assert(dut.address_store == 12'h30C);

	// signal to router that packet is received
	wait(dut.current_state == dut.CONFIRM);
	bus.ack_in <= 1;

	// lower ack_in and make sure that the packet was sent sucessfully and packet count incremented
	@(posedge bus.ready)
	bus.ack_in <= 0;
	assert(bus.transmit == 0);
	assert(bus.packets_ok == 1);

	#8;
	//=============================================================================
	// READY -> CHECKSUM -> ACK -> LOOKUP -> TRANSMIT -> CONFIRM -> RETRY -> READY
	//=============================================================================
	// This is a FULL packet send test where it takes two tries to send the packet

	@(posedge clk)
	bus.receive    <= 1;
	bus.data_in    <= 32'b0101_0101_0101_0101_0101_0101_0101_0101;
	bus.header_in  <= 6'd16;
	bus.address_in <= 12'b1111_1111_1111;

	// stop sending data once router moves to CHECKSUM state
	wait(dut.current_state == dut.CHECKSUM);
	bus.receive   <= 0;

	// check if computed header is correct in ACK state
	@(posedge bus.ack_out)
	assert(dut.computed_header == 6'd16);

	// check if correct lookup address in LOOKUP state
	@(posedge bus.lookup)
	assert(dut.lookup_address == 12'b0011_1111_1100);


	// ensure that router is outputting correct address in TRANSMIT
	@(posedge bus.transmit)
	assert(bus.address_out == 12'b0011_1111_1100);

	// let router go to RETRY before sending confirmation
	wait(dut.current_state == dut.RETRY);
	bus.ack_in <= 1;

	// check if packet count incremented
	@(posedge bus.ready)
	bus.ack_in <= 0;
	assert(bus.packets_ok == 2);

	//=============================================================================
	// READY -> CHECKSUM -> ACK -> LOOKUP -> TRANSMIT -> CONFIRM -> RETRY -> ERROR -> READY
	//=============================================================================
	// This is a FULL packet send test where it takes two tries but fails to receive acknowledgement of the packet
	// This test has all 0 packet inputs to test if the states return the correct values for empty data
	@(posedge clk)
	bus.receive    <= 1;
	bus.data_in    <= 32'b0;
	bus.header_in  <= 6'd0;
	bus.address_in <= 12'b0;

	// stop sending once devide in checksum state
	// could also wait for negedge of ready
	wait(dut.current_state == dut.CHECKSUM);
	bus.receive   <= 0;

	// make sure computed header is correct once ACK state is reached
	@(posedge bus.ack_out)
	assert(dut.computed_header == 6'd0);


	// check if lookup address is corret
	@(posedge bus.lookup)
	assert(dut.lookup_address == 12'b0);

	// check if address_out is ok during TRANSMIT
	@(posedge bus.transmit)
	assert(bus.address_out == 12'b0);

	// no confirmation received so ensure ERROR state reached
	wait(dut.current_state == dut.ERROR);
	assert(bus.bad_packet)

	// go to ready and make sure bad packet count incremented
	@(posedge bus.ready)
	bus.ack_in <= 0;
	assert(bus.packets_fail == 2);

	#8;
	//=============================================================================
	// READY -> CONFIG -> OFFLINE
	//=============================================================================
	// This is the final test where the router will be taken offline

	// start config because router is in READY
	@(posedge clk)
	bus.config_in <= 1;


	// send receive along with data[11:0] == 0 which will cause router to go offline
	wait(dut.current_state == dut.CONFIG);
	bus.receive    <= 1;
	bus.data_in    <= 32'b0;
	bus.header_in  <= 6'd0;
	bus.address_in <= 12'b0;


	// stop configuration once router is offline
	wait(dut.current_state == dut.OFFLINE);
	bus.config_in <= 0;

    #4;
	$stop;
end

endmodule : router_tb
