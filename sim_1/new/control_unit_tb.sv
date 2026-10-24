`timescale 1ns / 1ps

module control_unit_tb;


    bit clk = 1'b0;
    bit cpu_rst = 1'b1;
    bit bram_rst = 1'b1;

    // BRAM write signals used to load the program.
    wire        awready; 
    logic       awvalid;
    logic [19:0] awaddr;
    wire        wready;
    logic       wvalid;
    logic [31:0] wdata;
    logic       bready;
    wire        bvalid;
    wire [1:0]  bresp;

    // Read Channels
    wire        arready; // BRAM raises this when it can accept the CPU's read-address request.
    wire [19:0] araddr; // Address of the instruction the CPU wants to fetch from BRAM.
    wire        arvalid; // CPU raises this to indicate that araddr contains a valid read request.
    wire        rready;  // CPU raises this when it is ready to accept the instruction data.
    wire        rvalid;
    wire [31:0] rdata;

    localparam int memBytes = 512; // Reserve 512 bytes for the memory image
    localparam logic [31:0] programEndPC = 32'h0000_0160; // PC for program end

    logic [7:0] memory_bytes [0:memBytes-1];   // Store the hex file as individual 8-bit bytes before packing each group of four into an instruction word.
    logic [31:0] word_to_write; // Our instruction to write to BRAM

    always #5ns clk = ~clk; // 100MHz clock

    
    control_unit myCUnit (
        .clk     (clk),
        .rst     (cpu_rst),
        .error   (),
        .arready (arready),
        .araddr  (araddr),
        .arvalid (arvalid),
        .rdata   (rdata),
        .rvalid  (rvalid),
        .rready  (rready),
        
        
        // Connect the write-handshake inputs.
        .awready      (awready),
        .wready       (wready),
        .bvalid       (bvalid),

        // Add this for writes later
        .awaddr       (),
        .awvalid      (),
        .wdata        (),
        .write_strobe (),
        .wvalid       (),
        .bready       ()
    );

    // Instantiate the BRAM, yes even the write channels
    MY_AXI_BRAM my_bram (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (!bram_rst),
        .s_axi_araddr  (araddr),
        .s_axi_arprot  (3'b000),
        .s_axi_arready (arready),
        .s_axi_arvalid (arvalid),
        .s_axi_rdata   (rdata),
        .s_axi_rready  (rready),
        .s_axi_rvalid  (rvalid),
        .s_axi_awaddr  (awaddr),
        .s_axi_awprot  (3'b000),
        .s_axi_awready (awready),
        .s_axi_awvalid (awvalid),
        .s_axi_wdata   (wdata),
        .s_axi_wready  (wready),
        .s_axi_wstrb   (4'b1111),
        .s_axi_wvalid  (wvalid),
        .s_axi_bready  (bready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid)
    );

    // Write one word to BRAM and wait for the AXI write response.
    task automatic write_word(
        input logic [19:0] address,
        input logic [31:0] data
    );
        bit address_done;
        bit data_done;
        begin
            address_done = 1'b0;
            data_done = 1'b0;

            @(negedge clk);
            awaddr = address;
            wdata = data;
            awvalid = 1'b1;
            wvalid = 1'b1;
            bready = 1'b0;

            while (!(address_done && data_done)) begin
                @(posedge clk);
                if (awvalid && awready)
                    address_done = 1'b1;
                if (wvalid && wready)
                    data_done = 1'b1;

                @(negedge clk);
                if (address_done)
                    awvalid = 1'b0;
                if (data_done)
                    wvalid = 1'b0;
            end

            bready = 1'b1;
            do begin
                @(posedge clk);
            end while (!(bvalid && bready));
            @(negedge clk);
            bready = 1'b0;
        end
    endtask
    
    
    
    
    
    // Start of the test bench for reals
    initial begin
        cpu_rst = 1'b1;
        bram_rst = 1'b1;
        awvalid = 1'b0;
        awaddr = '0;
        wvalid = 1'b0;
        wdata = '0;
        bready = 1'b0;

        repeat (4) @(negedge clk);
        bram_rst = 1'b0;
        repeat (2) @(negedge clk);

        // Clear unused memory bytes, then load the little-endian hex file.
        for (int i = 0; i < memBytes; i = i + 1)
            memory_bytes[i] = 8'h00;
        $readmemh("lab4_binary.txt", memory_bytes); // funct for processing the hex

        $display("Loading program into BRAM..."); // Display for our loading phase
        for (int i = 0; i < memBytes; i = i + 4) begin
            word_to_write = {
                memory_bytes[i+3], memory_bytes[i+2],
                memory_bytes[i+1], memory_bytes[i]
            };
            write_word(i[19:0], word_to_write);
        end
        
        // Initialize the actual data, not instructions <---
        write_word(20'h00200, 32'h80A57F01); // write the word at address 0x200
        // Address: 0x200
        // Value:   0x80A57F01
        
        
        $display("BRAM loading complete."); // Ack that the loading is complete

        repeat (2) @(negedge clk);
        cpu_rst = 1'b0; // Reset the cpu
        $display("Running program..."); //Now show program is running

        
        // Wait until the cpu reaches the Ebreak instruction.
        wait (myCUnit.curr_instruction == 32'h00100073);
        @(negedge clk);
        
        $display(""); // SPacing
        $display("Register contents:");
        


       // Load instructions that I am testing basically
       // addi x1, x0, 512      # x1 = 0x200, our data address
       // lw   x2, 0(x1)        # Read the 32-bit value stored at memory address 0x200 and put it in x2
       // lb   x3, 2(x1)        # Load byte at offset 2
       // lb   x4, 0(x1)        # Load byte at offset 0
       // lh   x5, 0(x1)        # Load lower halfword
       // lh   x6, 2(x1)        # Load upper halfword
       // ebreak                # Stop the CPU
        
        
        
        
        // Expected results are:
        
        // x1 0x00000200
        // x2 0x80A57F01 // Full Word
        // x3 0xFFFFFFA5 // Loads the byte A5
        // x4 0x00000001 // loads byte 01 at offset 0
        // x5 0x00007F01 // Load lower halfword
        // x6 0xFFFF80A5 // Load upperhalfword, then sign extend (the upper halfword is 80A5)
        
        for (int i = 0; i < 32; i = i + 1) // All regs
            $display("Register x%0d : 0x%08h", i, myCUnit.my_regs.registers[i]);
        $finish;
    end

endmodule
