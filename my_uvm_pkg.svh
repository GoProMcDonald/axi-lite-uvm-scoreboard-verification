//tb_top (SystemVerilog 顶层模块)
   //|
   //|-- run_test("axi_smoke_test")   // 告诉 UVM：我要跑哪个 test 类
   //       |
   //       v
   //axi_smoke_test::build_phase()    // 创建 env（里面有 agent、scoreboard）
   //axi_smoke_test::run_phase()      // 创建并 start smoke_sequence
   //       |
   //       v
   //env.agent.sqr <--- seq           // sequencer 驱动 driver
   //       |
   //       v
   //driver 发激励 → DUT
   //monitor 采集总线事务 → scoreboard 检查


`ifndef MY_UVM_PKG_SVH//头文件保护（header guard）如果没有这个保护，你的 axi_seq_item、axi_driver 这些类可能会被编译两遍，直接报错。
`define MY_UVM_PKG_SVH//那么现在定义它

`include "uvm_macros.svh"//把 UVM 的宏定义文件引进来。里面有我们常用的\uvm_component_utils(...)、`uvm_object_utils(...)、`uvm_info/.../error/fatal` 等宏。

package my_uvm_pkg;//定义一个包，所有后面的类型、类、typedef 都放在这个命名空间里，方便在别的文件里一句 import my_uvm_pkg::*; 全部引入
  import uvm_pkg::*;// 引入 UVM 包，包含了 UVM 的所有类和宏定义
  `uvm_analysis_imp_decl(_exp)
  `uvm_analysis_imp_decl(_act)
  // --------------------- Transaction ---------------------
  class axi_seq_item extends uvm_sequence_item;//会在这里放：write/addr/data/... 字段、do_print/do_copy/do_compare 等方法。
    `uvm_object_utils(axi_seq_item)
    rand bit          write;          // 1=写 0=读
    rand logic [31:0] addr;
         logic [31:0] data;           // 写入的数据或读回的数据
    function new(string name="axi_seq_item"); super.new(name); endfunction
    virtual function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_field_int("write", write, 1,  UVM_DEC);
        printer.print_field_int("addr" , addr , 32, UVM_HEX);
        printer.print_field_int("data" , data , 32, UVM_HEX);
    endfunction
  endclass

  // --------------------- Sequencer -----------------------
  typedef uvm_sequencer #(axi_seq_item) axi_sequencer;//给带参数的 sequencer起个别名。等价于“一个只处理 axi_seq_item 的 sequencer”。

  // --------------------- Driver --------------------------这个 driver 是 UVM 骨架中唯一会主动去驱动 DUT 信号的模块，它负责把上层 sequence 发来的抽象事务（addr/data/类型）翻译成符合 AXI-Lite 协议的 valid/ready 握手时序，并在正确时机拉高/拉低各个信号。
  class axi_driver extends uvm_driver #(axi_seq_item);
    `uvm_component_utils(axi_driver)//把这个组件注册进 UVM 工厂。以后用 ::type_id::create("drv", parent) 才能创建它
    virtual axi_if vif;//虚接口句柄。driver 通过它给 DUT 施加引脚电平。

     uvm_analysis_port #(axi_seq_item) exp_ap; // 定义一个分析端口 exp_ap，用于接收来自 sequencer 的事务意图（exp）

    function new(string name, uvm_component parent); 
        super.new(name,parent); 
        exp_ap = new("exp_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF","axi_driver: no vif")
    endfunction

    task run_phase(uvm_phase phase);//驱动时序都写在 run 阶段
      // 初始默认
      //@(negedge vif.rst_n);//等一次复位拉低再等复位释放。保证 driver 在“复位完成后”才开始对 DUT 说话。
      @(posedge vif.rst_n);// 等复位释放
      vif.drive_defaults();//调接口里的默认驱动任务，把所有 valid/addr/data 等清零，避免上电即乱驱动。
      forever begin//循环处理事务
        axi_seq_item tr;//定义一个事务变量tr，类型是axi_seq_item
        seq_item_port.get_next_item(tr);//从sequencer拉取下一个事务，阻塞直到有新事务
        exp_ap.write(tr);//把事务克隆一份，发给分析端口 exp_ap（如果有订阅者的话）。这一步是可选的，主要用于调试和验证。
        if (tr.write) drive_write(tr);//如果是写事务，调用 drive_write 子任务
        else          drive_read(tr);// 如果是读事务，调用 drive_read 子任务
        seq_item_port.item_done();//通知sequencer，这个事务已处理完毕，可以发下一个
      end
    endtask

    task automatic drive_write(axi_seq_item tr);
      // 地址/数据/握手
      @(posedge vif.clk);
      vif.awaddr  <= tr.addr;
      vif.awvalid <= 1;
      vif.wdata   <= tr.data;
      vif.wstrb   <= 4'hF;
      vif.wvalid  <= 1;
      vif.bready  <= 1;

      // 等待 AW & W 握手
      wait(vif.awvalid && vif.awready);
      wait(vif.wvalid  && vif.wready);

      // 拉低 valid
      @(posedge vif.clk);
      vif.awvalid <= 0;
      vif.wvalid  <= 0;

      // 等待 BVALID -> BREADY
      wait(vif.bvalid);
      @(posedge vif.clk);
      vif.bready  <= 0;
    endtask

    task automatic drive_read(axi_seq_item tr);
      @(posedge vif.clk);
      vif.araddr  <= tr.addr;
      vif.arvalid <= 1;
      vif.rready  <= 1;

      // 等待 AR 握手
      wait(vif.arvalid && vif.arready);
      @(posedge vif.clk);
      vif.arvalid <= 0;

      // 等待 R 有效（数据由 monitor 捕获）
      wait(vif.rvalid);
      @(posedge vif.clk);
      vif.rready <= 0;
    endtask
  endclass

  // --------------------- Monitor -------------------------
  class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_if vif;// 虚接口，用于读取 DUT 信号
    uvm_analysis_port #(axi_seq_item) ap;//定义了一个名叫 ap 的广播口，它一次能发一个 axi_seq_item 类型的数据给订阅它的模块

    // 暂存上一次AR的地址（AXI-Lite 单拍简单实现）
    logic [31:0] last_araddr;
    bit          has_pending_read;

    function new(string name, uvm_component parent);
      super.new(name,parent);
      ap = new("ap", this);// analysis_port需要new
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))//从UVM配置库里拿一个叫“vif”的 virtual axi_if 存到 vif 变量，没拿到就报错。
        `uvm_fatal("NOVIF","axi_monitor: no vif")
    endfunction

    task run_phase(uvm_phase phase);
      has_pending_read = 0;
      forever begin
        @(posedge vif.clk);
        // 记录AR
        if (vif.arvalid && vif.arready) begin//如果AR握手了，记录地址
          last_araddr       = vif.araddr;
          has_pending_read  = 1;// 标记有未处理的读事务
        end
        // 写事务采样：同拍 AW/W 握手
        if (vif.awvalid && vif.awready && vif.wvalid && vif.wready) begin//如果同一拍握手了写地址和写数据，采样写事务
          axi_seq_item tr = axi_seq_item::type_id::create("wr_tr", this);
          tr.write = 1; tr.addr = vif.awaddr; tr.data = vif.wdata;
          ap.write(tr);
        end
        // 读事务采样：RVALID&RREADY 时吐出读结果
        if (vif.rvalid && vif.rready && has_pending_read) begin//如果RVALID&RREADY握手了，并且有未处理的读事务，采样读事务
          axi_seq_item tr = axi_seq_item::type_id::create("rd_tr", this);
          tr.write = 0; tr.addr = last_araddr; tr.data = vif.rdata;
          ap.write(tr);
          has_pending_read = 0;
        end
      end
    endtask
  endclass

  // --------------------- Agent ---------------------------
  class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    axi_driver    drv;
    axi_sequencer sqr;
    axi_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);//在 build 阶段，用工厂方法 ::type_id::create() 创建出 driver、sequencer、monitor 三个组件，并且把它们挂在当前 agent 下面（this 是 parent）
      super.build_phase(phase);
      drv = axi_driver   ::type_id::create("drv", this);// 创建 driver的实例
      sqr = axi_sequencer::type_id::create("sqr", this);// 创建 sequencer 的实例
      mon = axi_monitor  ::type_id::create("mon", this);//  创建 monitor 的实例
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(sqr.seq_item_export);//连接 driver 的 seq_item_port 到 sequencer 的 seq_item_export，这样 driver 就能从 sequencer 拉取事务了。
    endfunction
  endclass

  // --------------------- Scoreboard -----------------------------
  class axi_scoreboard extends uvm_scoreboard;//定义一个名为 axi_scoreboard 的 UVM 组件，类型是 scoreboard
  `uvm_component_utils(axi_scoreboard)//把该类注册到 UVM 工厂，以后可以用 ::type_id::create("scb", parent) 创建它。

  uvm_analysis_imp_exp #(axi_seq_item, axi_scoreboard) exp_imp; //一个 analysis_imp 终端，接收 driver 发来的“期望/意图”事务（exp）
  uvm_analysis_imp_act #(axi_seq_item, axi_scoreboard) act_imp; //一个 analysis_imp 终端，接收 monitor 发来的“实际/采样”事务（act）

  bit [31:0] ref_mem [bit [31:0]];// 影子模型：用来存储写入的地址和数据。类似于一个笔记本，记录每个地址的写入数据。
  typedef struct packed { bit [31:0] addr; } read_req_t;// 定义一个结构体 read_req_t，包含一个 32 位的地址字段，用于存储读请求的地址。
  read_req_t pending_reads[$];// 定义一个动态数组 pending_reads，用于存储所有未处理的读请求。

  int unsigned num_read_checked;// 统计已检查的读请求数量
  int unsigned num_write_tracked;// 统计已跟踪的写请求数量
  int unsigned num_mismatch;// 统计不匹配的读请求数量

  function new(string name, uvm_component parent);// 构造函数，创建一个 axi_scoreboard 实例
    super.new(name, parent);
    exp_imp = new("exp_imp", this);// 创建一个名为 exp_imp 的 analysis_imp 实例，用于接收期望事务
    act_imp = new("act_imp", this);// 创建一个名为 act_imp 的 analysis_imp 实例，用于接收实际事务
  endfunction

  function void write_exp(axi_seq_item tr);// 接收意图（来自 driver）。处理期望事务（来自 driver）当 driver 的 exp_ap.write(tr) 触发，且连接了 driver.exp_ap → scoreboard.exp_imp，UVM 自动回调到这里。
    if (tr.write) begin// 如果是写事务，把“将要写入的数据”写入影子模型 ref_mem，同时写计数 + 打印日志
      ref_mem[tr.addr] = tr.data;// 更新影子模型
      num_write_tracked++;// 增加写计数
      `uvm_info("SCB/EXP", $sformatf("WRITE intent: addr=0x%08h data=0x%08h", tr.addr, tr.data), UVM_LOW)// 打印写意图信息
    end
    else begin// 如果是读事务，记录这个地址的读请求到 pending_reads 数组中，把读地址排入 pending_reads 队列，等待稍后 monitor 的实际读回来时进行配对比对。
      read_req_t req; req.addr = tr.addr;// 创建一个读请求结构体，设置地址
      pending_reads.push_back(req);// 将读请求添加到 pending_reads 队列
      `uvm_info("SCB/EXP", $sformatf("READ intent:  addr=0x%08h (queued)", tr.addr), UVM_LOW)
    end
  endfunction

  function void write_act(axi_seq_item tr);//接收实际（来自 monitor）。处理实际事务（来自 monitor）当 monitor 的 ap.write(tr) 触发，且连接了 monitor.ap → scoreboard.act_imp，UVM 自动回调到这里。
    read_req_t req;
    logic [31:0]  exp_data;
    if (!tr.write) begin//这里只处理读实际（!tr.cmd），写实际可按需扩展
      if (pending_reads.size() == 0) begin//若没有任何排队的读意图，却来了一个读实际 → 说明时序/配对乱了（或某些读意图丢了），直接记一次不匹配并报错。
        num_mismatch++;// 增加不匹配计数
        `uvm_error("SCB/ACT", $sformatf("Actual READ with no pending intent! addr=0x%08h rdata=0x%08h", tr.addr, tr.data))// 打印错误信息
        return;
      end

      req = pending_reads.pop_front();
      if (req.addr != tr.addr) begin// 如果读请求的地址和实际事务的地址不匹配，说明时序乱了或意图丢失
        num_mismatch++;// 增加不匹配计数
        `uvm_error("SCB/ADDR", $sformatf("READ addr mismatch! exp=0x%08h act=0x%08h", req.addr, tr.addr))// 打印地址不匹配错误
        return;
      end

      exp_data = ref_mem.exists(tr.addr) ? ref_mem[tr.addr] : '0;// 从影子模型中获取期望数据，如果地址未写入过，则默认为0
      if (tr.data !== exp_data) begin// 如果实际读回的数据和期望数据不匹配，记录不匹配并报错
        num_mismatch++;// 增加不匹配计数
        `uvm_error("SCB/MISMATCH", $sformatf("READ data mismatch @0x%08h: EXP=0x%08h ACT=0x%08h", tr.addr, exp_data, tr.data))// 打印数据不匹配错误
      end
      else begin// 如果实际读回的数据和期望数据匹配，打印匹配信息
        num_read_checked++;// 增加已检查的读请求计数
        `uvm_info("SCB/MATCH", $sformatf("READ match @0x%08h: data=0x%08h", tr.addr, tr.data), UVM_LOW)// 打印读匹配信息
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);// 在报告阶段打印统计信息
    `uvm_info("SCB/REPORT", $sformatf(
      "Summary: write_intents=%0d, read_checked=%0d, mismatches=%0d, pending_reads=%0d",
      num_write_tracked, num_read_checked, num_mismatch, pending_reads.size()), UVM_NONE)// 打印统计信息
    if (num_mismatch == 0) `uvm_info("SCB/REPORT", "All checks passed ✅", UVM_NONE)// 如果没有不匹配，打印通过信息
    else `uvm_error("SCB/REPORT", "Some checks failed ❌")// 如果有不匹配，打印失败信息
  endfunction
endclass

  // --------------------- Env -----------------------------
  class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)
    axi_agent      agent;// 定义一个 axi_agent 类型的变量 agent，用于创建和管理 AXI-Lite 代理
    axi_scoreboard sb;// 定义一个 axi_scoreboard 类型的变量 sb，用于验证 AXI-Lite 事务

    function new(string name, uvm_component parent);
        super.new(name,parent); 
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = axi_agent     ::type_id::create("agent", this);// 创建一个 axi_agent 实例
      sb    = axi_scoreboard::type_id::create("sb",    this);// 创建一个 axi_scoreboard 实例
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.drv.exp_ap.connect(sb.exp_imp); // driver → scoreboard（意图exp）
      agent.mon.ap   .connect(sb.act_imp);  // monitor → scoreboard（实际act）
    endfunction

  endclass

  // --------------------- Smoke Sequence ------------------
  class axi_smoke_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(axi_smoke_seq)
    function new(string name="axi_smoke_seq"); super.new(name); endfunction
    task body();
      axi_seq_item tr;

      // wr 0x0 = A5A5_0001
      tr = axi_seq_item::type_id::create("wr0");
      start_item(tr); tr.write=1; tr.addr='h0; tr.data='hA5A5_0001; finish_item(tr);

      // rd 0x0
      tr = axi_seq_item::type_id::create("rd0");
      start_item(tr); tr.write=0; tr.addr='h0;                         finish_item(tr);

      // wr 0x4 = DEAD_BEEF
      tr = axi_seq_item::type_id::create("wr1");
      start_item(tr); tr.write=1; tr.addr='h4; tr.data='hDEAD_BEEF;    finish_item(tr);

      // rd 0x4
      tr = axi_seq_item::type_id::create("rd1");
      start_item(tr); tr.write=0; tr.addr='h4;                         finish_item(tr);
    endtask
  endclass

  // --------------------- Test ----------------------------
  class axi_smoke_test extends uvm_test;
    `uvm_component_utils(axi_smoke_test)
    axi_env env;
    axi_smoke_seq s;  // 只声明

    function new(string name="axi_smoke_test", uvm_component parent=null); 
        super.new(name,parent); 
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi_env::type_id::create("env", this);// 创建一个 axi_env 实例
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);// 抬起一个异步阻塞，表示测试开始
      s = axi_smoke_seq::type_id::create("s", this); // 这里创建
      s.start(env.agent.sqr);// 启动这个 sequence，传入 agent 的 sequencer，这样它就能发事务了。
      #50;
      phase.drop_objection(this);// 放下异步阻塞，表示测试结束
    endtask
  endclass

endpackage
`endif // MY_UVM_PKG_SVH
