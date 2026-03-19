module fpga_controller (
    input wire CLK_IN,         // 100MHz input clock
    input wire DIG_0,          // Control signal
	input wire DIG_1,          //reset from µC
    input wire [7:0] ADC_DATA, // 8-bit data from ADC
    output wire DAC_CLOCK,     // Clock for DAC
    output reg [7:0] DAC_DATA, // Data to DAC
    output reg [7:0] FT_DATA,  // Data to FT2232H
    output reg FT_WR,           // Write control for FT2232H
	input FT_TXE,
	input wire FT_CLKOUT,
	output reg FT_OE,
	output reg FT_RD
);

    // Clock generation (assumes DAC needs 120MHz, adjust if needed)
    reg [2:0] clk_div = 0;
    reg dac_clk_reg = 0;
    always @(posedge CLK_IN) begin
        clk_div <= clk_div + 1;
        if (clk_div == 2) begin
            dac_clk_reg <= ~dac_clk_reg;
            clk_div <= 0;
        end
    end
    assign DAC_CLOCK = dac_clk_reg;

    // Instantiate waveform generator
    waveform_generator waveform_gen (
        .CLK_IN(CLK_IN),
        .DAC_CLOCK(DAC_CLOCK),
        .DAC_DATA(DAC_DATA)
    );

    // Instantiate ADC interface
    wire [7:0] adc_output;
    adc_interface adc_intf (
        .CLK_IN(CLK_IN),
        .ADC_DATA(adc_output)
    );

    // Instantiate FIFO for FT2232H data buffering
    ft2232h_245_sync ft2232h_245_sync (
						.clk,//input 50_MHz
						.reset,
						.DAC_DATA,
						.AD_Bus,
						.oe,
						.rd,
						.txe,
						.wr,
						.clkout_ft2232
					);

    // Data handling logic
    always @(posedge CLK_IN) begin
        if (!DIG_0) begin
            FT_DATA <= fifo_out; // Send ADC data to FT2232H
            FT_WR <= ~fifo_empty; // Write when FIFO is not empty
        end else begin
            FT_WR <= 0;
        end
    end

endmodule

// Waveform Generator Module
module waveform_generator (
    input wire CLK_IN,
    output reg DAC_CLOCK,
    output reg [7:0] DAC_DATA
);
    reg [2:0] clk_div = 0;
    always @(posedge CLK_IN) begin
        clk_div <= clk_div + 1;
        if (clk_div == 2) begin
            DAC_CLOCK <= ~DAC_CLOCK;
            clk_div <= 0;
        end
    end
    
    parameter integer n = 31;
    reg [7:0] waveform_LUT [0:n-1];
    initial begin
        waveform_LUT[0] = 8'h80; waveform_LUT[1] = 8'h89;
        waveform_LUT[2] = 8'h99; waveform_LUT[3] = 8'hAE;
        waveform_LUT[4] = 8'hC7; waveform_LUT[5] = 8'hE1;
        waveform_LUT[6] = 8'hF6; waveform_LUT[7] = 8'hFF;
        waveform_LUT[8] = 8'hF4; waveform_LUT[9] = 8'hCF;
        waveform_LUT[10] = 8'h92; waveform_LUT[11] = 8'h4B;
        waveform_LUT[12] = 8'h11; waveform_LUT[13] = 8'h02;
        waveform_LUT[14] = 8'h2E; waveform_LUT[15] = 8'h8A;
        waveform_LUT[16] = 8'hE4; waveform_LUT[17] = 8'hFC;
        waveform_LUT[18] = 8'hB6; waveform_LUT[19] = 8'h3F;
        waveform_LUT[20] = 8'h00; waveform_LUT[21] = 8'h41;
        waveform_LUT[22] = 8'hC8; waveform_LUT[23] = 8'hFC;
        waveform_LUT[24] = 8'h91; waveform_LUT[25] = 8'h0C;
        waveform_LUT[26] = 8'h2E; waveform_LUT[27] = 8'hD0;
        waveform_LUT[28] = 8'hED; waveform_LUT[29] = 8'h4A;
        waveform_LUT[30] = 8'h09;
    end

    reg [9:0] index = 0;
    always @(posedge DAC_CLOCK) begin
        DAC_DATA <= waveform_LUT[index];
        index <= (index >= n - 1) ? 0 : index + 1;
    end
endmodule

// ADC Interface Module
module adc_interface (
    input wire CLK_IN,
    output reg [7:0] ADC_DATA
);
    always @(posedge CLK_IN) begin
        ADC_DATA <= $random; // Simulate ADC data
    end
endmodule

// FIFO Transmitter Module
module ft2232h_245_sync(input clk,//input 50_MHz
						 input reset,
						 input [7:0] DAC_DATA,
						 input [7:0] AD_Bus,
						 output reg oe,
						 output reg rd,
						 input txe,
						 output reg wr,
						 input clkout_ft2232);
						 //output reg oe);

//wire CLK_OUT_PLL; //Output from PLL_IP_clock 


reg txe_n;
reg wr_n;

reg oe_n = 1'b1;
reg rd_n = 1'b1;

reg Flag_tx = 0;

reg data_en_1 = 0;
reg data_en_2 = 0;

reg [7:0] data_o = 8'b00000000;


parameter TX_RX_0   = 3'b000;
parameter TX_1      = 3'b001; 
parameter TX_2      = 3'b010;  
parameter TX_3      = 3'b011;

reg [3:0] state;

reg [3:0] state_data;

reg counter = 1'b0;  

begin

assign AD_Bus = (data_en_1 == 1'b1) ? DAC_DATA : 8'bz;

always @ (posedge clkout_ft2232)
begin
if ((txe_n == 0) && Flag_tx)
	begin
	data_en_1 = 1'b1;
	end 
end 


always @ (posedge clk)
begin
   wr = wr_n;
   txe_n = txe;
	oe = oe_n;
	rd = rd_n;
end

always @ (posedge clk)
	if (reset) 
			begin 
			state = TX_RX_0;
			state_data = 0;
			counter = 1'b0;
			wr_n = 1'b1;
			end   
	else
	
	begin
		
		
		case(state)

		TX_RX_0: begin			
				if (txe_n == 0)
				begin
				state = TX_1;
				end
				else
				begin
				state = TX_RX_0;
				wr_n = 1'b1;
				end
				end
			
		TX_1 :  begin
				if(txe_n == 0)
				begin
				counter = counter + 1;
				if(counter == 1'b1)
					begin
					counter = 1'b0;
					state   = TX_2;
					end
				end
				else
				begin
				wr_n = 1'b1;
				state = TX_RX_0;
				end
				end
				
		TX_2 :  begin
				wr_n = 1'b0;
				counter = counter + 1;
				if(counter == 1'b1)
					begin
					counter = 1'b0;
					state   = TX_3;
					end
				end 
				
		TX_3 :  begin
				if(txe_n == 0)
					begin
					Flag_tx = 1'b1;
					state   = TX_3;
					end
				else
					begin
					state   = TX_RX_0;
					wr_n = 1'b1;
					Flag_tx = 1'b0;
					end
				end      	
				
		endcase
		end
end
endmodule 

