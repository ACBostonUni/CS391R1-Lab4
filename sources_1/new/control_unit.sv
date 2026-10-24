`timescale 1ns / 1ps

module control_unit (
    input  wire         clk,
    input  wire         rst,
    output logic        error,

    // AXI4-Lite read address channels

    input  wire         arready,
    output logic [19:0]  araddr,
    output logic        arvalid,

    // AXI4-Lite read data channels

    input  wire [31:0]  rdata,
    input  wire         rvalid,
    output logic        rready,
    
    // AXI write address channel
    input  wire        awready,
    output logic [19:0] awaddr,
    output logic       awvalid,

    // AXI write data channel
    input  wire        wready,
    output logic [31:0] wdata,
    output logic [3:0]  write_strobe,
    output logic       wvalid,

    // AXI write response channel
    input  wire        bvalid,
    output logic       bready
);

    localparam int bitWidth = 32;
    localparam int num_regs = 32;
    localparam logic [31:0] EBREAK = 32'h0010_0073;

     // PC and curr registers to keep track of instruction flow
    logic [31:0] PC;
    logic [31:0] curr_instruction;

    
    typedef enum logic [2:0] { // type for the 6 states
         // enum because its cool to use words
        READY,
        WAITING,
        EXECUTE,
        LOAD_REQUEST,
        LOAD_WAITING,
        LOAD_WB,
        STORE_REQ, // Send the write address and write data, handle handshakes
        STORE_WAIT // Wait for BRAM's response
    } state_t;

    state_t state; // instantiate a state instance


   // Instruction field slicing :D

    logic [6:0]  opCode;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [6:0]  funct7;
    logic [11:0] imm;
    logic [19:0] immU;

    assign opCode = curr_instruction[6:0];
    assign rd     = curr_instruction[11:7];
    assign funct3 = curr_instruction[14:12];
    assign rs1    = curr_instruction[19:15];
    assign rs2    = curr_instruction[24:20];
    assign funct7 = curr_instruction[31:25];
    assign imm    = curr_instruction[31:20];
    assign immU   = curr_instruction[31:12];


   
    logic [11:0] immS;
    assign immS = {curr_instruction[31:25], curr_instruction[11:7]};
    // reg file declarations and assignment
    wire [4:0] rd_sel = rd;
    wire [4:0] rs_sel = rs1;
    wire [4:0] rt_sel = rs2;
    wire write;
    logic [bitWidth-1:0] d_in;
    wire [bitWidth-1:0] rs;
    wire [bitWidth-1:0] rt;
    
     // alu declarations

   
    wire [bitWidth-1:0] op1;
    logic [bitWidth-1:0] op2;
    logic [9:0] control;
    wire [bitWidth-1:0] res;
    wire alu_error;  //new error wire

    
     wire isLoad;

    assign isLoad = (opCode == 7'b0000011);
    // Is it a load??
   
    wire isStore;
    assign isStore = (opCode == 7'b0100011);
    wire validOpCode;

    assign op1  = rs;
    

    assign validOpCode = // Sanity check make sure we get an opcode we can handle

        (opCode == 7'b0110011) || // R-type 
        (opCode == 7'b0010011) || // I-type 
        (opCode == 7'b0110111) ||   // LUI
        (opCode == 7'b0000011) || // Load
        (opCode == 7'b0100011); // Store

    assign write = !rst && (rd != 5'd0) && !alu_error &&
               (
                   // Regular execute and LUI writeback assignments
                   (state == EXECUTE &&
                    validOpCode &&
                    curr_instruction != EBREAK &&
                    !isLoad && !isStore)

                   ||

                   // if Load writeback. then we also want to write
                   (state == LOAD_WB && isLoad)
               );
     // Write Enable Assign Logic if rd == 0, then we just dont write. 
    // I first did it in the reg file, but this is cleaner

    
    
    register_file #(
        .reg_size(bitWidth),
        .num_reg(num_regs)
    ) my_regs (
        .clk   (clk),
        .we    (write),
        .d_in  (d_in),
        .rd_sel(rd_sel),
        .rs_sel(rs_sel),
        .rt_sel(rt_sel),
        .rst   (rst),
        .rs    (rs),
        .rt    (rt)
    );

    // ALU instance. The ALU implementation itself is unchanged.
    alu #(
        .opWidth(bitWidth)
    ) myalu (
        .op1    (op1),
        .op2    (op2),
        .control(control),
        .error  (alu_error),// Feed in the new ALU error
        .res    (res)
    );
    
    
  
    
    logic [31:0] loadData; // new addition to handle loads
    logic [31:0] loadAddr;
    logic [7:0] selByte;
    logic [15:0] selHalf;


    // Our logic for determining which type on instruction it is


    
    always_comb begin
        // Default values 
        op2     = 32'b0;
        control = 10'b0;
        d_in = res; // default d_in = res
        
        // Default values for the selected memory portions.
        selByte = 8'b0;
        selHalf = 16'b0;
        
        // (In cases of Load Byte)
        // Use a case statement here to check which byte we are going to read of the 32 bit chunk
        case (loadAddr[1:0])
            2'b00: selByte = loadData[7:0];
            2'b01: selByte = loadData[15:8];
            2'b10: selByte = loadData[23:16];
            2'b11: selByte = loadData[31:24];
        endcase
        
        // Same thing here but now we are selecting which half if cases of Load Half
        case (loadAddr[1])
            1'b0: selHalf = loadData[15:0];
            1'b1: selHalf = loadData[31:16];
        endcase
        
        case (opCode) // Made a case statement for opcode, felt more streamlined than the ifs
            7'b0110011: begin // R-type Instruction
               
                op2     = rt;
                control = {funct3, funct7};
            end

            7'b0010011: begin // I-type Instruction
                
                op2 = {{20{imm[11]}}, imm};

                 // for shift instructions that require the imm[11:5] we check if it is those
                if ((funct3 == 3'b001) || (funct3 == 3'b101))
                    control = {funct3, imm[11:5]};
                else
                    control = {funct3, 7'b0};
            end

            7'b0110111: begin // LUI option. Simply add 12 0's to the end and then give it to the ALU. (ALU will just set res = op2)
                
                op2     = {immU, 12'b0};
                control = {3'b000, 7'h11}; // Existing ALU control encoding for LUI.
            end
            
            7'b0000011: begin // This is an I-type (LOAD) <---
                // d_in will not be equal to res this time. 
                op2 = {{20{imm[11]}}, imm}; // Same as I type regular
                control = {3'h0, 7'h00}; // since we are always adding, hardcode the ALU add
                if (state == LOAD_WB) begin // If we are in the place to write back 
                    
                     case (funct3)

                        3'b000: begin // LB: load byte, sign-extend
                        d_in = {{24{selByte[7]}}, selByte};
                        end

                        3'b001: begin // LH: load halfword, sign-extend
                        d_in = {{16{selHalf[15]}}, selHalf};
                        end 
                        
                        
                        // I originally didn't sign extend, but I realized that negative nums would be misrepresented

                        3'b010: begin // LW: load full word
                        d_in = loadData;
                        end
                      
                     
                    endcase
                end
            end
            
            7'b0100011: begin // Store
                        
                  d_in = 32'h00000000; // we will not be writing so set d_in to the 0 reg
                  op2     = {{20{immS[11]}}, immS};
                  control = {3'b000, 7'h00};  // HardCode ALU add
                        
                    
                 end    
           // removed the default case I had previously. Didn't need it. 
        endcase
    end


    // Finite state machine for Fetch Decode Execute (This was hard to put together)

    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset the CPU's instruction-fetch state and AXI read controls.
            PC               <= 32'b0;
            curr_instruction <= 32'b0;
            state            <= READY;
            araddr           <= 20'b0;
            arvalid          <= 1'b0;
            rready           <= 1'b0;
            error            <= 1'b0;
            
            loadAddr <= 32'b0;
            loadData    <= 32'b0;
            
            // The write sig suite
            awaddr  <= 20'b0;
            awvalid <= 1'b0;
            wdata   <= 32'b0;
            write_strobe  <= 4'b0;
            wvalid  <= 1'b0;
            bready  <= 1'b0;
            
            
        end else begin
            case (state)
                READY: begin
                    rready <= 1'b0;

                    if (!arvalid) begin // Hold arvalid & araddr stable until arvalid && arready.

                        araddr  <= PC[19:0];
                        arvalid <= 1'b1;
                    end

                    // If both 

                    if (arvalid && arready) begin
                        arvalid <= 1'b0;// valid goes to low
                        rready  <= 1'b1;// ready to read
                        state   <= WAITING; // Change state to waiting

                    end
                end

                WAITING: begin
                    // Accept data only on the actual AXI read handshake.
 
                    if (rvalid && rready) begin
                       
                        curr_instruction <= rdata;
                        rready           <= 1'b0;
                        error            <= 1'b0; // Clear the previous error for this instruction.
                        state            <= EXECUTE;
                    end
                end

                EXECUTE: begin
                    rready <= 1'b0;

                   
                    if (curr_instruction == EBREAK) begin // we reached ebreak
                                                            //  // I learned that ebreak is 32'h0010_0073 
                        arvalid <= 1'b0;
                        state   <= EXECUTE;
                        
                    end else if (isLoad) begin
                    // Error checking for alu just in case, I didn't even think of this originally. 
                    if (alu_error) begin //  Godo idea to check though. 
                    error <= 1'b1;
                    PC    <= PC + 32'd4;
                    state <= READY;
                    end
                       
                    else begin
                    
                    // Save the original address, including the byte offset.
                    loadAddr <= res; // address calculated by the ALU

                    // Request the containing 32-bit word.
                    araddr <= {res[19:2], 2'b00}; // chop off the last 2 bits
                    
                    /// Okay so we doc 2 off replace with 0 to start at the front of 
                    // the 32 bit chunk that way we get all 4 bytes in scope, then we use the original 2 bits we dropped off to determine which byte we select out of the 32 bit chunk.
                    
                    // 2 bits is eliminating a dynamic amount of places, 
                    // we arent going back 2 spots every time. We go back as many spots as the value of the 2 bits we drop
                    
                    // So say that ALU calculates to grab val at 0x103
                    // we drop that 11 so now we have 0x100 
                    // consider all partitions either 4 bytes or 2 halfs
                    // Then we saved those actual to bytes in loadAddr which then picks out the one we want in the case
                    
                    // I'm having to teach myself how to do this while coding it :)
                   
                    arvalid <= 1'b1;
                    state   <= LOAD_REQUEST;
                    end
                    
                    end
                    
               else if (isStore) begin
                    // Again check for the ALU error
                    if(alu_error) begin
                    error <= 1'b1;
                    PC <= PC + 32'd4;
                    state <= READY;
               end else begin
               
               
                    case (funct3)
                    
                        3'b000: begin// Store Byte
                        
                        awaddr <= {res[19:2], 2'b00}; // Alignment just like we did in loads, and I recall now why we do this
                        
                        case(res[1:0])
                            2'b00: begin
                                wdata <= {24'b0, rt[7:0]};
                                write_strobe <= 4'b0001; // write strobe set to [7:0]
                            end
                            
                            2'b01: begin
                                wdata <= {16'b0, rt[7:0], 8'b0}; // align for [15:8]
                                write_strobe <= 4'b0010;
                            end
                            2'b10: begin
                            wdata <= {8'b0, rt[7:0], 16'b0}; // align for [23:16]
                            write_strobe <= 4'b0100;
                            end
                            
                            2'b11: begin
                            wdata <= {rt[7:0], 24'b0}; // align for [31:24]
                            write_strobe <= 4'b1000;
                        end
                            
                        
                        endcase
                        
                        awvalid <= 1'b1;
                        wvalid  <= 1'b1;
                        bready  <= 1'b0;
                        state   <= STORE_REQ;
                        end 
                        
                        
                        3'b001: begin // Store Half
                        if (res[0] == 1'b0) begin // test if address is even
                            awaddr <= {res[19:2], 2'b00};
                         
                            case(res[1])
                            
                                1'b0: begin
                                    wdata <= {16'b0, rt[15:0]};
                                    write_strobe <= 4'b0011;
                                end
                                
                                1'b1: begin
                                    
                                    wdata <= {rt[15:0], 16'b0};
                                    write_strobe <= 4'b1100;
                                end
                            
                            endcase
                            awvalid <= 1'b1;
                            wvalid  <= 1'b1;
                            bready  <= 1'b0;
                            state   <= STORE_REQ;
                        
                        end else begin
                        
                            // Halfword address must be even :o
                            error <= 1'b1;
                            PC    <= PC + 32'd4;
                            state <= READY;
                        
                        end
                        
                    end 
                        
                    3'b010: begin // Store A Word
                    
                    if(res[1:0] == 2'b00) begin
                        awaddr <= {res[19:2], 2'b00}; // alignment
                        wdata <= rt; // all of rt (because word)
                        write_strobe <= 4'b1111; // All on
                        
                        awvalid <= 1'b1;
                        wvalid  <= 1'b1;
                        bready  <= 1'b0;
                        state   <= STORE_REQ;
                    
                    end else begin
                         // Word address must be aligned to four bytes.
                        error <= 1'b1;
                        PC    <= PC + 32'd4;
                        state <= READY;
                    
                    end
                    
                    end
                    
                    default: begin
                    // Unsupported store funct3. // I didn't do the other ones
                    error <= 1'b1;
                    PC    <= PC + 32'd4;
                    state <= READY;
                    end
                        
                    endcase
                    
                    
                    
                    
               end
                    
               end
                    
                    
                    else begin
                       // If we have an alu error or the instr isnt valid set error to high

                        if (!validOpCode || alu_error) begin
                            error <= 1'b1;
                        end

       
                        PC    <= PC + 32'd4;
                        state <= READY;
                    end
                end
                
                
                LOAD_REQUEST: begin
                // Keep the read address valid until memory accepts it.(Same basic AXL4Lite stuff)
                    if (arvalid && arready) begin
                    arvalid <= 1'b0;
                    rready  <= 1'b1;
                    state   <= LOAD_WAITING;
                    end
                end
                LOAD_WAITING: begin
                // Capture data only after the AXI read handshake.
                    if (rvalid && rready) begin // Handshake, then now grab the data from memory
                    loadData <= rdata;
                    rready    <= 1'b0;
                    state     <= LOAD_WB;
                    end
                end

                LOAD_WB: begin
                // The register file writes load_data during this state.
                PC    <= PC + 32'd4;
                state <= READY;
                end
                
                STORE_REQ: begin
                // Handle the address and data channels (we need both agreements)
                
                if(awvalid && awready) begin
                    awvalid <= 1'b0;
                end
                
                if (wvalid && wready) begin
                    wvalid <= 1'b0;
               
                end
                
                if ((!awvalid || awready) && (!wvalid || wready)) begin // Check for both aggreements
                
                    bready <= 1'b1;
                    state <= STORE_WAIT;
                    
                end
                
                
                
                end
                
                
                STORE_WAIT: begin
                
                if (bvalid && bready) begin // Done waiting! Return to READY for the next instruction
                    bready <= 1'b0;
                    PC <= PC + 32'd4;
                    state <= READY;
                
                end
                
                end
                

                default: begin
                    // Recover to a known fetch state if the FSM ever reaches an invalid state.
                    state   <= READY;
                    arvalid <= 1'b0;
                    rready  <= 1'b0;
                end
            endcase
        end
    end

endmodule
