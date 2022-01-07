// Include uvm macros at this level so that they are available globally to all functions in this file
`include "uvm_macros.svh"

// timestep/time precision
`timescale 1ns/1ns
package router_pkg;

	import uvm_pkg::*;

	// set time for packet acknowledgent delay
	// - SINGLE/DOUBLE = successful transfer
	// - LATE = packet failed to forward
	typedef enum {SINGLE, DOUBLE, LATE} delay_t;

	// router packet transaction item
	class router_packet extends uvm_sequence_item;

		// data inputs
		rand bit config_in;
		rand bit  [5:0] header_in;
		rand bit [11:0] address_in;
		rand bit [31:0] data_in;

		// control signals
		rand delay_t delay;
		rand bit valid_header;

		//output signals
		bit ack_out;
		bit ack_in;
		bit bad_packet;
		bit  [5:0] header_out;
		bit [11:0] address_out;
		bit [31:0] data_out;
		
		// Constraints
		// prevent data packets from resetting the configuration
		constraint c_config   { config_in == 0;}

		// set header and data based on valid_header random variable
		constraint c_valid_header    { valid_header == 1 -> header_in == $countones(data_in);}

		// headers should be valid 90% of the time
		constraint valid_header_dist { valid_header dist { 0 := 1, 1 := 9}; }

		// packets should acknowledged properly 90% of the time
		constraint delay_dist { delay dist { SINGLE := 5, DOUBLE := 4, LATE := 1}; }

		// implement standard "do*" functions using uvm macros
		`uvm_object_utils_begin(router_packet)
			`uvm_field_int(config_in, UVM_DEFAULT)
			`uvm_field_int(header_in, UVM_DEFAULT)
			`uvm_field_int(address_in, UVM_DEFAULT)
			`uvm_field_int(data_in, UVM_DEFAULT)
			`uvm_field_enum(delay_t, delay, UVM_DEFAULT)
			`uvm_field_int(valid_header, UVM_DEFAULT)
			`uvm_field_int(ack_out, UVM_DEFAULT)
			`uvm_field_int(ack_in, UVM_DEFAULT)
			`uvm_field_int(bad_packet, UVM_DEFAULT)
			`uvm_field_int(header_out, UVM_DEFAULT)
			`uvm_field_int(address_out, UVM_DEFAULT)
			`uvm_field_int(data_out, UVM_DEFAULT)
		`uvm_object_utils_end

		// required for uvm_objects, different from uvm_components
		function new(string name = "router packet");
			super.new(name);
		endfunction
	endclass

	class packet_sequence extends uvm_sequence;
		`uvm_object_utils(packet_sequence)

		function new(string name="packet sequence");
			super.new(name);
		endfunction

		// allow for a random number of data packets
		rand int num;
		constraint c_num {soft num inside {[30:50]};}

		task body();
			repeat(num) begin

				// use factory method to create a packet object
				router_packet packet = router_packet::type_id::create("packet");

				// prepare uvm_sequence_item to be sent to driver
				start_item(packet);
				if (!packet.randomize())
					`uvm_error("packet_sequence", "Randomize Failed!");

				// Tell sequencer to send packet to driver
				finish_item(packet);

			end
		endtask
	endclass

	// Driver controls pin level inputs to router
	class router_driver extends uvm_driver #(router_packet);
		`uvm_component_utils(router_driver)

		// mandatory constructor
		function new(string name, uvm_component parent);
			super.new(name,parent);
		endfunction

		// handle to virtual interface
		virtual router_if vif;

		// get instance from config_db 
		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			if(!uvm_config_db#(virtual router_if)::get(this, "", "router_vif", vif))
				`uvm_fatal("router_driver", "uvm_config_db::get failed");
		endfunction


		task run_phase(uvm_phase phase);
			super.run_phase(phase);
			forever begin
				router_packet m_packet; // handle for packet
				seq_item_port.get_next_item(m_packet); // grab packet from FIFO through TLM port
				m_packet.print();
				wait(vif.ready === 1); // wait if router is not ready

				@(vif.cb);

				// set inputs to router pins
				vif.receive    <= 1;
				vif.config_in  <= m_packet.config_in;
				vif.header_in  <= m_packet.header_in;
				vif.address_in <= m_packet.address_in;
				vif.data_in    <= m_packet.data_in;

				// allow for both posibililities without assuming packet validity
				wait(vif.ack_out === 1 || vif.bad_packet === 1);
				// send packet acknowledgement for possible delay values
				// if packet acknowledged by router
				if(vif.ack_out === 1) begin

					wait(vif.transmit);
					case(m_packet.delay)
						SINGLE: begin
							@(vif.cb);
							vif.ack_in <= 1;
							end
						DOUBLE: begin
							wait(vif.transmit === 0);
							vif.ack_in <= 1;
							end
					endcase
				end

				@(vif.cb);

				vif.ack_in  <= 0;
				vif.receive <= 0;

				// signal to sequencer to send next packet
				seq_item_port.item_done();
			end
		endtask : run_phase
	endclass

	// looks at outputs and creates a router packet
	// sends that packet to the scoreboard using an analysis port
	class router_monitor extends uvm_monitor;
		`uvm_component_utils(router_monitor)

		function new(string name, uvm_component parent);
			super.new(name, parent);
		endfunction

		// analysis port for sending recorded packets to scoreboard
		uvm_analysis_port #(router_packet) monitor_analysis_port;

		// handle to virtual inteface		
		virtual router_if vif;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			if(!uvm_config_db#(virtual router_if)::get(this, "", "router_vif", vif))
				`uvm_fatal("router_driver", "uvm_config_db::get failed");

			// initialize analysis port that subscribers will connect to
			monitor_analysis_port = new("monitor analysis port", this);
		endfunction

		task run_phase(uvm_phase phase);
			super.run_phase(phase);

			forever begin
				router_packet m_packet = new(); // alternate form of creating new instance

				wait(vif.ready === 1 && vif.receive === 1);

				// read packet inputs while they are valid
				m_packet.config_in  = vif.config_in;
				m_packet.header_in  = vif.header_in;
				m_packet.address_in = vif.address_in;
				m_packet.data_in   = vif.data_in;

				// wait for packet success or failure
				wait(vif.ack_out === 1 || vif.bad_packet === 1);
				// send packet acknowledgement for possible delay values
				// if packet acknowledged by router
				if(vif.ack_out === 1) begin
					m_packet.ack_out = vif.ack_out;
					m_packet.valid_header = 1;

					wait(vif.transmit);
					// save data values, considered valid when transmit is high
					m_packet.header_out  = vif.header_out;
					m_packet.address_out = vif.address_out;
					m_packet.data_out    = vif.data_out;
					
					// wait for on-time vs late acknowledgement
					wait(vif.ack_in === 1 || vif.bad_packet === 1);

					if(vif.ack_in === 1) begin
						m_packet.ack_in = 1;
						if( vif.transmit ) m_packet.delay = SINGLE;
						else m_packet.delay = DOUBLE;
					end else begin
						m_packet.delay = LATE;
						m_packet.bad_packet = 1;
					end

				end else if(vif.bad_packet === 1) begin
					m_packet.bad_packet = vif.bad_packet;
				end else begin
					`uvm_error(get_type_name(), "[Monitor] Encountered unknown packet result")
				end

				wait(vif.ready)
				// send completed packet to subscribers through analysis port
				monitor_analysis_port.write(m_packet);

			end
		endtask
	endclass

	// encapsulates and connects TLM ports for:
	// driver, monitor, and sequencer
	class router_agent extends uvm_agent;
		`uvm_component_utils(router_agent);

		function new(string name, uvm_component parent);
			super.new(name, parent);
		endfunction

		router_driver driver_inst;
		router_monitor monitor_inst;

		// instantiate a regular uvm_sequencer parameterized with router_packet
		// don't need to make a subclass 
		uvm_sequencer #(router_packet) sequencer_inst;


		// create instances of each uvm_component using factory methods
		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			sequencer_inst = uvm_sequencer #(router_packet)::type_id::create("sequencer_inst", this);
			driver_inst    =  router_driver::type_id::create("driver_inst", this);
			monitor_inst   = router_monitor::type_id::create("monitor_inst", this);
		endfunction

		// connect TLM ports
		// sequencer seq_item_export is attacted to the driver seq_item_port
		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			driver_inst.seq_item_port.connect(sequencer_inst.seq_item_export);
		endfunction
	endclass

	class router_scoreboard extends uvm_scoreboard;
		`uvm_component_utils(router_scoreboard)

		function new(string name="scoreboard", uvm_component parent=null);
			super.new(name, parent);
		endfunction

		// parametrized handle for the analysis
		// receives packets from the monitor analysis port
		uvm_analysis_imp #(router_packet, router_scoreboard) monitor_analysis_import;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			// create instance of the monitor analysis port
			monitor_analysis_import = new("monitor_analysis_import", this);
		endfunction

		function write(router_packet item);

			// make sure that packet is not a configuration packet (out of scope for this test)
			if(item.header_in !== 0) begin

				// tests for valid packets
				if (item.valid_header) begin

					if (item.header_in == $countones(item.data_in)) 
						 `uvm_info(get_type_name(), "header valid", UVM_HIGH)
					else `uvm_error(get_type_name(), "valid_header == 1 but actual header invalid")

					if (item.ack_out) 
						`uvm_info(get_type_name(), "acknowledgement", UVM_HIGH)
					else `uvm_error(get_type_name(), "no acknowledgement")

					if(item.ack_in) begin
						if (item.delay == SINGLE || item.delay == DOUBLE) 
							`uvm_info(get_type_name(), "correct delay", UVM_HIGH)
						else `uvm_error(get_type_name(), "incorrect delay")

					end else begin
						if (item.delay == LATE && item.bad_packet) 
							`uvm_info(get_type_name(), "correct lateness", UVM_HIGH)
						else `uvm_error(get_type_name(), "failed late packet check")
					end

				// tests for packets with invalid data/header
				end else begin

					if (item.header_in !== $countones(item.data_in)) 
						 `uvm_info(get_type_name(), "header valid", UVM_HIGH)
					else `uvm_error(get_type_name(), "valid_header == 0 but actual header valid")

					if (item.ack_out === 0 && item.ack_in === 0) 
						`uvm_info(get_type_name(), "acknowledgements correct", UVM_HIGH)
					else `uvm_error(get_type_name(), "acknowledgement on bad packet")

					if (item.bad_packet === 1) 
						`uvm_info(get_type_name(), "correct error", UVM_HIGH)
					else `uvm_error(get_type_name(), "expected error")

				end
			end
		endfunction

	endclass

	// encapsulates agent and scoreboard
	class router_env extends uvm_env;
		`uvm_component_utils(router_env)

		function new(string name="env", uvm_component parent=null);
			super.new(name, parent);
		endfunction

		router_agent agent_inst;
		router_scoreboard sb_inst;

		// instantiate agent and scoreboard
		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			agent_inst = router_agent::type_id::create("agent_inst", this);
			sb_inst = router_scoreboard::type_id::create("sb_inst", this);
		endfunction

		// connect monitor analysis port to scoreboard import
		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
				agent_inst.
				monitor_inst.
				monitor_analysis_port.connect(sb_inst.monitor_analysis_import);
		endfunction
	endclass

	// holds environment and run reset/config procedures
	class router_test extends uvm_test;
		`uvm_component_utils(router_test)

		function new(string name="env", uvm_component parent=null);
			super.new(name, parent);
		endfunction

		router_env env_inst;
		virtual router_if vif;

		// get virtual interface from
		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			env_inst = router_env::type_id::create("env_inst", this);
			if(!uvm_config_db#(virtual router_if)::get(this, "", "router_vif", vif))
				`uvm_fatal("router_test", "uvm_config_db::get failed");

		endfunction

		// prepare router to receive packets
		task reset_and_configure();
			vif.reset_n <= 0;
			vif.ack_in  <= 0;
			repeat(5) @(vif.cb);
			vif.reset_n <= 1;

			// receive config signal to enter config mode
			@(vif.cb);
			vif.receive   <= 0;
			vif.config_in <= 1;
		
			// in this test the router will be assigned an address of all 1s
			@(vif.cb);
			vif.config_in <= 0; // ensure router does not go into config mode again
			vif.receive   <= 1;
			vif.data_in   <= 32'h00000_fff;
			// wait for router to enter ready and stay there for 2 clock cycles
			// receive is low because we do not want the router to start listening yet
			@(vif.cb);
			vif.receive <= 0;
			repeat(5) @(vif.cb);
		endtask


		task run_phase(uvm_phase phase);

			// create instance of sequence and set number of packets randomly
			packet_sequence seq = packet_sequence::type_id::create("seq");
			if (!seq.randomize())
					`uvm_error("packet_sequence", "Randomize Failed!");

			// prevents test from ending
			phase.raise_objection(this);

			reset_and_configure();

			// tell sequencer to start sending packets to driver
			seq.start(env_inst.agent_inst.sequencer_inst);

			#1000;

			// simulation ends after last objection dropped
			phase.drop_objection(this);
		endtask


	endclass
		
endpackage

module top;

	import uvm_pkg::*;
	import router_pkg::*;

	bit clk;

	initial begin
		clk = 0;
		forever #10 clk = ~clk;
	end

	router_if bus(.clk);
	router dut(.bus);

	initial begin
		uvm_config_db#(virtual router_if)::set(null, "*", "router_vif", bus);
		uvm_top.finish_on_completion = 1;
		run_test("router_test"); // standard uvm function for running uvm_test objects
	end

endmodule