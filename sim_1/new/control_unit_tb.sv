`timescale 1ns / 1ps

module control_unit_tb;


    bit clk = 1'b0;
    bit cpu_rst = 1'b1;
    bit bram_rst = 1'b1;
    wire cpu_error;
    // BRAM write signals used to load the program.
    wire        awready; 
    wire        bvalid;
    wire [1:0]  bresp;
    wire        wready;
    // Shared Channels ^^^
    
    logic       tb_awvalid;
    logic [19:0] tb_awaddr;
   
    logic       tb_wvalid;
    logic [31:0] tb_wdata;
    logic       tb_bready;
    // tb Channels ^^^^^

    // Read Channels
    wire        arready; // BRAM raises this when it can accept the CPU's read-address request.
    wire [19:0] araddr; // Address of the instruction the CPU wants to fetch from BRAM.
    wire        arvalid; // CPU raises this to indicate that araddr contains a valid read request.
    wire        rready;  // CPU raises this when it is ready to accept the instruction data.
    wire        rvalid;
    wire [31:0] rdata;


    // 0 is testbench preload
    // 1 is CPU execution stores
    logic cpu_write_mode = 1'b0;

    // ControlUnit write-channel outputs
    wire [19:0] cpu_awaddr; // Memory address CPU wants to write
    wire        cpu_awvalid; // CPU says its write address is valid
    wire [31:0] cpu_wdata; // The data val CPU gives to BRAM
    wire [3:0]  cpu_write_strobe; // Bit selector
    wire        cpu_wvalid; // CPU says write data is valid
    wire        cpu_bready; // CPU ready to recieve write response
 
    // Actual signals delivered to BRAM
    wire [19:0] bram_awaddr; // The selected write address
    wire        bram_awvalid; // Selected writer's address-valid signal
    wire [31:0] bram_wdata; // The write data coming in
    wire [3:0]  bram_wstrb; // Selector for the writer's bytes
    wire        bram_wvalid; // Selected writer's data valid signal
    wire        bram_bready; // Writer's response-ready signal


    // I originally got super confused on the difference in the 
    // BRAM and CPU signals, so I just wanted to put CPU and Bram infront of all of it. 
    // I also added comments to all of this to make sense of things while I am typing it.
    
    localparam int memBytes = 512; // Reserve 512 bytes for the memory image
    localparam logic [31:0] programEndPC = 32'h0000_0160; // PC for program end

    logic [7:0] memory_bytes [0:memBytes-1];   // Store the hex file as individual 8-bit bytes before packing each group of four into an instruction word.
    logic [31:0] word_to_write; // Our instruction to write to BRAM

   
        // Assign the write address channel, if write mode = 1 then cpu awaddr, else tb_awaddr
    assign bram_awaddr =
        cpu_write_mode ? cpu_awaddr : tb_awaddr;
        
        // Assign the Bram Valid, if write mode 1, then we use the CPU awvalid, otherwise use tb_awvalid
    assign bram_awvalid =
        cpu_write_mode ? cpu_awvalid : tb_awvalid;

    // Same logic here with determining which wdata to assign to the bramwdata depending on CPUY write mode
    assign bram_wdata =
        cpu_write_mode ? cpu_wdata : tb_wdata;

    // Logic continues down here the same. Bram,s write suite changes from cpu to tb depending on the write mode. 
    assign bram_wvalid =
        cpu_write_mode ? cpu_wvalid : tb_wvalid;

    // Byte enables: CPU can select individual bytes.
    assign bram_wstrb =
        cpu_write_mode ? cpu_write_strobe : 4'b1111;

    // Write response channel
    assign bram_bready =
        cpu_write_mode ? cpu_bready : tb_bready;
   
   
   
   
   
   
   
    always #5ns clk = ~clk; // 100MHz clock


    



    
    control_unit myCUnit (
        .clk     (clk),
        .rst     (cpu_rst),
        .error   (cpu_error), //Forgot to have any kind of error wire in the testBench
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

        // Add this for writes later // Alright now time to connect
        .awaddr       (cpu_awaddr),
        .awvalid      (cpu_awvalid),
        .wdata        (cpu_wdata),
        .write_strobe (cpu_write_strobe),
        .wvalid       (cpu_wvalid),
        .bready       (cpu_bready)
    );

    // Instantiate the BRAM, yes even the write channels
    // Now I connected up the new bram signals which changed based on the CPU write mode.
    // So those are connected up and now we can write from testbench to bram and cpu to bram
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
        .s_axi_awaddr  (bram_awaddr),
        .s_axi_awprot  (3'b000),
        .s_axi_awready (awready),
        .s_axi_awvalid (bram_awvalid),
        .s_axi_wdata   (bram_wdata),
        .s_axi_wready  (wready),
        .s_axi_wstrb   (bram_wstrb),
        .s_axi_wvalid  (bram_wvalid),
        .s_axi_bready  (bram_bready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid)
    );

    // Write one word to BRAM and wait for the AXI write response.
    // Now this is the tb side of things so all addr, data, valid in here is with the tb prefix
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
            tb_awaddr = address;
            tb_wdata = data;
            tb_awvalid = 1'b1;
            tb_wvalid = 1'b1;
            tb_bready = 1'b0;

            while (!(address_done && data_done)) begin
                @(posedge clk);
                if (tb_awvalid && awready)
                    address_done = 1'b1;
                if (tb_wvalid && wready)
                    data_done = 1'b1;

                @(negedge clk);
                if (address_done)
                    tb_awvalid = 1'b0;
                if (data_done)
                    tb_wvalid = 1'b0;
            end

            tb_bready = 1'b1;
            do begin
                @(posedge clk);
            end while (!(bvalid && tb_bready));
            @(negedge clk);
            tb_bready = 1'b0;
        end
    endtask
    
    // Add in check for CPU error
    always @(negedge clk) begin
    if (cpu_error)
        $display("CPU ERROR: instruction = 0x%08h",
                 myCUnit.curr_instruction);
     end
    
    
    // Start of the test bench for reals
    initial begin
        cpu_rst = 1'b1;
        bram_rst = 1'b1;
        tb_awvalid = 1'b0;
        tb_awaddr = '0;
        tb_wvalid = 1'b0;
        tb_wdata = '0;
        tb_bready = 1'b0;

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
         // We finished preloading the BRAM now hand writes over to the CPU for potential STORES
        cpu_write_mode = 1'b1;
        cpu_rst = 1'b0; // Release the reset of the CPU (oops originally had that commented as reset the CPU)
        $display("Running program..."); //Now show program is running

        
        // Wait until the cpu reaches the Ebreak instruction.
        wait (myCUnit.curr_instruction == 32'h00100073);
        @(negedge clk);
        
        // Checks that determine if some of the branches failed. 
        if (myCUnit.my_regs.registers[31] !== 32'd0)
            $error("FAIL: At least one branch test failed");

        if (myCUnit.my_regs.registers[6] !== 32'd0)
            $error("FAIL: Loop counter should be zero"); // because we subtract from x6 until it equals 0

        if (myCUnit.my_regs.registers[7] !== 32'd3)
            $error("FAIL: Subtractive branch loop should execute three times");
    
        $display("Branch tests completed.");
        
        $display(""); // SPacing
        $display("Register contents:");
        


        //Register	Expected value	   What it is doing
           //x1	          5	         First comparison operand
           //x2	          5	              Equal to x1
          //x3	          7	             X3 is Greater than x1
          //x4	     0xFFFFFFFF	          Signed value -1
          //x5	          1	           Positive comparison operand

   
   
         //  beq x1, x2	(5 = 5)   	Taken
         // bne x1, x2	(5 != 5)	Not taken
         // bne x1, x3	(5 != 7)	Taken
         // beq x1, x3	(5 = 7)	   Not taken
        // blt x4, x5	(-1 < 1)	Taken (Also using signed value)
        // blt x3, x1	(7 < 5)	   Not taken
        // bge x4, x5	(-1 >= 1)	Not taken (Also uses signed)
        //  bge x5, x4	(1 >= -1)	Taken (Also Uses Signed)
        
        // Then finally we test a loop!
        
        // addi x6, x0, 3
        // addi x7, x0, 0
        // loop:
        // addi x7,x7, 1
        // addi x6, x6, -1
        // bne x6, x0, loop
        
        // finally ebreak
        
        
        
        // expected register values:
        
        // Reg x0: 0
        // Reg x1: 5
        // Reg x3: 7
        // Reg x4: 0xffffffff
        // Reg x5: 1
        // Reg x6: 0 // because we subtract 1 from x6 every time we loop
        // Reg x7: 3 // because we add one every time we loop (until x6 reaches 0)
        // Reg x31: 0 // This means that no errors occurred (If not 0, errors in branching occured)
        
        for (int i = 0; i < 32; i = i + 1) // All regs
            $display("Register x%0d : 0x%08h", i, myCUnit.my_regs.registers[i]);
        $finish;
    end

endmodule
