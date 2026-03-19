module waveform_generator (
    input wire CLK_IN,          // 100MHz input clock
    output reg DAC_CLOCK,       // 120MHz clock to DAC
    output reg DAC_SLEEP,       // DAC sleep control (0 = normal operation)
    output reg [7:0] DAC_DATA   // 8-bit output to DAC
);

    // Clock divider for generating 120MHz DAC clock from 100MHz input
    reg [2:0] clk_div = 0;
    always @(posedge CLK_IN) begin
        clk_div <= clk_div + 1;
        if (clk_div == 2) begin
            DAC_CLOCK <= ~DAC_CLOCK;
            clk_div <= 0;
        end
    end

    // Look-Up Table (LUT) to store precomputed waveform samples
    parameter integer n = 31;  // Number of samples per ramp (Tb/Ts)
    reg [7:0] waveform_LUT [0:n-1];
    
    initial begin
        // Precomputed LUT values based on Python script
waveform_LUT[0] = 8'h80;
waveform_LUT[1] = 8'h89;
waveform_LUT[2] = 8'h99;
waveform_LUT[3] = 8'hAE;
waveform_LUT[4] = 8'hC7;
waveform_LUT[5] = 8'hE1;
waveform_LUT[6] = 8'hF6;
waveform_LUT[7] = 8'hFF;
waveform_LUT[8] = 8'hF4;
waveform_LUT[9] = 8'hCF;
waveform_LUT[10] = 8'h92;
waveform_LUT[11] = 8'h4B;
waveform_LUT[12] = 8'h11;
waveform_LUT[13] = 8'h02;
waveform_LUT[14] = 8'h2E;
waveform_LUT[15] = 8'h8A;
waveform_LUT[16] = 8'hE4;
waveform_LUT[17] = 8'hFC;
waveform_LUT[18] = 8'hB6;
waveform_LUT[19] = 8'h3F;
waveform_LUT[20] = 8'h00;
waveform_LUT[21] = 8'h41;
waveform_LUT[22] = 8'hC8;
waveform_LUT[23] = 8'hFC;
waveform_LUT[24] = 8'h91;
waveform_LUT[25] = 8'h0C;
waveform_LUT[26] = 8'h2E;
waveform_LUT[27] = 8'hD0;
waveform_LUT[28] = 8'hED;
waveform_LUT[29] = 8'h4A;
waveform_LUT[30] = 8'h09;
        DAC_SLEEP = 0; // Enable DAC operation
    end

    // Counter to step through the LUT
    reg [9:0] index = 0;
    always @(posedge DAC_CLOCK) begin
        DAC_DATA <= waveform_LUT[index];
        index <= index + 1;
        if (index >= n) index <= 0; // Repeat the waveform
    end

endmodule
