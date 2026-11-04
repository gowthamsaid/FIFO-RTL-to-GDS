# Shared constraints for matched FIFO experiments.
# No current_design command: the RTL top differs between the two architectures.
create_clock -name core_clock -period 2.0 [get_ports clk]
set_input_delay 0.2 -clock core_clock [all_inputs -no_clocks]
set_output_delay 0.2 -clock core_clock [all_outputs]
