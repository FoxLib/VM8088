module sd
(
    // 25 Mhz
    input  wire         clock,

    // SPI
    output reg          SPI_CS,
    output reg          SPI_SCLK,
    input  wire         SPI_MISO,
    output reg          SPI_MOSI,

    // Интерфейс
    input  wire         sd_signal,  // =1 Прием команды
    input  wire [ 1:0]  sd_cmd,     // ID команды
    output reg  [ 7:0]  sd_din,     // Исходящие данные в процессор
    input  wire [ 7:0]  sd_out,     // Входящие данные из процессора
    output reg          sd_busy,    // =1 Устройство занято
    output wire         sd_timeout  // =1 Вышел таймаут
);

// 0.1 s
`define SPI_TIMEOUT_CNT     2500000

initial begin

    SPI_CS   = 1'b1;
    SPI_SCLK = 1'b0;
    SPI_MOSI = 1'b0;
    sd_din   = 8'h00;
    sd_busy  = 1'b0;

end

// ---------------------------------------------------------------------
// SPI SdCard
// ---------------------------------------------------------------------

// Сигнал о том, занято ли устройство
assign      sd_timeout = (sd_timeout_cnt == 0);

reg  [2:0]  spi_process = 0;
reg  [3:0]  spi_cycle   = 0;
reg  [7:0]  spi_data_w  = 0;

// INIT SPI MODE
reg  [7:0]  spi_counter    = 0;
reg  [7:0]  spi_slow_tick  = 0;
reg  [24:0] sd_timeout_cnt = 0;

always @(posedge clock) begin

    // Счетчик таймаута. Дойдя для
    if (sd_timeout_cnt > `SPI_TIMEOUT_CNT && spi_process == 0)
        sd_timeout_cnt <= sd_timeout_cnt - 1'b1;

    case (spi_process)

        // Инициировать процессинг
        0: if (sd_signal) begin

            spi_process <= 1 + sd_cmd;
            spi_counter <= 0;
            spi_cycle   <= 0;
            spi_data_w  <= sd_out;
            sd_busy     <= 1;
            sd_timeout_cnt <= 0;

        end

        // Command-1: 80 тактов в slow-режиме
        1: begin

            SPI_CS   <= 1;
            SPI_MOSI <= 1;

            // 125*100`000
            if (spi_slow_tick == (125 - 1)) begin

                SPI_SCLK      <= ~SPI_SCLK;
                spi_slow_tick <= 0;
                spi_counter   <= spi_counter + 1;

                // 80 ticks
                if (spi_counter == (2*80 - 1)) begin

                    SPI_SCLK    <= 0;
                    spi_process <= 0;
                    sd_busy     <= 0;

                end

            end
            // Оттикивание таймера
            else begin spi_slow_tick <= spi_slow_tick + 1;  end

        end

        // Command 1: Read/Write SPI
        2: case (spi_cycle)

            // CLK-DN
            0: begin

                SPI_SCLK  <= 0;
                spi_cycle <= 1;
                SPI_MOSI  <= spi_data_w[7];

            end
            // CLK-UP
            1: begin

                SPI_SCLK    <= 1;
                spi_cycle   <= 0;
                sd_din      <= {sd_din[6:0], SPI_MISO};
                spi_data_w  <= {spi_data_w[6:0], 1'b0};
                spi_counter <= spi_counter + 1;

                if (spi_counter == 8) begin

                    SPI_SCLK    <= 0;
                    sd_busy     <= 0;
                    spi_counter <= 0;
                    spi_process <= 0;
                    SPI_MOSI    <= 0;

                end
            end

        endcase

        // Переключить CS
        3, 4: begin SPI_CS <= ~spi_process[0]; spi_process <= 0; sd_busy <= 0; end

    endcase

end

endmodule
