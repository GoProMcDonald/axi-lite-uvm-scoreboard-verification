interface axi_if(input logic clk, input logic rst_n);
  // Write address channel
  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;

  // Write data channel
  logic [31:0] wdata;
  logic  [3:0] wstrb;
  logic        wvalid;
  logic        wready;

  // Write response channel
  logic  [1:0] bresp;
  logic        bvalid;
  logic        bready;

  // Read address channel
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;

  // Read data channel  
  logic [31:0] rdata;
  logic  [1:0] rresp;
  logic        rvalid;
  logic        rready;

  // 默认驱动任务（可选）
  task automatic drive_defaults();
    awaddr  <= '0; awvalid <= 0;
    wdata   <= '0; wstrb   <= 4'hF; wvalid <= 0;
    bready  <= 0;
    araddr  <= '0; arvalid <= 0;
    rready  <= 0;
  endtask
endinterface
