`timescale 1ns/1ns

interface router_if(input bit clk);
	// INPUTS
	logic        reset_n;      // active low asynchronous reset
	logic        config_in;    // input that puts router into config state
	logic        ack_in; 	   // indicates to router that packet received by destination
	logic 	     receive;      // indicates to router that data packet data is valid
	logic  [5:0] header_in;    // checksum value. MUST be equal to # 1s in data packet binary value
	logic [11:0] address_in;   // incoming address to router
	logic [31:0] data_in;      // actual incoming packet data. 32 bit packets in this case but can be parametrized
  
	// OUTPUTS  
	logic 	     ready;		   // indicates to senders that this router is ready to receive packets
	logic 	     ack_out;	   // indicates to senders that the packet was received and forwarded successfully
	logic        bad_packet;   // indicates to sender that packet was not valid
	logic        transmit;     // indicate to destination that data is valid
	logic 	     lookup;       // signal to dns table that data out is a header that needs to be looked up
	logic  [5:0] header_out;   // output checksum value. Must be equal to # of 1s in data packet binary value
	logic [11:0] address_out;  // output address
	logic [31:0] data_out;     // data output port for router. Used to send data to either the next router or the lookup table
	logic [31:0] packets_ok;   // # of packets that were sent successfully
	logic [31:0] packets_fail; // # of packets that got corrupted

	clocking cb @(posedge clk);
		default input #1 output #2;
		input ready, ack_out, bad_packet, transmit, lookup, header_out, address_out, data_out, packets_ok, packets_fail;
		output reset_n, config_in, ack_in, receive, header_in, address_in, data_in;
	endclocking

endinterface

module router (router_if bus);

// setup enum for all 10 states
typedef enum {OFFLINE, CONFIG, READY, CHECKSUM, ACK, LOOKUP, TRANSMIT, CONFIRM, RETRY, ERROR} state;
state current_state;

// setup internal registers
// Storing received packet data
logic  [5:0] header_store;
logic [11:0] address_store;
logic [31:0] data_store;

// storing data that was either calculated or looked up from DNS module
logic  [5:0] computed_header;
logic [11:0] lookup_address;
logic [31:0] temp_data;

// address config data assigned to this router
logic [11:0] address;

// instantiate resolver module
masker resolver(.address_in(address_store), .address_out(lookup_address));

always_ff @(posedge bus.clk or negedge bus.reset_n) begin 

	if(~bus.reset_n) begin
		// set to idle state
		current_state   <= OFFLINE;
		// set store registers to 0
		header_store    <=  6'b0;
		address_store   <= 12'b0;
		data_store      <= 32'b0;
		// set calculation registers to 0
		computed_header <=  6'b0;
		temp_data       <= 32'b0;
		// router address initialized to 0
		address         <= 12'b0;
		// set module outputs to 0
		bus.packets_ok      <= 32'b0;
		bus.packets_fail    <= 32'b0;

	end else begin
		 case(current_state)

		 	// In the OFFLINE state the router is waiting to be configured by the internet service provider (ISP)
		 	OFFLINE: begin
		 		if (bus.config_in == 1'b1) begin
		 			current_state <= CONFIG;
		 		end
		 	end

		 	// In the CONFIG state:
		 	// if the address sent through the data_in port is 0
		 	//		- router sent back to OFFLINE mode
		 	//		- address is kept
		 	// if the value on data_in[11:0] is > 0:
		 	// 		- address is assigned
		 	//		- state becomes ready
		 	CONFIG: begin
		 		if (bus.receive == 1'b1) begin

		 			if (bus.data_in[11:0] == 12'b0) begin
		 				current_state <= OFFLINE;
		 			end

		 			else begin
		 				address       <= bus.data_in[11:0];
		 				current_state <= READY;
		 			end
		 		end
		 	end

		 	// In the READY state:
		 	// if config_in go back to config state
		 	// if recieving data, then store packet and go to CHECKSUM state
		 	// otherwise stay in READY
		 	READY: begin
		 		if (bus.config_in == 1'b1) begin
		 			current_state <= CONFIG;
		 		end

		 		else if (bus.receive == 1'b1) begin
		 			header_store    <= bus.header_in;
		 			address_store   <= bus.address_in;
		 			data_store      <= bus.data_in;
		 			temp_data       <= bus.data_in; // will be modifying this register to calculate checksum
		 			computed_header <= 6'b0;    // resetting computed header for checksum section
		 			current_state   <= CHECKSUM;
		 		end
		 	end

		 	// In the CHECKSUM state:
		 	// the checksum is computed for the in_data
		 	// Here the state will compute the # of 1s in the data packet by shifting the temp_data variable 32 times
		 	// this will save on cell count and increase 
		 	CHECKSUM: begin
		 		if (temp_data > 32'b0) begin
		 			// add the rightmost bit to computed_header
		 			// if it is a 1 then it will automatically be incremented
		 			computed_header <= computed_header + temp_data[0]; 
		 			temp_data       <= temp_data >> 1;

		 		end else begin

		 			// if checksum matches the one sent by the source router then it will continue the forwarding
		 			// if it is not a match the router will increment the packets_fail output in the ERROR state
		 			if (computed_header == header_store) 
		 				current_state <= ACK;
		 			else
		 				current_state <= ERROR;
		 		end
		 	end

		 	// The ACK state is for notifying the previous router by toggling the ack_out signal
		 	// only enter this state if the packet checksum is correct
		 	ACK: begin
		 		current_state <= LOOKUP;
		 	end

		 	// In the lOOKUP state the router completes a transaction with the resolver module
		 	// The resolver module takes the current stored address and performs some operation on it
		 	// This is useful because different resolver modules can be used depending on how you want addresses converted
		 	LOOKUP: begin
		 		address_store <= lookup_address;
		 		current_state <= TRANSMIT;
		 	end


		 	// in the TRANSMIT stage the router does its first attempt at sending data
		 	TRANSMIT: begin
		 		current_state <= CONFIRM;
		 	end

		 	// in the CONFIRM state the transmit bit is still high and the router is waiting for ack_in to go high
		 	// if confirmation is received then the router goes back to READY
		 	// increments count of good packets sent
		 	CONFIRM: begin
		 		if (bus.ack_in) begin
		 			bus.packets_ok    <= bus.packets_ok + 1;
		 			current_state <= READY;
		 		end else
		 			current_state <= RETRY;
		 	end

		 	// the RETRY state is the last attempt to wait for a confirmation
		 	// if no confirmation is received then the packet is counted as a bad packet
		 	RETRY: begin
		 		if (bus.ack_in) begin
		 			bus.packets_ok    <= bus.packets_ok + 1;
		 			current_state <= READY;
		 		end else
		 			current_state <= ERROR;
		 	end

		 	// enter ERROR state if packet is corrupted or not sent
		 	// also as a default state
		 	ERROR: begin
		 		bus.packets_fail  <= bus.packets_fail + 1;
		 		current_state <= READY;
		 	end

		 	// in case something goes wrong
		 	default: begin
		 		current_state <= ERROR;
		 	end

		endcase
	end
end


// assign 1 bit outputs that are based on state only
assign bus.ready       = current_state == READY   ;
assign bus.ack_out     = current_state == ACK     ;
assign bus.lookup      = current_state == LOOKUP  ;
assign bus.bad_packet  = current_state == ERROR   ;
// two attempts at transmitting and receiving confirmation
assign bus.transmit    = current_state == TRANSMIT || current_state == CONFIRM;

// assign data outputs based on stored data
assign bus.header_out  = header_store   ;
assign bus.address_out = address_store  ;  
assign bus.data_out    = data_store     ;

endmodule : router


// for this case, a simple masking resolver is used for address lookup
module masker (
	input  logic [11:0] address_in,  // takes in the input address and masks a few bits
	output logic [11:0] address_out
	);

	assign address_out = address_in & 12'b0011_1111_1100;

endmodule

