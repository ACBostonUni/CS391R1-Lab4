`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Austin Corp
// Engineer: Austin
// 
// Create Date: 09/16/2026 06:38:09 PM
// Design Name: 
// Module Name: alu.sv
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.02 - ALU configured for RiscV
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module alu #(parameter opWidth = 32)(
    input wire [opWidth-1:0] op1,
    input wire [opWidth-1:0] op2,// Can be reg or immidiate
    input wire [9:0] control,
    output reg error,
    output reg [opWidth-1:0] res
    );
    
    
    always_comb begin
    error = 1'b0;
    res   = 1'd0;
    
    if (control == {3'h4, 7'h00}) begin // XOR
    
    res = (op1 ^ op2);
    error = 0;
    
    end else if (control == {3'h7, 7'h00}) begin // AND
    
    res = (op1 & op2);
    error = 0;
    
    end else if (control == {3'h6, 7'h00}) begin // OR
    
    res = (op1 | op2);
    error = 0;
    

    end else if (control == {3'h1, 7'h00}) begin // unsigned logical left SHift
    res = (op1 << op2);
    error = 0;
    
    end else if (control == {3'h5, 7'h00}) begin // unsigned logical right SHift
    res = (op1 >> op2);
    error = 0;
    
    end else if (control == {3'h5, 7'h20}) begin // arithmetic right shift
    res = $signed(op1) >>> op2;
    error = 0;
    
    end else if (control == {3'h0, 7'h00}) begin // Addition
    res = op1 + op2;
    error = 0;
    end else if (control == {3'h0, 7'h20}) begin // Subtraction
    res = op1 - op2;
    error = 0;
    end else if (control == {3'h3, 7'h00}) begin // less Than unsigned
        res = op1 < op2;
        error = 0;
    end  
    
   else if (control == {3'h2, 7'h00}) begin // less Than signed
        res = $signed(op1) < $signed(op2);
        error = 0;
    end else if (control == {3'h0, 7'h11}) begin // LUI Load upper immidiate
        res = op2;
    
    end else if(control == {3'h0, 7'h4}) begin // This is Branch <
        res = $signed(op1) < $signed(op2);
    
    end else if (control == {3'h0, 7'h5}) begin // This is Branch >=
        res = $signed(op1) >= $signed(op2);

    end
    
    end
    
    
 
    
    
endmodule
