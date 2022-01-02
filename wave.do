onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider Dut
add wave -noupdate /top/dut/current_state
add wave -noupdate /top/dut/header_store
add wave -noupdate /top/dut/address_store
add wave -noupdate /top/dut/data_store
add wave -noupdate /top/dut/computed_header
add wave -noupdate /top/dut/lookup_address
add wave -noupdate /top/dut/temp_data
add wave -noupdate /top/dut/address
add wave -noupdate -divider Bus
add wave -noupdate /top/bus/clk
add wave -noupdate /top/bus/reset_n
add wave -noupdate /top/bus/config_in
add wave -noupdate /top/bus/ack_in
add wave -noupdate /top/bus/receive
add wave -noupdate /top/bus/header_in
add wave -noupdate /top/bus/address_in
add wave -noupdate /top/bus/data_in
add wave -noupdate /top/bus/ready
add wave -noupdate /top/bus/ack_out
add wave -noupdate /top/bus/bad_packet
add wave -noupdate /top/bus/transmit
add wave -noupdate /top/bus/lookup
add wave -noupdate /top/bus/header_out
add wave -noupdate /top/bus/address_out
add wave -noupdate /top/bus/data_out
add wave -noupdate /top/bus/packets_ok
add wave -noupdate /top/bus/packets_fail
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {433 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ns} {3912 ns}
