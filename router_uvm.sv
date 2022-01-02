`include "uvm_macros.svh"
`timescale 1ns/1ns
package router_pkg;

	import uvm_pkg::*;
	typedef enum {SINGLE, DOUBLE, LATE} delay_t;

	// router packet transaction item
	// TODO: derive into data and config packets
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
		constraint c_config   { config_in == 0;}
		constraint c_valid_header    { valid_header == 1 -> header_in == $countones(data_in);}
		constraint valid_header_dist { valid_header dist { 0 := 1, 1 := 9}; }
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

		function new(string name = "router packet");
			super.new(name);
		endfunction
	endclass

	class packet_sequence extends uvm_sequence;
		`uvm_object_utils(packet_sequence)

		function new(string name="packet sequence");
			super.new(name);
		endfunction

		rand int num;
		constraint c_num {soft num inside {[30:50]};}

		task body();
			repeat(num) begin
				router_packet packet = router_packet::type_id::create("packet");
				
				start_item(packet);
				if (!packet.randomize())
					`uvm_error("packet_sequence", "Randomize Failed!");
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

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			if(!uvm_config_db#(virtual router_if)::get(this, "", "router_vif", vif))
				`uvm_fatal("router_driver", "uvm_config_db::get failed");
		endfunction


		task run_phase(uvm_phase phase);
			super.run_phase(phase);
			forever begin
				router_packet m_packet; // handle to packet
				seq_item_port.get_next_item(m_packet); // received packet through sequencer
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

		uvm_analysis_port #(router_packet) monitor_analysis_port;
		int delay_count;
		
		virtual router_if vif;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			if(!uvm_config_db#(virtual router_if)::get(this, "", "router_vif", vif))
				`uvm_fatal("router_driver", "uvm_config_db::get failed");
			monitor_analysis_port = new("monitor analysis port", this);
		endfunction

		task run_phase(uvm_phase phase);
			super.run_phase(phase);

			forever begin
				router_packet m_packet = new(); // Sus
				delay_count = 0;
				wait(vif.ready === 1 && vif.receive === 1);
				m_packet.config_in  = vif.config_in;
				m_packet.header_in  = vif.header_in;
				m_packet.address_in = vif.address_in;
				m_packet.data_in   = vif.data_in;

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
		uvm_sequencer #(router_packet) sequencer_inst;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			sequencer_inst = uvm_sequencer #(router_packet)::type_id::create("sequencer_inst", this);
			driver_inst   =  router_driver::type_id::create("driver_inst", this);
			monitor_inst  = router_monitor::type_id::create("monitor_inst", this);
		endfunction

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

		uvm_analysis_imp #(router_packet, router_scoreboard) monitor_analysis_import;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			monitor_analysis_import = new("monitor_analysis_import", this);
		endfunction

		function write(router_packet item);

			if(item.header_in !== 0) begin

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

	class router_env extends uvm_env;
		`uvm_component_utils(router_env)

		function new(string name="env", uvm_component parent=null);
			super.new(name, parent);
		endfunction

		router_agent agent_inst;
		router_scoreboard sb_inst;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			agent_inst = router_agent::type_id::create("agent_inst", this);
			sb_inst = router_scoreboard::type_id::create("sb_inst", this);
		endfunction

		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			agent_inst.
			monitor_inst.
			monitor_analysis_port.
			connect(sb_inst.monitor_analysis_import);
		endfunction
	endclass

	class router_test extends uvm_test;
		`uvm_component_utils(router_test)

		function new(string name="env", uvm_component parent=null);
			super.new(name, parent);
		endfunction

		router_env env_inst;
		virtual router_if vif;

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			env_inst = router_env::type_id::create("env_inst", this);
			if(!uvm_config_db#(virtual router_if)::get(this, "", "router_vif", vif))
				`uvm_fatal("router_test", "uvm_config_db::get failed");

		endfunction

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

			packet_sequence seq = packet_sequence::type_id::create("seq");
			if (!seq.randomize())
					`uvm_error("packet_sequence", "Randomize Failed!");

			phase.raise_objection(this);
			reset_and_configure();

			seq.start(env_inst.agent_inst.sequencer_inst);

			#1000;
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
		run_test("router_test");
	end

endmodule