`timescale 1ns / 1ps
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




