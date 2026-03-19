`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    21:30:14 03/06/2025 
// Design Name: 
// Module Name:    FPGA_Controller 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module FPGA_Controller(
    input wire CLK_IN,         // 100MHz input clock
    input wire DIG_0,          // Control signal TX or RX (ADAR1000 + RF Switch)
    input wire DIG_1,          // Reset FT2232 from µC
    input wire DIG_2,          // Enable RX Mixer
    input wire DIG_3,          // Enable TX Mixer
    output wire ADC_CLOCK,
    output reg ADC_PD,
    output reg ADC_OE,
    input wire [9:0] ADC_DATA, // 10-bit data from ADC
    output wire DAC_CLOCK,     // Clock for DAC
    output wire [7:0] DAC_DATA, // Data to DAC
    output wire DAC_SLEEP,
    input wire STM32_SCLK,
    input wire STM32_MOSI,
    output wire STM32_MISO,
    input wire STM32_CS_ADAR_1,
    input wire STM32_CS_ADAR_2,
    input wire STM32_CS_ADAR_3,
    input wire STM32_CS_ADAR_4,
    output wire SPI_SCLK_1V8,
    output wire SPI_MOSI_1V8,
    input wire SPI_MISO_1V8,
    output wire CS_ADAR_1V8_1,
    output wire CS_ADAR_1V8_2,
    output wire CS_ADAR_1V8_3,
    output wire CS_ADAR_1V8_4,
    output reg ADAR_TR1,
    output reg ADAR_TR2,
    output reg ADAR_TR3,
    output reg ADAR_TR4,
    output reg ADAR_TX_LOAD_1,
    output reg ADAR_TX_LOAD_2,
    output reg ADAR_TX_LOAD_3,
    output reg ADAR_TX_LOAD_4,
    output reg ADAR_RX_LOAD_1,
    output reg ADAR_RX_LOAD_2,
    output reg ADAR_RX_LOAD_3,
    output reg ADAR_RX_LOAD_4,
    output reg M3S_VCTRL,
    output wire MIX_TX_EN,
    output wire MIX_RX_EN,
    output wire [7:0] AD_Bus,   // Bus to FT2232HQ
    output wire FT_WR,          // Write control for FT2232H
    input FT_TXE,
    input wire FT_CLKOUT,
    output wire FT_OE,
    output wire FT_RD
);

    // Parameters
    parameter integer DAC_DURATION = 1200;  // 10µs at 120MHz (1200 cycles)
    parameter integer ADC_DURATION = 2400;  // 20µs at 120MHz (2400 cycles)

        // State Machine States
    localparam IDLE = 2'b00;
    localparam DAC_ACTIVE = 2'b01;
    localparam ADC_ACTIVE = 2'b10;

    reg [1:0] state; // 2-bit state register

    // Counter
    reg [31:0] counter;

    // ADC Active Signal
    reg adc_active;
	 
	     // Internal signal for DAC_SLEEP
    reg dac_sleep_reg; // Internal reg to drive DAC_SLEEP

    // Assign DAC_SLEEP to the internal reg
    assign DAC_SLEEP = dac_sleep_reg;

    assign SPI_SCLK_1V8 = STM32_SCLK;
    assign SPI_MOSI_1V8 = STM32_MOSI;
    assign STM32_MISO = SPI_MISO_1V8;
    
    assign CS_ADAR_1V8_1 = STM32_CS_ADAR_1;
    assign CS_ADAR_1V8_2 = STM32_CS_ADAR_2;
    assign CS_ADAR_1V8_3 = STM32_CS_ADAR_3;
    assign CS_ADAR_1V8_4 = STM32_CS_ADAR_4;
    
    assign MIX_TX_EN = DIG_3;
    assign MIX_RX_EN = DIG_2;
    
    always @(*) begin
        if (DIG_0) begin
			ADC_OE = 1'b0;  // Enable ADC  Output enable (0 = enable)
			ADC_PD = 1'b0; // Power down (0 = normal operation)
            ADAR_TR1 = 1;
            ADAR_TR2 = 1;
            ADAR_TR3 = 1;
            ADAR_TR4 = 1;
            M3S_VCTRL = 0;
			ADAR_TX_LOAD_1 = 0;
			ADAR_TX_LOAD_2 = 0;
			ADAR_TX_LOAD_3 = 0;
			ADAR_TX_LOAD_4 = 0;
			ADAR_RX_LOAD_1 = 0;
			ADAR_RX_LOAD_2 = 0;
			ADAR_RX_LOAD_3 = 0;
			ADAR_RX_LOAD_4 = 0;
        end else begin
			ADC_OE = 1'b0;  // Enable ADC  Output enable (0 = enable)
			ADC_PD = 1'b0; // Power down (0 = normal operation)
            ADAR_TR1 = 0;
            ADAR_TR2 = 0;
            ADAR_TR3 = 0;
            ADAR_TR4 = 0;
            M3S_VCTRL = 1;
			ADAR_TX_LOAD_1 = 0;
			ADAR_TX_LOAD_2 = 0;
			ADAR_TX_LOAD_3 = 0;
			ADAR_TX_LOAD_4 = 0;
			ADAR_RX_LOAD_1 = 0;
			ADAR_RX_LOAD_2 = 0;
			ADAR_RX_LOAD_3 = 0;
			ADAR_RX_LOAD_4 = 0;
        end
    end

    // Clock generation (assumes DAC needs 120MHz, adjust if needed)
  Clock_120MHz Clock_out
   (// Clock in ports
    .CLK_IN(CLK_IN),      // IN
    // Clock out ports
    .CLK_OUT_120MHz(CLK_OUT_120MHz),     // OUT
    .CLK_OUT_60MHz(CLK_OUT_60MHz));    // OUT
	 
	 assign DAC_CLOCK = CLK_OUT_120MHz;
	 assign ADC_CLOCK = CLK_OUT_60MHz;

    // Instantiate waveform generator
    waveform_generator waveform_gen (
        .DAC_CLOCK(CLK_OUT_120MHz),
		  .DAC_SLEEP(DAC_SLEEP),
        .DAC_DATA(DAC_DATA)
    );

    // Instantiate ADC interface
	 wire [9:0] ADC_sampled_data;
    adc_interface adc_intf (
        .ADC_CLK(ADC_CLOCK),
        .ADC_DATA(ADC_DATA),
		.ADC_sampled_data(ADC_sampled_data)
    );

    // Instantiate FT2232H FIFO Transmitter
    ft2232h_245_sync ft2232h_245_sync (
        .clk(ADC_CLOCK), // 60 MHz clock
        .reset(DIG_1),
        .ADC_DATA(ADC_sampled_data[9:2]), // 8-bit data from ADC
        .AD_Bus(AD_Bus),
        .oe(FT_OE),
        .rd(FT_RD),
        .txe(FT_TXE),
        .wr(FT_WR),
        .clkout_ft2232(FT_CLKOUT),
        .adc_active(adc_active) // ADC active signal
    );
// State Machine
    always @(posedge CLK_OUT_120MHz or posedge DIG_1) begin
        if (DIG_1) begin
            state <= IDLE;
            counter <= 0;
            dac_sleep_reg <= 1'b1; // Put DAC to sleep initially
            adc_active <= 1'b0; // ADC inactive initially
        end else begin
            case (state)
                IDLE: begin
                    state <= DAC_ACTIVE;
                    counter <= 0;
                    dac_sleep_reg <= 1'b0; // Wake up DAC
                    adc_active <= 1'b0; // ADC inactive
                end

                DAC_ACTIVE: begin
                    if (counter < DAC_DURATION) begin
                        counter <= counter + 1;
                    end else begin
                        state <= ADC_ACTIVE;
                        counter <= 0;
                        dac_sleep_reg <= 1'b1; // Put DAC to sleep
                        adc_active <= 1'b1; // Activate ADC
                    end
                end

                ADC_ACTIVE: begin
                    if (counter < ADC_DURATION) begin
                        counter <= counter + 1;
                    end else begin
                        state <= IDLE;
                        counter <= 0;
                        adc_active <= 1'b0; // Deactivate ADC
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

// Waveform Generator Module
module waveform_generator (
    input wire DAC_CLOCK,
	 input wire DAC_SLEEP,
    output reg [7:0] DAC_DATA
);
    
    parameter integer n = 1200;
    reg [7:0] waveform_LUT [0:n-1];
 initial begin
	waveform_LUT[0] = 8'h80;
	waveform_LUT[1] = 8'h80;
	waveform_LUT[2] = 8'h80;
	waveform_LUT[3] = 8'h80;
	waveform_LUT[4] = 8'h81;
	waveform_LUT[5] = 8'h82;
	waveform_LUT[6] = 8'h82;
	waveform_LUT[7] = 8'h84;
	waveform_LUT[8] = 8'h85;
	waveform_LUT[9] = 8'h86;
	waveform_LUT[10] = 8'h88;
	waveform_LUT[11] = 8'h8A;
	waveform_LUT[12] = 8'h8B;
	waveform_LUT[13] = 8'h8E;
	waveform_LUT[14] = 8'h90;
	waveform_LUT[15] = 8'h92;
	waveform_LUT[16] = 8'h95;
	waveform_LUT[17] = 8'h97;
	waveform_LUT[18] = 8'h9A;
	waveform_LUT[19] = 8'h9D;
	waveform_LUT[20] = 8'hA0;
	waveform_LUT[21] = 8'hA4;
	waveform_LUT[22] = 8'hA7;
	waveform_LUT[23] = 8'hAB;
	waveform_LUT[24] = 8'hAE;
	waveform_LUT[25] = 8'hB2;
	waveform_LUT[26] = 8'hB6;
	waveform_LUT[27] = 8'hBA;
	waveform_LUT[28] = 8'hBE;
	waveform_LUT[29] = 8'hC2;
	waveform_LUT[30] = 8'hC6;
	waveform_LUT[31] = 8'hCA;
	waveform_LUT[32] = 8'hCE;
	waveform_LUT[33] = 8'hD3;
	waveform_LUT[34] = 8'hD7;
	waveform_LUT[35] = 8'hDB;
	waveform_LUT[36] = 8'hDF;
	waveform_LUT[37] = 8'hE3;
	waveform_LUT[38] = 8'hE6;
	waveform_LUT[39] = 8'hEA;
	waveform_LUT[40] = 8'hED;
	waveform_LUT[41] = 8'hF1;
	waveform_LUT[42] = 8'hF4;
	waveform_LUT[43] = 8'hF6;
	waveform_LUT[44] = 8'hF9;
	waveform_LUT[45] = 8'hFB;
	waveform_LUT[46] = 8'hFC;
	waveform_LUT[47] = 8'hFE;
	waveform_LUT[48] = 8'hFE;
	waveform_LUT[49] = 8'hFE;
	waveform_LUT[50] = 8'hFE;
	waveform_LUT[51] = 8'hFD;
	waveform_LUT[52] = 8'hFC;
	waveform_LUT[53] = 8'hFA;
	waveform_LUT[54] = 8'hF7;
	waveform_LUT[55] = 8'hF4;
	waveform_LUT[56] = 8'hF0;
	waveform_LUT[57] = 8'hEB;
	waveform_LUT[58] = 8'hE6;
	waveform_LUT[59] = 8'hE0;
	waveform_LUT[60] = 8'hD9;
	waveform_LUT[61] = 8'hD2;
	waveform_LUT[62] = 8'hCA;
	waveform_LUT[63] = 8'hC1;
	waveform_LUT[64] = 8'hB8;
	waveform_LUT[65] = 8'hAE;
	waveform_LUT[66] = 8'hA4;
	waveform_LUT[67] = 8'h99;
	waveform_LUT[68] = 8'h8E;
	waveform_LUT[69] = 8'h83;
	waveform_LUT[70] = 8'h77;
	waveform_LUT[71] = 8'h6C;
	waveform_LUT[72] = 8'h60;
	waveform_LUT[73] = 8'h54;
	waveform_LUT[74] = 8'h49;
	waveform_LUT[75] = 8'h3E;
	waveform_LUT[76] = 8'h34;
	waveform_LUT[77] = 8'h2A;
	waveform_LUT[78] = 8'h21;
	waveform_LUT[79] = 8'h19;
	waveform_LUT[80] = 8'h12;
	waveform_LUT[81] = 8'h0B;
	waveform_LUT[82] = 8'h07;
	waveform_LUT[83] = 8'h03;
	waveform_LUT[84] = 8'h01;
	waveform_LUT[85] = 8'h01;
	waveform_LUT[86] = 8'h02;
	waveform_LUT[87] = 8'h04;
	waveform_LUT[88] = 8'h08;
	waveform_LUT[89] = 8'h0E;
	waveform_LUT[90] = 8'h16;
	waveform_LUT[91] = 8'h1F;
	waveform_LUT[92] = 8'h2A;
	waveform_LUT[93] = 8'h35;
	waveform_LUT[94] = 8'h43;
	waveform_LUT[95] = 8'h51;
	waveform_LUT[96] = 8'h60;
	waveform_LUT[97] = 8'h70;
	waveform_LUT[98] = 8'h80;
	waveform_LUT[99] = 8'h90;
	waveform_LUT[100] = 8'hA0;
	waveform_LUT[101] = 8'hB0;
	waveform_LUT[102] = 8'hBF;
	waveform_LUT[103] = 8'hCD;
	waveform_LUT[104] = 8'hDA;
	waveform_LUT[105] = 8'hE6;
	waveform_LUT[106] = 8'hEF;
	waveform_LUT[107] = 8'hF6;
	waveform_LUT[108] = 8'hFB;
	waveform_LUT[109] = 8'hFE;
	waveform_LUT[110] = 8'hFE;
	waveform_LUT[111] = 8'hFC;
	waveform_LUT[112] = 8'hF7;
	waveform_LUT[113] = 8'hEF;
	waveform_LUT[114] = 8'hE4;
	waveform_LUT[115] = 8'hD8;
	waveform_LUT[116] = 8'hC9;
	waveform_LUT[117] = 8'hB8;
	waveform_LUT[118] = 8'hA6;
	waveform_LUT[119] = 8'h93;
	waveform_LUT[120] = 8'h7F;
	waveform_LUT[121] = 8'h6C;
	waveform_LUT[122] = 8'h58;
	waveform_LUT[123] = 8'h45;
	waveform_LUT[124] = 8'h34;
	waveform_LUT[125] = 8'h24;
	waveform_LUT[126] = 8'h17;
	waveform_LUT[127] = 8'h0D;
	waveform_LUT[128] = 8'h05;
	waveform_LUT[129] = 8'h01;
	waveform_LUT[130] = 8'h01;
	waveform_LUT[131] = 8'h04;
	waveform_LUT[132] = 8'h0B;
	waveform_LUT[133] = 8'h15;
	waveform_LUT[134] = 8'h23;
	waveform_LUT[135] = 8'h34;
	waveform_LUT[136] = 8'h47;
	waveform_LUT[137] = 8'h5C;
	waveform_LUT[138] = 8'h73;
	waveform_LUT[139] = 8'h8A;
	waveform_LUT[140] = 8'hA0;
	waveform_LUT[141] = 8'hB6;
	waveform_LUT[142] = 8'hCA;
	waveform_LUT[143] = 8'hDC;
	waveform_LUT[144] = 8'hEB;
	waveform_LUT[145] = 8'hF6;
	waveform_LUT[146] = 8'hFC;
	waveform_LUT[147] = 8'hFE;
	waveform_LUT[148] = 8'hFC;
	waveform_LUT[149] = 8'hF5;
	waveform_LUT[150] = 8'hE9;
	waveform_LUT[151] = 8'hD9;
	waveform_LUT[152] = 8'hC6;
	waveform_LUT[153] = 8'hAF;
	waveform_LUT[154] = 8'h97;
	waveform_LUT[155] = 8'h7D;
	waveform_LUT[156] = 8'h64;
	waveform_LUT[157] = 8'h4B;
	waveform_LUT[158] = 8'h35;
	waveform_LUT[159] = 8'h21;
	waveform_LUT[160] = 8'h11;
	waveform_LUT[161] = 8'h07;
	waveform_LUT[162] = 8'h01;
	waveform_LUT[163] = 8'h01;
	waveform_LUT[164] = 8'h07;
	waveform_LUT[165] = 8'h13;
	waveform_LUT[166] = 8'h23;
	waveform_LUT[167] = 8'h38;
	waveform_LUT[168] = 8'h51;
	waveform_LUT[169] = 8'h6C;
	waveform_LUT[170] = 8'h88;
	waveform_LUT[171] = 8'hA4;
	waveform_LUT[172] = 8'hBE;
	waveform_LUT[173] = 8'hD5;
	waveform_LUT[174] = 8'hE8;
	waveform_LUT[175] = 8'hF6;
	waveform_LUT[176] = 8'hFD;
	waveform_LUT[177] = 8'hFE;
	waveform_LUT[178] = 8'hF8;
	waveform_LUT[179] = 8'hEC;
	waveform_LUT[180] = 8'hD9;
	waveform_LUT[181] = 8'hC2;
	waveform_LUT[182] = 8'hA6;
	waveform_LUT[183] = 8'h89;
	waveform_LUT[184] = 8'h6A;
	waveform_LUT[185] = 8'h4D;
	waveform_LUT[186] = 8'h32;
	waveform_LUT[187] = 8'h1C;
	waveform_LUT[188] = 8'h0C;
	waveform_LUT[189] = 8'h03;
	waveform_LUT[190] = 8'h01;
	waveform_LUT[191] = 8'h07;
	waveform_LUT[192] = 8'h14;
	waveform_LUT[193] = 8'h29;
	waveform_LUT[194] = 8'h43;
	waveform_LUT[195] = 8'h61;
	waveform_LUT[196] = 8'h81;
	waveform_LUT[197] = 8'hA1;
	waveform_LUT[198] = 8'hBF;
	waveform_LUT[199] = 8'hD9;
	waveform_LUT[200] = 8'hEE;
	waveform_LUT[201] = 8'hFA;
	waveform_LUT[202] = 8'hFE;
	waveform_LUT[203] = 8'hFA;
	waveform_LUT[204] = 8'hED;
	waveform_LUT[205] = 8'hD8;
	waveform_LUT[206] = 8'hBC;
	waveform_LUT[207] = 8'h9C;
	waveform_LUT[208] = 8'h7A;
	waveform_LUT[209] = 8'h58;
	waveform_LUT[210] = 8'h39;
	waveform_LUT[211] = 8'h1F;
	waveform_LUT[212] = 8'h0C;
	waveform_LUT[213] = 8'h02;
	waveform_LUT[214] = 8'h02;
	waveform_LUT[215] = 8'h0B;
	waveform_LUT[216] = 8'h1E;
	waveform_LUT[217] = 8'h38;
	waveform_LUT[218] = 8'h59;
	waveform_LUT[219] = 8'h7C;
	waveform_LUT[220] = 8'hA0;
	waveform_LUT[221] = 8'hC2;
	waveform_LUT[222] = 8'hDE;
	waveform_LUT[223] = 8'hF2;
	waveform_LUT[224] = 8'hFD;
	waveform_LUT[225] = 8'hFD;
	waveform_LUT[226] = 8'hF2;
	waveform_LUT[227] = 8'hDD;
	waveform_LUT[228] = 8'hC0;
	waveform_LUT[229] = 8'h9D;
	waveform_LUT[230] = 8'h77;
	waveform_LUT[231] = 8'h52;
	waveform_LUT[232] = 8'h31;
	waveform_LUT[233] = 8'h16;
	waveform_LUT[234] = 8'h06;
	waveform_LUT[235] = 8'h01;
	waveform_LUT[236] = 8'h07;
	waveform_LUT[237] = 8'h19;
	waveform_LUT[238] = 8'h35;
	waveform_LUT[239] = 8'h58;
	waveform_LUT[240] = 8'h80;
	waveform_LUT[241] = 8'hA7;
	waveform_LUT[242] = 8'hCA;
	waveform_LUT[243] = 8'hE7;
	waveform_LUT[244] = 8'hF9;
	waveform_LUT[245] = 8'hFE;
	waveform_LUT[246] = 8'hF7;
	waveform_LUT[247] = 8'hE4;
	waveform_LUT[248] = 8'hC6;
	waveform_LUT[249] = 8'hA0;
	waveform_LUT[250] = 8'h77;
	waveform_LUT[251] = 8'h4F;
	waveform_LUT[252] = 8'h2B;
	waveform_LUT[253] = 8'h11;
	waveform_LUT[254] = 8'h03;
	waveform_LUT[255] = 8'h02;
	waveform_LUT[256] = 8'h0F;
	waveform_LUT[257] = 8'h29;
	waveform_LUT[258] = 8'h4C;
	waveform_LUT[259] = 8'h76;
	waveform_LUT[260] = 8'hA0;
	waveform_LUT[261] = 8'hC8;
	waveform_LUT[262] = 8'hE6;
	waveform_LUT[263] = 8'hF9;
	waveform_LUT[264] = 8'hFE;
	waveform_LUT[265] = 8'hF4;
	waveform_LUT[266] = 8'hDC;
	waveform_LUT[267] = 8'hB8;
	waveform_LUT[268] = 8'h8E;
	waveform_LUT[269] = 8'h62;
	waveform_LUT[270] = 8'h39;
	waveform_LUT[271] = 8'h19;
	waveform_LUT[272] = 8'h05;
	waveform_LUT[273] = 8'h01;
	waveform_LUT[274] = 8'h0D;
	waveform_LUT[275] = 8'h27;
	waveform_LUT[276] = 8'h4D;
	waveform_LUT[277] = 8'h7A;
	waveform_LUT[278] = 8'hA7;
	waveform_LUT[279] = 8'hD0;
	waveform_LUT[280] = 8'hEE;
	waveform_LUT[281] = 8'hFD;
	waveform_LUT[282] = 8'hFC;
	waveform_LUT[283] = 8'hEA;
	waveform_LUT[284] = 8'hC9;
	waveform_LUT[285] = 8'h9E;
	waveform_LUT[286] = 8'h6F;
	waveform_LUT[287] = 8'h42;
	waveform_LUT[288] = 8'h1E;
	waveform_LUT[289] = 8'h07;
	waveform_LUT[290] = 8'h01;
	waveform_LUT[291] = 8'h0D;
	waveform_LUT[292] = 8'h2A;
	waveform_LUT[293] = 8'h53;
	waveform_LUT[294] = 8'h83;
	waveform_LUT[295] = 8'hB2;
	waveform_LUT[296] = 8'hDA;
	waveform_LUT[297] = 8'hF5;
	waveform_LUT[298] = 8'hFE;
	waveform_LUT[299] = 8'hF5;
	waveform_LUT[300] = 8'hD9;
	waveform_LUT[301] = 8'hB0;
	waveform_LUT[302] = 8'h7F;
	waveform_LUT[303] = 8'h4E;
	waveform_LUT[304] = 8'h25;
	waveform_LUT[305] = 8'h09;
	waveform_LUT[306] = 8'h01;
	waveform_LUT[307] = 8'h0C;
	waveform_LUT[308] = 8'h2A;
	waveform_LUT[309] = 8'h55;
	waveform_LUT[310] = 8'h88;
	waveform_LUT[311] = 8'hB9;
	waveform_LUT[312] = 8'hE1;
	waveform_LUT[313] = 8'hF9;
	waveform_LUT[314] = 8'hFD;
	waveform_LUT[315] = 8'hEC;
	waveform_LUT[316] = 8'hC9;
	waveform_LUT[317] = 8'h99;
	waveform_LUT[318] = 8'h65;
	waveform_LUT[319] = 8'h35;
	waveform_LUT[320] = 8'h11;
	waveform_LUT[321] = 8'h01;
	waveform_LUT[322] = 8'h07;
	waveform_LUT[323] = 8'h22;
	waveform_LUT[324] = 8'h4D;
	waveform_LUT[325] = 8'h82;
	waveform_LUT[326] = 8'hB6;
	waveform_LUT[327] = 8'hE1;
	waveform_LUT[328] = 8'hFA;
	waveform_LUT[329] = 8'hFD;
	waveform_LUT[330] = 8'hE9;
	waveform_LUT[331] = 8'hC2;
	waveform_LUT[332] = 8'h8E;
	waveform_LUT[333] = 8'h57;
	waveform_LUT[334] = 8'h28;
	waveform_LUT[335] = 8'h09;
	waveform_LUT[336] = 8'h01;
	waveform_LUT[337] = 8'h10;
	waveform_LUT[338] = 8'h35;
	waveform_LUT[339] = 8'h68;
	waveform_LUT[340] = 8'hA0;
	waveform_LUT[341] = 8'hD2;
	waveform_LUT[342] = 8'hF4;
	waveform_LUT[343] = 8'hFE;
	waveform_LUT[344] = 8'hF0;
	waveform_LUT[345] = 8'hCB;
	waveform_LUT[346] = 8'h97;
	waveform_LUT[347] = 8'h5E;
	waveform_LUT[348] = 8'h2B;
	waveform_LUT[349] = 8'h0A;
	waveform_LUT[350] = 8'h01;
	waveform_LUT[351] = 8'h12;
	waveform_LUT[352] = 8'h39;
	waveform_LUT[353] = 8'h70;
	waveform_LUT[354] = 8'hAA;
	waveform_LUT[355] = 8'hDB;
	waveform_LUT[356] = 8'hF9;
	waveform_LUT[357] = 8'hFD;
	waveform_LUT[358] = 8'hE6;
	waveform_LUT[359] = 8'hB9;
	waveform_LUT[360] = 8'h7F;
	waveform_LUT[361] = 8'h46;
	waveform_LUT[362] = 8'h19;
	waveform_LUT[363] = 8'h02;
	waveform_LUT[364] = 8'h07;
	waveform_LUT[365] = 8'h27;
	waveform_LUT[366] = 8'h5B;
	waveform_LUT[367] = 8'h97;
	waveform_LUT[368] = 8'hCE;
	waveform_LUT[369] = 8'hF4;
	waveform_LUT[370] = 8'hFE;
	waveform_LUT[371] = 8'hEC;
	waveform_LUT[372] = 8'hC0;
	waveform_LUT[373] = 8'h85;
	waveform_LUT[374] = 8'h49;
	waveform_LUT[375] = 8'h19;
	waveform_LUT[376] = 8'h02;
	waveform_LUT[377] = 8'h08;
	waveform_LUT[378] = 8'h2B;
	waveform_LUT[379] = 8'h62;
	waveform_LUT[380] = 8'hA0;
	waveform_LUT[381] = 8'hD7;
	waveform_LUT[382] = 8'hF8;
	waveform_LUT[383] = 8'hFC;
	waveform_LUT[384] = 8'hE1;
	waveform_LUT[385] = 8'hAE;
	waveform_LUT[386] = 8'h6F;
	waveform_LUT[387] = 8'h34;
	waveform_LUT[388] = 8'h0C;
	waveform_LUT[389] = 8'h01;
	waveform_LUT[390] = 8'h16;
	waveform_LUT[391] = 8'h46;
	waveform_LUT[392] = 8'h85;
	waveform_LUT[393] = 8'hC3;
	waveform_LUT[394] = 8'hEF;
	waveform_LUT[395] = 8'hFE;
	waveform_LUT[396] = 8'hED;
	waveform_LUT[397] = 8'hBE;
	waveform_LUT[398] = 8'h7F;
	waveform_LUT[399] = 8'h40;
	waveform_LUT[400] = 8'h11;
	waveform_LUT[401] = 8'h01;
	waveform_LUT[402] = 8'h12;
	waveform_LUT[403] = 8'h41;
	waveform_LUT[404] = 8'h81;
	waveform_LUT[405] = 8'hC1;
	waveform_LUT[406] = 8'hEF;
	waveform_LUT[407] = 8'hFE;
	waveform_LUT[408] = 8'hEB;
	waveform_LUT[409] = 8'hB9;
	waveform_LUT[410] = 8'h77;
	waveform_LUT[411] = 8'h37;
	waveform_LUT[412] = 8'h0C;
	waveform_LUT[413] = 8'h01;
	waveform_LUT[414] = 8'h1B;
	waveform_LUT[415] = 8'h51;
	waveform_LUT[416] = 8'h95;
	waveform_LUT[417] = 8'hD3;
	waveform_LUT[418] = 8'hF8;
	waveform_LUT[419] = 8'hFB;
	waveform_LUT[420] = 8'hD9;
	waveform_LUT[421] = 8'h9D;
	waveform_LUT[422] = 8'h58;
	waveform_LUT[423] = 8'h1E;
	waveform_LUT[424] = 8'h02;
	waveform_LUT[425] = 8'h0B;
	waveform_LUT[426] = 8'h37;
	waveform_LUT[427] = 8'h7A;
	waveform_LUT[428] = 8'hBE;
	waveform_LUT[429] = 8'hEF;
	waveform_LUT[430] = 8'hFE;
	waveform_LUT[431] = 8'hE6;
	waveform_LUT[432] = 8'hAE;
	waveform_LUT[433] = 8'h68;
	waveform_LUT[434] = 8'h28;
	waveform_LUT[435] = 8'h04;
	waveform_LUT[436] = 8'h07;
	waveform_LUT[437] = 8'h30;
	waveform_LUT[438] = 8'h73;
	waveform_LUT[439] = 8'hB9;
	waveform_LUT[440] = 8'hEE;
	waveform_LUT[441] = 8'hFE;
	waveform_LUT[442] = 8'hE6;
	waveform_LUT[443] = 8'hAC;
	waveform_LUT[444] = 8'h64;
	waveform_LUT[445] = 8'h24;
	waveform_LUT[446] = 8'h03;
	waveform_LUT[447] = 8'h0A;
	waveform_LUT[448] = 8'h39;
	waveform_LUT[449] = 8'h80;
	waveform_LUT[450] = 8'hC6;
	waveform_LUT[451] = 8'hF5;
	waveform_LUT[452] = 8'hFC;
	waveform_LUT[453] = 8'hD9;
	waveform_LUT[454] = 8'h97;
	waveform_LUT[455] = 8'h4D;
	waveform_LUT[456] = 8'h14;
	waveform_LUT[457] = 8'h01;
	waveform_LUT[458] = 8'h19;
	waveform_LUT[459] = 8'h55;
	waveform_LUT[460] = 8'hA0;
	waveform_LUT[461] = 8'hE0;
	waveform_LUT[462] = 8'hFE;
	waveform_LUT[463] = 8'hEF;
	waveform_LUT[464] = 8'hB8;
	waveform_LUT[465] = 8'h6D;
	waveform_LUT[466] = 8'h28;
	waveform_LUT[467] = 8'h03;
	waveform_LUT[468] = 8'h0B;
	waveform_LUT[469] = 8'h3D;
	waveform_LUT[470] = 8'h88;
	waveform_LUT[471] = 8'hD0;
	waveform_LUT[472] = 8'hFA;
	waveform_LUT[473] = 8'hF7;
	waveform_LUT[474] = 8'hC8;
	waveform_LUT[475] = 8'h7D;
	waveform_LUT[476] = 8'h34;
	waveform_LUT[477] = 8'h06;
	waveform_LUT[478] = 8'h07;
	waveform_LUT[479] = 8'h35;
	waveform_LUT[480] = 8'h80;
	waveform_LUT[481] = 8'hCA;
	waveform_LUT[482] = 8'hF8;
	waveform_LUT[483] = 8'hF8;
	waveform_LUT[484] = 8'hC9;
	waveform_LUT[485] = 8'h7D;
	waveform_LUT[486] = 8'h32;
	waveform_LUT[487] = 8'h05;
	waveform_LUT[488] = 8'h08;
	waveform_LUT[489] = 8'h3A;
	waveform_LUT[490] = 8'h88;
	waveform_LUT[491] = 8'hD2;
	waveform_LUT[492] = 8'hFB;
	waveform_LUT[493] = 8'hF3;
	waveform_LUT[494] = 8'hBC;
	waveform_LUT[495] = 8'h6D;
	waveform_LUT[496] = 8'h25;
	waveform_LUT[497] = 8'h01;
	waveform_LUT[498] = 8'h12;
	waveform_LUT[499] = 8'h4F;
	waveform_LUT[500] = 8'hA0;
	waveform_LUT[501] = 8'hE4;
	waveform_LUT[502] = 8'hFE;
	waveform_LUT[503] = 8'hE4;
	waveform_LUT[504] = 8'h9F;
	waveform_LUT[505] = 8'h4D;
	waveform_LUT[506] = 8'h10;
	waveform_LUT[507] = 8'h02;
	waveform_LUT[508] = 8'h2A;
	waveform_LUT[509] = 8'h76;
	waveform_LUT[510] = 8'hC6;
	waveform_LUT[511] = 8'hF8;
	waveform_LUT[512] = 8'hF7;
	waveform_LUT[513] = 8'hC1;
	waveform_LUT[514] = 8'h6F;
	waveform_LUT[515] = 8'h24;
	waveform_LUT[516] = 8'h01;
	waveform_LUT[517] = 8'h15;
	waveform_LUT[518] = 8'h59;
	waveform_LUT[519] = 8'hAD;
	waveform_LUT[520] = 8'hEE;
	waveform_LUT[521] = 8'hFD;
	waveform_LUT[522] = 8'hD4;
	waveform_LUT[523] = 8'h85;
	waveform_LUT[524] = 8'h34;
	waveform_LUT[525] = 8'h04;
	waveform_LUT[526] = 8'h0D;
	waveform_LUT[527] = 8'h4A;
	waveform_LUT[528] = 8'h9F;
	waveform_LUT[529] = 8'hE6;
	waveform_LUT[530] = 8'hFE;
	waveform_LUT[531] = 8'hDC;
	waveform_LUT[532] = 8'h8E;
	waveform_LUT[533] = 8'h3A;
	waveform_LUT[534] = 8'h06;
	waveform_LUT[535] = 8'h0B;
	waveform_LUT[536] = 8'h47;
	waveform_LUT[537] = 8'h9E;
	waveform_LUT[538] = 8'hE6;
	waveform_LUT[539] = 8'hFE;
	waveform_LUT[540] = 8'hD9;
	waveform_LUT[541] = 8'h89;
	waveform_LUT[542] = 8'h35;
	waveform_LUT[543] = 8'h04;
	waveform_LUT[544] = 8'h0F;
	waveform_LUT[545] = 8'h51;
	waveform_LUT[546] = 8'hAA;
	waveform_LUT[547] = 8'hEE;
	waveform_LUT[548] = 8'hFC;
	waveform_LUT[549] = 8'hCD;
	waveform_LUT[550] = 8'h77;
	waveform_LUT[551] = 8'h26;
	waveform_LUT[552] = 8'h01;
	waveform_LUT[553] = 8'h1B;
	waveform_LUT[554] = 8'h68;
	waveform_LUT[555] = 8'hC1;
	waveform_LUT[556] = 8'hF9;
	waveform_LUT[557] = 8'hF3;
	waveform_LUT[558] = 8'hB3;
	waveform_LUT[559] = 8'h58;
	waveform_LUT[560] = 8'h11;
	waveform_LUT[561] = 8'h03;
	waveform_LUT[562] = 8'h35;
	waveform_LUT[563] = 8'h8E;
	waveform_LUT[564] = 8'hDF;
	waveform_LUT[565] = 8'hFE;
	waveform_LUT[566] = 8'hDC;
	waveform_LUT[567] = 8'h89;
	waveform_LUT[568] = 8'h31;
	waveform_LUT[569] = 8'h02;
	waveform_LUT[570] = 8'h16;
	waveform_LUT[571] = 8'h62;
	waveform_LUT[572] = 8'hBE;
	waveform_LUT[573] = 8'hF9;
	waveform_LUT[574] = 8'hF2;
	waveform_LUT[575] = 8'hAE;
	waveform_LUT[576] = 8'h51;
	waveform_LUT[577] = 8'h0D;
	waveform_LUT[578] = 8'h07;
	waveform_LUT[579] = 8'h43;
	waveform_LUT[580] = 8'hA0;
	waveform_LUT[581] = 8'hEC;
	waveform_LUT[582] = 8'hFC;
	waveform_LUT[583] = 8'hC7;
	waveform_LUT[584] = 8'h6A;
	waveform_LUT[585] = 8'h19;
	waveform_LUT[586] = 8'h02;
	waveform_LUT[587] = 8'h30;
	waveform_LUT[588] = 8'h8C;
	waveform_LUT[589] = 8'hE0;
	waveform_LUT[590] = 8'hFE;
	waveform_LUT[591] = 8'hD4;
	waveform_LUT[592] = 8'h7A;
	waveform_LUT[593] = 8'h23;
	waveform_LUT[594] = 8'h01;
	waveform_LUT[595] = 8'h27;
	waveform_LUT[596] = 8'h81;
	waveform_LUT[597] = 8'hDA;
	waveform_LUT[598] = 8'hFE;
	waveform_LUT[599] = 8'hD9;
	waveform_LUT[600] = 8'h7F;
	waveform_LUT[601] = 8'h26;
	waveform_LUT[602] = 8'h01;
	waveform_LUT[603] = 8'h26;
	waveform_LUT[604] = 8'h81;
	waveform_LUT[605] = 8'hDB;
	waveform_LUT[606] = 8'hFE;
	waveform_LUT[607] = 8'hD6;
	waveform_LUT[608] = 8'h7A;
	waveform_LUT[609] = 8'h21;
	waveform_LUT[610] = 8'h01;
	waveform_LUT[611] = 8'h2D;
	waveform_LUT[612] = 8'h8C;
	waveform_LUT[613] = 8'hE3;
	waveform_LUT[614] = 8'hFD;
	waveform_LUT[615] = 8'hCB;
	waveform_LUT[616] = 8'h6A;
	waveform_LUT[617] = 8'h16;
	waveform_LUT[618] = 8'h03;
	waveform_LUT[619] = 8'h3D;
	waveform_LUT[620] = 8'hA0;
	waveform_LUT[621] = 8'hEF;
	waveform_LUT[622] = 8'hF8;
	waveform_LUT[623] = 8'hB5;
	waveform_LUT[624] = 8'h51;
	waveform_LUT[625] = 8'h09;
	waveform_LUT[626] = 8'h0D;
	waveform_LUT[627] = 8'h59;
	waveform_LUT[628] = 8'hBE;
	waveform_LUT[629] = 8'hFB;
	waveform_LUT[630] = 8'hE9;
	waveform_LUT[631] = 8'h93;
	waveform_LUT[632] = 8'h31;
	waveform_LUT[633] = 8'h01;
	waveform_LUT[634] = 8'h23;
	waveform_LUT[635] = 8'h82;
	waveform_LUT[636] = 8'hDF;
	waveform_LUT[637] = 8'hFE;
	waveform_LUT[638] = 8'hCA;
	waveform_LUT[639] = 8'h65;
	waveform_LUT[640] = 8'h11;
	waveform_LUT[641] = 8'h07;
	waveform_LUT[642] = 8'h4C;
	waveform_LUT[643] = 8'hB4;
	waveform_LUT[644] = 8'hF9;
	waveform_LUT[645] = 8'hEC;
	waveform_LUT[646] = 8'h97;
	waveform_LUT[647] = 8'h32;
	waveform_LUT[648] = 8'h01;
	waveform_LUT[649] = 8'h26;
	waveform_LUT[650] = 8'h88;
	waveform_LUT[651] = 8'hE4;
	waveform_LUT[652] = 8'hFC;
	waveform_LUT[653] = 8'hBE;
	waveform_LUT[654] = 8'h55;
	waveform_LUT[655] = 8'h09;
	waveform_LUT[656] = 8'h0F;
	waveform_LUT[657] = 8'h63;
	waveform_LUT[658] = 8'hCA;
	waveform_LUT[659] = 8'hFE;
	waveform_LUT[660] = 8'hD9;
	waveform_LUT[661] = 8'h75;
	waveform_LUT[662] = 8'h19;
	waveform_LUT[663] = 8'h04;
	waveform_LUT[664] = 8'h47;
	waveform_LUT[665] = 8'hB2;
	waveform_LUT[666] = 8'hF9;
	waveform_LUT[667] = 8'hEA;
	waveform_LUT[668] = 8'h8E;
	waveform_LUT[669] = 8'h28;
	waveform_LUT[670] = 8'h01;
	waveform_LUT[671] = 8'h35;
	waveform_LUT[672] = 8'h9F;
	waveform_LUT[673] = 8'hF2;
	waveform_LUT[674] = 8'hF2;
	waveform_LUT[675] = 8'h9E;
	waveform_LUT[676] = 8'h34;
	waveform_LUT[677] = 8'h01;
	waveform_LUT[678] = 8'h2B;
	waveform_LUT[679] = 8'h94;
	waveform_LUT[680] = 8'hEE;
	waveform_LUT[681] = 8'hF6;
	waveform_LUT[682] = 8'hA6;
	waveform_LUT[683] = 8'h3A;
	waveform_LUT[684] = 8'h01;
	waveform_LUT[685] = 8'h27;
	waveform_LUT[686] = 8'h90;
	waveform_LUT[687] = 8'hEC;
	waveform_LUT[688] = 8'hF7;
	waveform_LUT[689] = 8'hA7;
	waveform_LUT[690] = 8'h39;
	waveform_LUT[691] = 8'h01;
	waveform_LUT[692] = 8'h2A;
	waveform_LUT[693] = 8'h94;
	waveform_LUT[694] = 8'hEF;
	waveform_LUT[695] = 8'hF4;
	waveform_LUT[696] = 8'h9F;
	waveform_LUT[697] = 8'h32;
	waveform_LUT[698] = 8'h01;
	waveform_LUT[699] = 8'h32;
	waveform_LUT[700] = 8'hA0;
	waveform_LUT[701] = 8'hF5;
	waveform_LUT[702] = 8'hED;
	waveform_LUT[703] = 8'h8F;
	waveform_LUT[704] = 8'h25;
	waveform_LUT[705] = 8'h02;
	waveform_LUT[706] = 8'h43;
	waveform_LUT[707] = 8'hB4;
	waveform_LUT[708] = 8'hFB;
	waveform_LUT[709] = 8'hE0;
	waveform_LUT[710] = 8'h77;
	waveform_LUT[711] = 8'h15;
	waveform_LUT[712] = 8'h09;
	waveform_LUT[713] = 8'h5C;
	waveform_LUT[714] = 8'hCD;
	waveform_LUT[715] = 8'hFE;
	waveform_LUT[716] = 8'hC9;
	waveform_LUT[717] = 8'h57;
	waveform_LUT[718] = 8'h07;
	waveform_LUT[719] = 8'h19;
	waveform_LUT[720] = 8'h80;
	waveform_LUT[721] = 8'hE6;
	waveform_LUT[722] = 8'hF8;
	waveform_LUT[723] = 8'hA6;
	waveform_LUT[724] = 8'h34;
	waveform_LUT[725] = 8'h01;
	waveform_LUT[726] = 8'h37;
	waveform_LUT[727] = 8'hAB;
	waveform_LUT[728] = 8'hFA;
	waveform_LUT[729] = 8'hE2;
	waveform_LUT[730] = 8'h77;
	waveform_LUT[731] = 8'h13;
	waveform_LUT[732] = 8'h0B;
	waveform_LUT[733] = 8'h66;
	waveform_LUT[734] = 8'hD7;
	waveform_LUT[735] = 8'hFD;
	waveform_LUT[736] = 8'hB8;
	waveform_LUT[737] = 8'h42;
	waveform_LUT[738] = 8'h01;
	waveform_LUT[739] = 8'h2D;
	waveform_LUT[740] = 8'hA0;
	waveform_LUT[741] = 8'hF7;
	waveform_LUT[742] = 8'hE6;
	waveform_LUT[743] = 8'h7B;
	waveform_LUT[744] = 8'h14;
	waveform_LUT[745] = 8'h0B;
	waveform_LUT[746] = 8'h68;
	waveform_LUT[747] = 8'hDA;
	waveform_LUT[748] = 8'hFC;
	waveform_LUT[749] = 8'hB0;
	waveform_LUT[750] = 8'h39;
	waveform_LUT[751] = 8'h01;
	waveform_LUT[752] = 8'h39;
	waveform_LUT[753] = 8'hB1;
	waveform_LUT[754] = 8'hFC;
	waveform_LUT[755] = 8'hD8;
	waveform_LUT[756] = 8'h64;
	waveform_LUT[757] = 8'h09;
	waveform_LUT[758] = 8'h19;
	waveform_LUT[759] = 8'h86;
	waveform_LUT[760] = 8'hEE;
	waveform_LUT[761] = 8'hF1;
	waveform_LUT[762] = 8'h8C;
	waveform_LUT[763] = 8'h1C;
	waveform_LUT[764] = 8'h07;
	waveform_LUT[765] = 8'h61;
	waveform_LUT[766] = 8'hD7;
	waveform_LUT[767] = 8'hFC;
	waveform_LUT[768] = 8'hAE;
	waveform_LUT[769] = 8'h35;
	waveform_LUT[770] = 8'h01;
	waveform_LUT[771] = 8'h43;
	waveform_LUT[772] = 8'hBE;
	waveform_LUT[773] = 8'hFE;
	waveform_LUT[774] = 8'hC8;
	waveform_LUT[775] = 8'h4D;
	waveform_LUT[776] = 8'h02;
	waveform_LUT[777] = 8'h2E;
	waveform_LUT[778] = 8'hA7;
	waveform_LUT[779] = 8'hFB;
	waveform_LUT[780] = 8'hD9;
	waveform_LUT[781] = 8'h62;
	waveform_LUT[782] = 8'h07;
	waveform_LUT[783] = 8'h1F;
	waveform_LUT[784] = 8'h95;
	waveform_LUT[785] = 8'hF6;
	waveform_LUT[786] = 8'hE4;
	waveform_LUT[787] = 8'h71;
	waveform_LUT[788] = 8'h0C;
	waveform_LUT[789] = 8'h17;
	waveform_LUT[790] = 8'h88;
	waveform_LUT[791] = 8'hF1;
	waveform_LUT[792] = 8'hEB;
	waveform_LUT[793] = 8'h7B;
	waveform_LUT[794] = 8'h10;
	waveform_LUT[795] = 8'h13;
	waveform_LUT[796] = 8'h81;
	waveform_LUT[797] = 8'hEE;
	waveform_LUT[798] = 8'hED;
	waveform_LUT[799] = 8'h7F;
	waveform_LUT[800] = 8'h11;
	waveform_LUT[801] = 8'h12;
	waveform_LUT[802] = 8'h80;
	waveform_LUT[803] = 8'hEE;
	waveform_LUT[804] = 8'hED;
	waveform_LUT[805] = 8'h7D;
	waveform_LUT[806] = 8'h10;
	waveform_LUT[807] = 8'h14;
	waveform_LUT[808] = 8'h85;
	waveform_LUT[809] = 8'hF1;
	waveform_LUT[810] = 8'hE9;
	waveform_LUT[811] = 8'h75;
	waveform_LUT[812] = 8'h0C;
	waveform_LUT[813] = 8'h19;
	waveform_LUT[814] = 8'h90;
	waveform_LUT[815] = 8'hF6;
	waveform_LUT[816] = 8'hE1;
	waveform_LUT[817] = 8'h68;
	waveform_LUT[818] = 8'h07;
	waveform_LUT[819] = 8'h24;
	waveform_LUT[820] = 8'hA0;
	waveform_LUT[821] = 8'hFB;
	waveform_LUT[822] = 8'hD4;
	waveform_LUT[823] = 8'h54;
	waveform_LUT[824] = 8'h02;
	waveform_LUT[825] = 8'h34;
	waveform_LUT[826] = 8'hB6;
	waveform_LUT[827] = 8'hFE;
	waveform_LUT[828] = 8'hC0;
	waveform_LUT[829] = 8'h3D;
	waveform_LUT[830] = 8'h01;
	waveform_LUT[831] = 8'h4C;
	waveform_LUT[832] = 8'hCE;
	waveform_LUT[833] = 8'hFC;
	waveform_LUT[834] = 8'hA4;
	waveform_LUT[835] = 8'h24;
	waveform_LUT[836] = 8'h07;
	waveform_LUT[837] = 8'h6C;
	waveform_LUT[838] = 8'hE7;
	waveform_LUT[839] = 8'hF1;
	waveform_LUT[840] = 8'h7F;
	waveform_LUT[841] = 8'h0E;
	waveform_LUT[842] = 8'h19;
	waveform_LUT[843] = 8'h94;
	waveform_LUT[844] = 8'hF9;
	waveform_LUT[845] = 8'hD8;
	waveform_LUT[846] = 8'h55;
	waveform_LUT[847] = 8'h01;
	waveform_LUT[848] = 8'h39;
	waveform_LUT[849] = 8'hBF;
	waveform_LUT[850] = 8'hFE;
	waveform_LUT[851] = 8'hB0;
	waveform_LUT[852] = 8'h2B;
	waveform_LUT[853] = 8'h05;
	waveform_LUT[854] = 8'h68;
	waveform_LUT[855] = 8'hE6;
	waveform_LUT[856] = 8'hF0;
	waveform_LUT[857] = 8'h7B;
	waveform_LUT[858] = 8'h0B;
	waveform_LUT[859] = 8'h1F;
	waveform_LUT[860] = 8'hA0;
	waveform_LUT[861] = 8'hFC;
	waveform_LUT[862] = 8'hCA;
	waveform_LUT[863] = 8'h42;
	waveform_LUT[864] = 8'h01;
	waveform_LUT[865] = 8'h51;
	waveform_LUT[866] = 8'hD7;
	waveform_LUT[867] = 8'hF8;
	waveform_LUT[868] = 8'h8E;
	waveform_LUT[869] = 8'h13;
	waveform_LUT[870] = 8'h16;
	waveform_LUT[871] = 8'h94;
	waveform_LUT[872] = 8'hFA;
	waveform_LUT[873] = 8'hD1;
	waveform_LUT[874] = 8'h49;
	waveform_LUT[875] = 8'h01;
	waveform_LUT[876] = 8'h4D;
	waveform_LUT[877] = 8'hD5;
	waveform_LUT[878] = 8'hF8;
	waveform_LUT[879] = 8'h8D;
	waveform_LUT[880] = 8'h11;
	waveform_LUT[881] = 8'h19;
	waveform_LUT[882] = 8'h9A;
	waveform_LUT[883] = 8'hFC;
	waveform_LUT[884] = 8'hC9;
	waveform_LUT[885] = 8'h3E;
	waveform_LUT[886] = 8'h02;
	waveform_LUT[887] = 8'h5C;
	waveform_LUT[888] = 8'hE1;
	waveform_LUT[889] = 8'hF1;
	waveform_LUT[890] = 8'h77;
	waveform_LUT[891] = 8'h08;
	waveform_LUT[892] = 8'h2A;
	waveform_LUT[893] = 8'hB4;
	waveform_LUT[894] = 8'hFE;
	waveform_LUT[895] = 8'hAE;
	waveform_LUT[896] = 8'h25;
	waveform_LUT[897] = 8'h0A;
	waveform_LUT[898] = 8'h80;
	waveform_LUT[899] = 8'hF5;
	waveform_LUT[900] = 8'hD9;
	waveform_LUT[901] = 8'h4F;
	waveform_LUT[902] = 8'h01;
	waveform_LUT[903] = 8'h50;
	waveform_LUT[904] = 8'hDA;
	waveform_LUT[905] = 8'hF4;
	waveform_LUT[906] = 8'h7C;
	waveform_LUT[907] = 8'h09;
	waveform_LUT[908] = 8'h2A;
	waveform_LUT[909] = 8'hB6;
	waveform_LUT[910] = 8'hFE;
	waveform_LUT[911] = 8'hA7;
	waveform_LUT[912] = 8'h1E;
	waveform_LUT[913] = 8'h10;
	waveform_LUT[914] = 8'h90;
	waveform_LUT[915] = 8'hFB;
	waveform_LUT[916] = 8'hC9;
	waveform_LUT[917] = 8'h3A;
	waveform_LUT[918] = 8'h03;
	waveform_LUT[919] = 8'h6C;
	waveform_LUT[920] = 8'hEE;
	waveform_LUT[921] = 8'hE2;
	waveform_LUT[922] = 8'h58;
	waveform_LUT[923] = 8'h01;
	waveform_LUT[924] = 8'h4D;
	waveform_LUT[925] = 8'hDB;
	waveform_LUT[926] = 8'hF2;
	waveform_LUT[927] = 8'h75;
	waveform_LUT[928] = 8'h05;
	waveform_LUT[929] = 8'h35;
	waveform_LUT[930] = 8'hC6;
	waveform_LUT[931] = 8'hFB;
	waveform_LUT[932] = 8'h8E;
	waveform_LUT[933] = 8'h0E;
	waveform_LUT[934] = 8'h23;
	waveform_LUT[935] = 8'hB2;
	waveform_LUT[936] = 8'hFE;
	waveform_LUT[937] = 8'hA3;
	waveform_LUT[938] = 8'h18;
	waveform_LUT[939] = 8'h17;
	waveform_LUT[940] = 8'hA0;
	waveform_LUT[941] = 8'hFE;
	waveform_LUT[942] = 8'hB3;
	waveform_LUT[943] = 8'h23;
	waveform_LUT[944] = 8'h0F;
	waveform_LUT[945] = 8'h92;
	waveform_LUT[946] = 8'hFC;
	waveform_LUT[947] = 8'hBE;
	waveform_LUT[948] = 8'h2B;
	waveform_LUT[949] = 8'h0A;
	waveform_LUT[950] = 8'h88;
	waveform_LUT[951] = 8'hFA;
	waveform_LUT[952] = 8'hC6;
	waveform_LUT[953] = 8'h32;
	waveform_LUT[954] = 8'h08;
	waveform_LUT[955] = 8'h82;
	waveform_LUT[956] = 8'hF9;
	waveform_LUT[957] = 8'hC9;
	waveform_LUT[958] = 8'h34;
	waveform_LUT[959] = 8'h07;
	waveform_LUT[960] = 8'h80;
	waveform_LUT[961] = 8'hF8;
	waveform_LUT[962] = 8'hCA;
	waveform_LUT[963] = 8'h34;
	waveform_LUT[964] = 8'h07;
	waveform_LUT[965] = 8'h82;
	waveform_LUT[966] = 8'hF9;
	waveform_LUT[967] = 8'hC7;
	waveform_LUT[968] = 8'h31;
	waveform_LUT[969] = 8'h09;
	waveform_LUT[970] = 8'h88;
	waveform_LUT[971] = 8'hFB;
	waveform_LUT[972] = 8'hC0;
	waveform_LUT[973] = 8'h2A;
	waveform_LUT[974] = 8'h0D;
	waveform_LUT[975] = 8'h92;
	waveform_LUT[976] = 8'hFD;
	waveform_LUT[977] = 8'hB5;
	waveform_LUT[978] = 8'h21;
	waveform_LUT[979] = 8'h13;
	waveform_LUT[980] = 8'hA0;
	waveform_LUT[981] = 8'hFE;
	waveform_LUT[982] = 8'hA6;
	waveform_LUT[983] = 8'h16;
	waveform_LUT[984] = 8'h1E;
	waveform_LUT[985] = 8'hB2;
	waveform_LUT[986] = 8'hFD;
	waveform_LUT[987] = 8'h93;
	waveform_LUT[988] = 8'h0C;
	waveform_LUT[989] = 8'h2D;
	waveform_LUT[990] = 8'hC6;
	waveform_LUT[991] = 8'hF8;
	waveform_LUT[992] = 8'h7A;
	waveform_LUT[993] = 8'h04;
	waveform_LUT[994] = 8'h43;
	waveform_LUT[995] = 8'hDB;
	waveform_LUT[996] = 8'hED;
	waveform_LUT[997] = 8'h5E;
	waveform_LUT[998] = 8'h01;
	waveform_LUT[999] = 8'h5F;
	waveform_LUT[1000] = 8'hEE;
	waveform_LUT[1001] = 8'hD9;
	waveform_LUT[1002] = 8'h40;
	waveform_LUT[1003] = 8'h05;
	waveform_LUT[1004] = 8'h81;
	waveform_LUT[1005] = 8'hFB;
	waveform_LUT[1006] = 8'hBC;
	waveform_LUT[1007] = 8'h23;
	waveform_LUT[1008] = 8'h14;
	waveform_LUT[1009] = 8'hA7;
	waveform_LUT[1010] = 8'hFE;
	waveform_LUT[1011] = 8'h96;
	waveform_LUT[1012] = 8'h0C;
	waveform_LUT[1013] = 8'h30;
	waveform_LUT[1014] = 8'hCD;
	waveform_LUT[1015] = 8'hF4;
	waveform_LUT[1016] = 8'h6A;
	waveform_LUT[1017] = 8'h01;
	waveform_LUT[1018] = 8'h59;
	waveform_LUT[1019] = 8'hEC;
	waveform_LUT[1020] = 8'hD9;
	waveform_LUT[1021] = 8'h3D;
	waveform_LUT[1022] = 8'h07;
	waveform_LUT[1023] = 8'h8A;
	waveform_LUT[1024] = 8'hFD;
	waveform_LUT[1025] = 8'hAE;
	waveform_LUT[1026] = 8'h17;
	waveform_LUT[1027] = 8'h22;
	waveform_LUT[1028] = 8'hBE;
	waveform_LUT[1029] = 8'hF9;
	waveform_LUT[1030] = 8'h77;
	waveform_LUT[1031] = 8'h02;
	waveform_LUT[1032] = 8'h51;
	waveform_LUT[1033] = 8'hE9;
	waveform_LUT[1034] = 8'hDC;
	waveform_LUT[1035] = 8'h3E;
	waveform_LUT[1036] = 8'h07;
	waveform_LUT[1037] = 8'h8E;
	waveform_LUT[1038] = 8'hFE;
	waveform_LUT[1039] = 8'hA7;
	waveform_LUT[1040] = 8'h11;
	waveform_LUT[1041] = 8'h2B;
	waveform_LUT[1042] = 8'hCB;
	waveform_LUT[1043] = 8'hF3;
	waveform_LUT[1044] = 8'h64;
	waveform_LUT[1045] = 8'h01;
	waveform_LUT[1046] = 8'h68;
	waveform_LUT[1047] = 8'hF5;
	waveform_LUT[1048] = 8'hC6;
	waveform_LUT[1049] = 8'h26;
	waveform_LUT[1050] = 8'h16;
	waveform_LUT[1051] = 8'hB0;
	waveform_LUT[1052] = 8'hFC;
	waveform_LUT[1053] = 8'h7F;
	waveform_LUT[1054] = 8'h03;
	waveform_LUT[1055] = 8'h51;
	waveform_LUT[1056] = 8'hEB;
	waveform_LUT[1057] = 8'hD6;
	waveform_LUT[1058] = 8'h34;
	waveform_LUT[1059] = 8'h0D;
	waveform_LUT[1060] = 8'hA0;
	waveform_LUT[1061] = 8'hFE;
	waveform_LUT[1062] = 8'h8C;
	waveform_LUT[1063] = 8'h05;
	waveform_LUT[1064] = 8'h47;
	waveform_LUT[1065] = 8'hE6;
	waveform_LUT[1066] = 8'hDC;
	waveform_LUT[1067] = 8'h3A;
	waveform_LUT[1068] = 8'h0B;
	waveform_LUT[1069] = 8'h9D;
	waveform_LUT[1070] = 8'hFE;
	waveform_LUT[1071] = 8'h8D;
	waveform_LUT[1072] = 8'h05;
	waveform_LUT[1073] = 8'h4A;
	waveform_LUT[1074] = 8'hE8;
	waveform_LUT[1075] = 8'hD8;
	waveform_LUT[1076] = 8'h34;
	waveform_LUT[1077] = 8'h0F;
	waveform_LUT[1078] = 8'hA7;
	waveform_LUT[1079] = 8'hFD;
	waveform_LUT[1080] = 8'h7F;
	waveform_LUT[1081] = 8'h02;
	waveform_LUT[1082] = 8'h59;
	waveform_LUT[1083] = 8'hF1;
	waveform_LUT[1084] = 8'hC9;
	waveform_LUT[1085] = 8'h24;
	waveform_LUT[1086] = 8'h1B;
	waveform_LUT[1087] = 8'hBD;
	waveform_LUT[1088] = 8'hF6;
	waveform_LUT[1089] = 8'h65;
	waveform_LUT[1090] = 8'h01;
	waveform_LUT[1091] = 8'h76;
	waveform_LUT[1092] = 8'hFB;
	waveform_LUT[1093] = 8'hAC;
	waveform_LUT[1094] = 8'h10;
	waveform_LUT[1095] = 8'h34;
	waveform_LUT[1096] = 8'hDA;
	waveform_LUT[1097] = 8'hE4;
	waveform_LUT[1098] = 8'h40;
	waveform_LUT[1099] = 8'h0A;
	waveform_LUT[1100] = 8'hA0;
	waveform_LUT[1101] = 8'hFD;
	waveform_LUT[1102] = 8'h7F;
	waveform_LUT[1103] = 8'h01;
	waveform_LUT[1104] = 8'h60;
	waveform_LUT[1105] = 8'hF6;
	waveform_LUT[1106] = 8'hBC;
	waveform_LUT[1107] = 8'h18;
	waveform_LUT[1108] = 8'h2A;
	waveform_LUT[1109] = 8'hD2;
	waveform_LUT[1110] = 8'hE9;
	waveform_LUT[1111] = 8'h46;
	waveform_LUT[1112] = 8'h09;
	waveform_LUT[1113] = 8'h9E;
	waveform_LUT[1114] = 8'hFD;
	waveform_LUT[1115] = 8'h7D;
	waveform_LUT[1116] = 8'h01;
	waveform_LUT[1117] = 8'h66;
	waveform_LUT[1118] = 8'hF8;
	waveform_LUT[1119] = 8'hB3;
	waveform_LUT[1120] = 8'h11;
	waveform_LUT[1121] = 8'h35;
	waveform_LUT[1122] = 8'hDE;
	waveform_LUT[1123] = 8'hDD;
	waveform_LUT[1124] = 8'h34;
	waveform_LUT[1125] = 8'h13;
	waveform_LUT[1126] = 8'hB6;
	waveform_LUT[1127] = 8'hF7;
	waveform_LUT[1128] = 8'h60;
	waveform_LUT[1129] = 8'h02;
	waveform_LUT[1130] = 8'h88;
	waveform_LUT[1131] = 8'hFE;
	waveform_LUT[1132] = 8'h8E;
	waveform_LUT[1133] = 8'h03;
	waveform_LUT[1134] = 8'h5B;
	waveform_LUT[1135] = 8'hF6;
	waveform_LUT[1136] = 8'hB8;
	waveform_LUT[1137] = 8'h13;
	waveform_LUT[1138] = 8'h35;
	waveform_LUT[1139] = 8'hE0;
	waveform_LUT[1140] = 8'hD9;
	waveform_LUT[1141] = 8'h2D;
	waveform_LUT[1142] = 8'h19;
	waveform_LUT[1143] = 8'hC3;
	waveform_LUT[1144] = 8'hF0;
	waveform_LUT[1145] = 8'h4D;
	waveform_LUT[1146] = 8'h08;
	waveform_LUT[1147] = 8'hA1;
	waveform_LUT[1148] = 8'hFC;
	waveform_LUT[1149] = 8'h6F;
	waveform_LUT[1150] = 8'h01;
	waveform_LUT[1151] = 8'h80;
	waveform_LUT[1152] = 8'hFE;
	waveform_LUT[1153] = 8'h8F;
	waveform_LUT[1154] = 8'h03;
	waveform_LUT[1155] = 8'h61;
	waveform_LUT[1156] = 8'hF9;
	waveform_LUT[1157] = 8'hAC;
	waveform_LUT[1158] = 8'h0B;
	waveform_LUT[1159] = 8'h46;
	waveform_LUT[1160] = 8'hEE;
	waveform_LUT[1161] = 8'hC4;
	waveform_LUT[1162] = 8'h18;
	waveform_LUT[1163] = 8'h30;
	waveform_LUT[1164] = 8'hDF;
	waveform_LUT[1165] = 8'hD8;
	waveform_LUT[1166] = 8'h28;
	waveform_LUT[1167] = 8'h1F;
	waveform_LUT[1168] = 8'hCE;
	waveform_LUT[1169] = 8'hE6;
	waveform_LUT[1170] = 8'h39;
	waveform_LUT[1171] = 8'h13;
	waveform_LUT[1172] = 8'hBE;
	waveform_LUT[1173] = 8'hF0;
	waveform_LUT[1174] = 8'h49;
	waveform_LUT[1175] = 8'h0B;
	waveform_LUT[1176] = 8'hAE;
	waveform_LUT[1177] = 8'hF7;
	waveform_LUT[1178] = 8'h58;
	waveform_LUT[1179] = 8'h06;
	waveform_LUT[1180] = 8'hA0;
	waveform_LUT[1181] = 8'hFB;
	waveform_LUT[1182] = 8'h65;
	waveform_LUT[1183] = 8'h03;
	waveform_LUT[1184] = 8'h95;
	waveform_LUT[1185] = 8'hFD;
	waveform_LUT[1186] = 8'h6F;
	waveform_LUT[1187] = 8'h01;
	waveform_LUT[1188] = 8'h8C;
	waveform_LUT[1189] = 8'hFE;
	waveform_LUT[1190] = 8'h77;
	waveform_LUT[1191] = 8'h01;
	waveform_LUT[1192] = 8'h85;
	waveform_LUT[1193] = 8'hFE;
	waveform_LUT[1194] = 8'h7C;
	waveform_LUT[1195] = 8'h01;
	waveform_LUT[1196] = 8'h81;
	waveform_LUT[1197] = 8'hFE;
	waveform_LUT[1198] = 8'h7F;
	waveform_LUT[1199] = 8'h01; 
    end

    reg [7:0] index = 0;
     always @(posedge DAC_CLOCK) begin
        if (!DAC_SLEEP) begin // Only drive DAC_DATA when DAC_SLEEP is low
            DAC_DATA <= waveform_LUT[index];
            index <= index + 1;
            if (index >= n) index <= 0;
        end
    end

endmodule

// ADC Interface Module
module adc_interface (
    input wire ADC_CLK,    // 60 MHz clock output to ADC
    input wire [9:0] ADC_DATA, // 10-bit parallel ADC data input
    output reg [9:0] ADC_sampled_data // Captured ADC data
);


    // Capture ADC data on ADC_CLK rising edge
    always @(posedge ADC_CLK) begin
        ADC_sampled_data <= ADC_DATA;
    end
    
endmodule

// FIFO Transmitter Module
module ft2232h_245_sync (
    input clk,              // 60 MHz clock
    input reset,            // Reset signal
    input [7:0] ADC_DATA,  // 8-bit data from ADC
    output wire [7:0] AD_Bus, // Bus to FT2232HQ
    output reg oe,          // Output enable
    output reg rd,          // Read signal
    input txe,              // Transmit enable
    output reg wr,          // Write signal
    input clkout_ft2232,    // FT2232 clock
    input adc_active        // ADC active signal
);

    // Internal signals
    reg txe_n;
    reg wr_n;
    reg oe_n = 1'b1;
    reg rd_n = 1'b1;
    reg Flag_tx = 0;
    reg data_en_1 = 0;
    reg data_en_2 = 0;
    reg [7:0] data_o = 8'b00000000;

    // State definitions
    parameter TX_RX_0   = 3'b000;
    parameter TX_1      = 3'b001; 
    parameter TX_2      = 3'b010;  
    parameter TX_3      = 3'b011;

    reg [3:0] state;
    reg [3:0] state_data;
    reg counter = 1'b0;  

    // Assign output data bus
    assign AD_Bus = (data_en_1 == 1'b1) ? ADC_DATA : 8'bz;

    // Control logic
    always @(posedge clkout_ft2232) begin
        if ((txe_n == 0) && Flag_tx && adc_active) begin
            data_en_1 <= 1'b1; // Enable data transfer only during ADC_ACTIVE
        end else begin
            data_en_1 <= 1'b0;
        end
    end

    // State machine
    always @(posedge clk) begin
        if (reset) begin
            state <= TX_RX_0;
            state_data <= 0;
            counter <= 1'b0;
            wr_n <= 1'b1;
        end else begin
            case (state)
                TX_RX_0: begin
                    if (txe_n == 0) begin
                        state <= TX_1;
                    end else begin
                        state <= TX_RX_0;
                        wr_n <= 1'b1;
                    end
                end

                TX_1: begin
                    if (txe_n == 0) begin
                        counter <= counter + 1;
                        if (counter == 1'b1) begin
                            counter <= 1'b0;
                            state <= TX_2;
                        end
                    end else begin
                        wr_n <= 1'b1;
                        state <= TX_RX_0;
                    end
                end

                TX_2: begin
                    wr_n <= 1'b0;
                    counter <= counter + 1;
                    if (counter == 1'b1) begin
                        counter <= 1'b0;
                        state <= TX_3;
                    end
                end

                TX_3: begin
                    if (txe_n == 0) begin
                        Flag_tx <= 1'b1;
                        state <= TX_3;
                    end else begin
                        state <= TX_RX_0;
                        wr_n <= 1'b1;
                        Flag_tx <= 1'b0;
                    end
                end
            endcase
        end
    end

    // Assign outputs
    always @(posedge clk) begin
        wr <= wr_n;
        txe_n <= txe;
        oe <= oe_n;
        rd <= rd_n;
    end

endmodule

