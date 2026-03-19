module spi_level_shifter (
    input wire STM32_SCLK,
    input wire STM32_MOSI,
    output wire STM32_MISO,
    input wire STM32_CS_ADAR1,
    input wire STM32_CS_ADAR2,
    input wire STM32_CS_ADAR3,
    input wire STM32_CS_ADAR4,
    input wire DIG_0,
    input wire DIG_1,
    input wire DIG_2,
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
    output reg M3S_VCTRL,
    output wire MIX_TX_EN,
    output wire MIX_RX_EN
);

    assign SPI_SCLK_1V8 = STM32_SCLK;
    assign SPI_MOSI_1V8 = STM32_MOSI;
    assign STM32_MISO = SPI_MISO_1V8;
    
    assign CS_ADAR_1V8_1 = STM32_CS_ADAR1;
    assign CS_ADAR_1V8_2 = STM32_CS_ADAR2;
    assign CS_ADAR_1V8_3 = STM32_CS_ADAR3;
    assign CS_ADAR_1V8_4 = STM32_CS_ADAR4;
    
    assign MIX_TX_EN = DIG_1;
    assign MIX_RX_EN = DIG_2;
    
    always @(*) begin
        if (DIG_0) begin
            ADAR_TR1 = 1;
            ADAR_TR2 = 1;
            ADAR_TR3 = 1;
            ADAR_TR4 = 1;
            M3S_VCTRL = 0;
        end else begin
            ADAR_TR1 = 0;
            ADAR_TR2 = 0;
            ADAR_TR3 = 0;
            ADAR_TR4 = 0;
            M3S_VCTRL = 1;
        end
    end

endmodule