module adc_interface (
    input wire CLK_IN,      // 100 MHz clock input
    input wire rst,         // Reset signal
    output wire ADC_CLK,    // 60 MHz clock output to ADC
    output reg ADC_OE,      // Output enable (0 = enable)
    output reg ADC_PD,      // Power down (0 = normal operation)
    input wire [9:0] ADC_DATA, // 10-bit parallel ADC data input
    output reg [9:0] sampled_data // Captured ADC data
);

    // Clocking Wizard or PLL/MMCM should be instantiated here to generate 60MHz ADC_CLK
    wire clk_60MHz;
    
    // Instantiate clock generator (example with MMCM/PLL instantiation needed)
    clk_wiz_0 clk_gen (
        .clk_in1(CLK_IN),
        .clk_out1(clk_60MHz), // 60 MHz clock output
        .reset(1'b0),
        .locked()
    );
    
    assign ADC_CLK = clk_60MHz;
    
    // ADC control signals initialization
    always @(posedge CLK_IN or posedge rst) begin
        if (rst) begin
            ADC_OE <= 1'b1; // Default disabled
            ADC_PD <= 1'b1; // Default power down
        end else begin
            ADC_OE <= 1'b0; // Enable ADC
            ADC_PD <= 1'b0; // Normal operation
        end
    end
    
    // Capture ADC data on ADC_CLK rising edge
    always @(posedge clk_60MHz) begin
        sampled_data <= ADC_DATA;
    end
    
endmodule