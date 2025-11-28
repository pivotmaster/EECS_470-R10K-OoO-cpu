`include "sys_defs.svh"

module dcache (
    input clock, reset,
    
    // Request from LOAD unit
    input  ADDR        Dcache_addr_0,      // Request 0
    input  MEM_COMMAND Dcache_command_0, // MEM_LOAD or MEM_STORE or MEM_NONE
    input  MEM_SIZE    Dcache_size_0, // WORD/BYTE/HALF
    input  MEM_BLOCK   Dcache_store_data_0, // load = 0
    input  logic [`LQ_IDX_WIDTH-1:0] Dcache_req_tag,

    output logic       Dcache_req_0_accept, // if bank conflict (two request go to the same bank), it might be 0 and need to be resent at the next cycle
    output MEM_BLOCK   Dcache_data_out_0,
    output logic       Dcache_valid_out_0,
    output logic [`LQ_IDX_WIDTH-1:0] Dcache_load_tag,
    
    input  ADDR        Dcache_addr_1,      // Request 1
    input  MEM_COMMAND Dcache_command_1,
    input  MEM_SIZE    Dcache_size_1,
    input  MEM_BLOCK   Dcache_store_data_1,

    output logic       Dcache_req_1_accept,  // if bank conflict (two request go to the same bank), it might be 0
    output MEM_BLOCK   Dcache_data_out_1,
    output logic       Dcache_valid_out_1,
    
    // Memory interface (non-blocking)
    output MEM_COMMAND Dcache2mem_command,
    output ADDR        Dcache2mem_addr,
    output MEM_SIZE    Dcache2mem_size,
    output MEM_BLOCK   Dcache2mem_data,
    
    input  MEM_TAG   mem2proc_transaction_tag, //Tell you the tag for this to mem request (1 cycle after sending request)
    input  MEM_BLOCK mem2proc_data,
    input  MEM_TAG   mem2proc_data_tag
);

    // =========================================================
    // Cache configuration
    // =========================================================

    // Cache parameters
    parameter int CACHE_SIZE = 256;
    parameter int LINE_SIZE = (`XLEN /8) * 2; //8 Bytes
    parameter int CACHE_WAYS = 4;             // 4-way associative
    parameter int BANKS = 2;                  // 2 banks for dual-port
    parameter int CACHE_LINES = 256 / LINE_SIZE;           // Total lines (32 lines)
    parameter int BANK_SIZE = CACHE_LINES / BANKS; // Total lines per bank (16 lines / bank)
    parameter int SETS_PER_BANK = BANK_SIZE / CACHE_WAYS; //4 sets per bank

    parameter int VICTIM_SIZE = 8;            // Victim cache entries
    parameter int MSHR_SIZE = 4;             // Outstanding requests

    // Bits parameters
    parameter int BANK_BITS = $clog2(BANKS); // # bank = 2 (1 bit)
    parameter int OFFSET_BITS = $clog2(LINE_SIZE); // # offset = 8 bytes (3 bits)
    parameter int INDEX_BITS = $clog2(BANK_SIZE / CACHE_WAYS);      // # set = 4 = 16 lines / 4 ways (2 bits per bank)
    parameter int TAG_BITS = `XLEN - INDEX_BITS - OFFSET_BITS - BANK_BITS; // 3 for byte offset
    
    // =========================================================
    // Cache Signals (sent to mem_dp)
    // =========================================================
    // ---------- READ ---------- 
    // Read enable signals
    logic cache_read_en_0, cache_read_en_1;
    // Read addresses 
    logic [INDEX_BITS-1:0] cache_read_addr_0;
    logic [INDEX_BITS-1:0] cache_read_addr_1;
    // Read Data
    MEM_BLOCK [CACHE_WAYS-1:0] cache_data_read_0 ;
    MEM_BLOCK [CACHE_WAYS-1:0] cache_data_read_1;
    MEM_BLOCK line_data_0, line_data_1;  //this is the read result in the whole line format
    MEM_BLOCK updated_line_0 ,updated_line_1; // if store: modified the line and put it back to the cache line
    
    // ---------- WRITE ---------- 
    // Write enable signals
    logic  [CACHE_WAYS-1:0] cache_write_en_0;
    logic  [CACHE_WAYS-1:0] cache_write_en_1;
    logic  [CACHE_WAYS-1:0] cache_write_en_hit_0;
    logic  [CACHE_WAYS-1:0] cache_write_en_hit_1;
    logic  [CACHE_WAYS-1:0] cache_write_en_refill_0;
    logic  [CACHE_WAYS-1:0] cache_write_en_refill_1;

    // Write addresses 
    logic [INDEX_BITS-1:0] cache_write_addr_0, cache_write_addr_hit_0, cache_write_addr_refill_0;
    logic [INDEX_BITS-1:0] cache_write_addr_1, cache_write_addr_hit_1, cache_write_addr_refill_1;

    // Write Data
    MEM_BLOCK cache_write_data_0, cache_write_data_hit_0, cache_write_data_refill_0;
    MEM_BLOCK cache_write_data_1, cache_write_data_hit_1, cache_write_data_refill_1;

    genvar w;
    for (w = 0; w < CACHE_WAYS; w++) begin
        assign cache_write_en_0[w] = cache_write_en_hit_0[w] | cache_write_en_refill_0[w];
        assign cache_write_en_1[w] = cache_write_en_hit_1[w] | cache_write_en_refill_1[w];
    end

    assign cache_write_addr_0 =
        (|cache_write_en_refill_0) ? cache_write_addr_refill_0 : cache_write_addr_hit_0;
    assign cache_write_addr_1 =
        (|cache_write_en_refill_1) ? cache_write_addr_refill_1 : cache_write_addr_hit_1;

    assign cache_write_data_0 =
        (|cache_write_en_refill_0) ? cache_write_data_refill_0 : cache_write_data_hit_0;
    assign cache_write_data_1 =
        (|cache_write_en_refill_1) ? cache_write_data_refill_1 : cache_write_data_hit_1;

    // =========================================================
    // Cache helper bits
    // =========================================================
    // ----------  Banked, associative storage ----------
    logic [TAG_BITS-1:0]       cache_tags [BANKS-1:0][SETS_PER_BANK-1:0][CACHE_WAYS-1:0];
    logic [CACHE_WAYS-1:0]     cache_valid[BANKS-1:0][SETS_PER_BANK-1:0];
    logic [CACHE_WAYS-1:0]     cache_dirty[BANKS-1:0][SETS_PER_BANK-1:0];


    // ---------- LRU tracking for replacement ---------- 
    logic [$clog2(CACHE_WAYS)-1:0] lru_bits [BANKS-1:0][SETS_PER_BANK-1:0][CACHE_WAYS-1:0];

    // =========================================================
    // Main Cache Arrays
    // =========================================================
    // even bank (bank bit = 0)
    genvar i;
    for (i = 0; i < CACHE_WAYS; i++) begin : gen_cache_data_bank_even
        memDP #(
            .WIDTH(LINE_SIZE * 8),           // MEM_BLOCK width (in bytes)
            .DEPTH(SETS_PER_BANK),  // = set size = 4 (each DP contains 1 way)
            .READ_PORTS(1),       
            .BYPASS_EN(1)         // Enable bypass for write-through
        ) cache_data_0 (
            .clock(clock),
            .reset(reset),
            .re(cache_read_en_0),
            .raddr(cache_read_addr_0),
            .rdata(cache_data_read_0[i]),
            .we(cache_write_en_0[i]),
            .waddr(cache_write_addr_0),
            .wdata(cache_write_data_0)
        );
    end 

    // odd bank (bank bit = 1)
    genvar j;
    for (j = 0; j < CACHE_WAYS; j++) begin : gen_cache_data_bank_odd
        memDP #(
            .WIDTH(LINE_SIZE * 8),           // MEM_BLOCK width (in bytes)
            .DEPTH(SETS_PER_BANK),  //= set size (each DP contains 1 way)
            .READ_PORTS(1),       
            .BYPASS_EN(1)         // Enable bypass for write-through
        ) cache_data_1 (
            .clock(clock),
            .reset(reset),
            .re(cache_read_en_1),
            .raddr(cache_read_addr_1),
            .rdata(cache_data_read_1[j]),
            .we(cache_write_en_1[j]),
            .waddr(cache_write_addr_1),
            .wdata(cache_write_data_1)
        );
    end 
    
    // // =========================================================
    // // Victim Cache
    // // =========================================================
    // typedef struct packed {
    //     logic valid;
    //     logic [CACHE_TAG_BITS-1:0] tag;
    //     logic [CACHE_INDEX_BITS-1:0] index;
    //     MEM_BLOCK data;
    //     logic dirty;
    // } victim_entry_t;

    // victim_entry_t victim_cache [VICTIM_SIZE-1:0];
    // logic [$clog2(VICTIM_SIZE)-1:0] victim_lru [VICTIM_SIZE-1:0];


    // =========================================================
    // Cache Control
    // =========================================================
    // ----------  Address breakdown ---------- 
    logic [TAG_BITS-1:0] tag_0, tag_1;
    logic [INDEX_BITS-1:0] index_0, index_1;
    logic [OFFSET_BITS-1:0] offset_0, offset_1;
    logic [BANK_BITS-1:0] bank_0, bank_1;

    assign bank_0 = Dcache_addr_0[OFFSET_BITS +: BANK_BITS];
    assign offset_0 = Dcache_addr_0[0 +: OFFSET_BITS];
    assign index_0 =  Dcache_addr_0[OFFSET_BITS + BANK_BITS +: INDEX_BITS];
    assign tag_0 =  Dcache_addr_0[31 : OFFSET_BITS + BANK_BITS + INDEX_BITS];

    assign bank_1  = Dcache_addr_1[OFFSET_BITS +: BANK_BITS];
    assign offset_1 = Dcache_addr_1[0 +: OFFSET_BITS];
    assign index_1 = Dcache_addr_1[OFFSET_BITS + BANK_BITS +: INDEX_BITS];
    assign tag_1   = Dcache_addr_1[31 : OFFSET_BITS + BANK_BITS + INDEX_BITS];

    // ----------  Bank determiniation ---------- (turn #request to #BANK)
    logic req_0_to_bank_0, req_0_to_bank_1, req_1_to_bank_0, req_1_to_bank_1;
    logic req_0_accept,req_1_accept; //whether request has assign to bank

    //### load & store both can use ###//
    assign req_0_to_bank_0 = (Dcache_command_0 != MEM_NONE) && !bank_0;
    assign req_0_to_bank_1 = (Dcache_command_0 != MEM_NONE) && bank_0;
    assign req_1_to_bank_0 = (Dcache_command_1 != MEM_NONE) && !req_0_to_bank_0 && !bank_1;
    assign req_1_to_bank_1 = (Dcache_command_1 != MEM_NONE) && !req_0_to_bank_1 && bank_1;

    assign req_0_accept = req_0_to_bank_0 || req_0_to_bank_1;
    assign req_1_accept = req_1_to_bank_0 || req_1_to_bank_1;

    // ----------  Cache Hit Detection ----------       
    //### The 1/0 here is from CPU REQUEST not bank ###//
    //### load & store both can use ###//
    logic [CACHE_WAYS-1:0] way_hit_0, way_hit_1;  // all ways hit =1 , miss = 0 (ex: 0010)
    logic [1:0] hit_way_0, hit_way_1;  //which way hit (ex: 2)
    logic cache_hit_0, cache_hit_1, load_cache_hit_0, load_cache_hit_1, store_cache_hit_0, store_cache_hit_1;

    always_comb begin
        way_hit_0 = '0;
        way_hit_1 = '0;
        hit_way_0 = 0;
        hit_way_1 = 0;
        
        // Check all ways for hits using arrays (valid and tag match)
        for (int w = 0; w < CACHE_WAYS; w++) begin
            way_hit_0[w] = cache_valid[bank_0][index_0][w] && (cache_tags[bank_0][index_0][w] == tag_0);
            way_hit_1[w] = cache_valid[bank_1][index_1][w] && (cache_tags[bank_1][index_1][w] == tag_1);
        end
        
        // hit or miss
        cache_hit_0 = (|way_hit_0) ;
        cache_hit_1 = (|way_hit_1);

        load_cache_hit_0 = cache_hit_0 && Dcache_command_0 == MEM_LOAD;
        load_cache_hit_1 = cache_hit_1 && Dcache_command_1 == MEM_LOAD;

        store_cache_hit_0 = cache_hit_0 && Dcache_command_0 == MEM_STORE;
        store_cache_hit_1 = cache_hit_1 && Dcache_command_1 == MEM_STORE;

        // check which way hit
        for (int w = 0; w < CACHE_WAYS; w++) begin
            if (way_hit_0[w]) hit_way_0 = w;
            if (way_hit_1[w]) hit_way_1 = w;
        end
    end

    // =========================================================
    // Load (Read) Logic 
    //
    // ### Cannot use load_cache_hit because it still need to read the whole line while write! ###//
    // =========================================================  
    // ----------  Read enable signals ----------    
    assign cache_read_en_0 = (req_0_to_bank_0 && Dcache_req_0_accept) || (req_1_to_bank_0 && Dcache_req_1_accept);
    assign cache_read_en_1 = (req_0_to_bank_1 && Dcache_req_0_accept) || (req_1_to_bank_1 && Dcache_req_1_accept);

    // ----------  Assign Read address ----------    
    // Only need index to determine which set 
    assign cache_read_addr_0 = (req_0_to_bank_0) ? index_0 : (req_1_to_bank_0) ? index_1 : '0;
    assign cache_read_addr_1 = (req_0_to_bank_1) ? index_0 : (req_1_to_bank_1) ? index_1 : '0;

    // ----------  Get Read Result ---------- 
    always_comb begin
        Dcache_load_tag = (Dcache_valid_out_0) ? Dcache_req_tag : '0; // if cache miss, tag = 0 //### 11/25 ###//
        Dcache_valid_out_0 = (load_cache_hit_0) && Dcache_req_0_accept; //Actually Dcache_req_0_accept contains (Dcache_command_0 != MEM_NONE)
        Dcache_valid_out_1 = (load_cache_hit_1) && Dcache_req_1_accept;
        Dcache_data_out_0 = '0; //8 byte per line = 64 bits
        Dcache_data_out_1 = '0;
        line_data_0 = '0;
        line_data_1 = '0;

        if (cache_hit_0) begin
            if (req_0_to_bank_0) line_data_0 = cache_data_read_0[hit_way_0];
            else if (req_0_to_bank_1) line_data_0 = cache_data_read_1[hit_way_0];
        end 

        if (cache_hit_1) begin
            if (req_1_to_bank_0) line_data_1 = cache_data_read_0[hit_way_1];
            else if (req_1_to_bank_1) line_data_1 = cache_data_read_1[hit_way_1];
        end 

        // Choose the data to cpu by data size and offset
        if (load_cache_hit_0 || load_cache_hit_1) begin
            unique case (Dcache_size_0)
                BYTE:    Dcache_data_out_0.byte_level[0] = line_data_0.byte_level[offset_0];
                HALF:    Dcache_data_out_0.half_level[0] = line_data_0.half_level[offset_0[OFFSET_BITS-1:1]];
                WORD:    Dcache_data_out_0.word_level[0] = line_data_0.word_level[offset_0[OFFSET_BITS-1:2]];
                DOUBLE:  Dcache_data_out_0.dbbl_level = line_data_0.dbbl_level;
                default: Dcache_data_out_0.dbbl_level = line_data_0.dbbl_level;
            endcase
            unique case (Dcache_size_1)
                BYTE:    Dcache_data_out_1.byte_level[0] = line_data_1.byte_level[offset_1];
                HALF:    Dcache_data_out_1.half_level[0] = line_data_1.half_level[offset_1[OFFSET_BITS-1:1]];
                WORD:    Dcache_data_out_1.word_level[0] = line_data_1.word_level[offset_1[OFFSET_BITS-1:2]];
                DOUBLE:  Dcache_data_out_1.dbbl_level = line_data_1.dbbl_level;
                default: Dcache_data_out_1.dbbl_level = line_data_1.dbbl_level;
            endcase

        // Data from memory refill_mshr_id
        end else if (mem2proc_data_tag != 0) begin
            unique case (Dcache_size_0)
                BYTE:    Dcache_data_out_0.byte_level[0] = mem2proc_data.byte_level[offset_0];
                HALF:    Dcache_data_out_0.half_level[0] = mem2proc_data.half_level[offset_0[OFFSET_BITS-1:1]];
                WORD:    Dcache_data_out_0.word_level[0] = mem2proc_data.word_level[offset_0[OFFSET_BITS-1:2]];
                DOUBLE:  Dcache_data_out_0.dbbl_level = mem2proc_data.dbbl_level;
                default: Dcache_data_out_0.dbbl_level = mem2proc_data.dbbl_level;
            endcase
            unique case (Dcache_size_1)
                BYTE:    Dcache_data_out_1.byte_level[0] = mem2proc_data.byte_level[offset_1];
                HALF:    Dcache_data_out_1.half_level[0] = mem2proc_data.half_level[offset_1[OFFSET_BITS-1:1]];
                WORD:    Dcache_data_out_1.word_level[0] = mem2proc_data.word_level[offset_1[OFFSET_BITS-1:2]];
                DOUBLE:  Dcache_data_out_1.dbbl_level = mem2proc_data.dbbl_level;
                default: Dcache_data_out_1.dbbl_level = mem2proc_data.dbbl_level;
            endcase
        end
    end


    // =========================================================
    // Store (Write) Logic
    // =========================================================  
    // ----------  Write enable signals ----------    
    always_comb begin 
        for (int w = 0; w < CACHE_WAYS; w++) begin
            cache_write_en_hit_0[w] = 1'b0;
            cache_write_en_hit_1[w] = 1'b0;
        end
        // bank 0 enable
        if (store_cache_hit_0 && req_0_to_bank_0) begin
            cache_write_en_hit_0[hit_way_0] = 1'b1;
        end else if (store_cache_hit_1 && req_1_to_bank_0) begin
            cache_write_en_hit_0[hit_way_1] = 1'b1;
        end

        // bank 1 enable
        if (store_cache_hit_0 && req_0_to_bank_1) begin
            cache_write_en_hit_1[hit_way_0] = 1'b1;
        end else if (store_cache_hit_1 && req_1_to_bank_1) begin
            cache_write_en_hit_1[hit_way_1] = 1'b1;
        end
    end

    // ----------  Assign Write address ----------    
    // Only need index to determine which set 
    assign cache_write_addr_hit_0 = (req_0_to_bank_0 && store_cache_hit_0) ? index_0 : (req_1_to_bank_0 && store_cache_hit_1) ? index_1 : '0;
    assign cache_write_addr_hit_1 = (req_0_to_bank_1 && store_cache_hit_0) ? index_0 : (req_1_to_bank_1 && store_cache_hit_1) ? index_1 : '0;

    // ---------- Write Data ---------- 
    always_comb begin
        updated_line_0 = line_data_0; // from read memDP
        updated_line_1 = line_data_1; // from read memDP

        // Get hit line and update the value we want to write 
        if (store_cache_hit_0) begin
            unique case (Dcache_size_0)
                BYTE:    updated_line_0.byte_level[offset_0] = Dcache_store_data_0.byte_level[0];
                HALF:    updated_line_0.half_level[offset_0[OFFSET_BITS-1:1]] = Dcache_store_data_0.half_level[0];
                WORD:    updated_line_0.word_level[offset_0[OFFSET_BITS-1:2]] = Dcache_store_data_0.word_level[0];
                DOUBLE:  updated_line_0.dbbl_level = Dcache_store_data_0.dbbl_level;
                default: updated_line_0.dbbl_level = Dcache_store_data_0.dbbl_level;
            endcase
        end

        if (store_cache_hit_1) begin
            unique case (Dcache_size_1)
                BYTE:    updated_line_1.byte_level[offset_1] = Dcache_store_data_1.byte_level[0];
                HALF:    updated_line_1.half_level[offset_1[OFFSET_BITS-1:1]] = Dcache_store_data_1.half_level[0];
                WORD:    updated_line_1.word_level[offset_1[OFFSET_BITS-1:2]] = Dcache_store_data_1.word_level[0];
                DOUBLE:  updated_line_1.dbbl_level = Dcache_store_data_1.dbbl_level;
                default: updated_line_1.dbbl_level = Dcache_store_data_1.dbbl_level;
            endcase
        end

        // store the updated line we write
        cache_write_data_hit_0 = updated_line_0;
        cache_write_data_hit_1 = updated_line_1;
    end

    // ----------  Cache Miss Path ----------     
    // 0/1 here is from REQUEST
    logic miss_0, miss_1;
    logic send_miss_0, send_miss_1;
    logic has_req_to_mem;
    logic [$clog2(CACHE_WAYS)-1:0] replace_way_0, replace_way_1;
    logic mshr_hit_0, mshr_hit_1;
    logic mshr_found;

    assign miss_0       = req_0_accept && !cache_hit_0; //req_0_accept contains !mem_none
    assign miss_1       = req_1_accept && !cache_hit_1;
    assign send_miss_0  = miss_0;
    assign send_miss_1  = !miss_0 && miss_1;  // request_0 go first
    assign has_req_to_mem = send_miss_0 || send_miss_1;

    assign Dcache_req_1_accept = req_1_accept && !(miss_0 && miss_1) && !mshr_hit_1 && (cache_hit_1 || mshr_found); // if request 0 and 1 both miss, give up request 1
    assign Dcache_req_0_accept = req_0_accept && !mshr_hit_0 && (cache_hit_0 || mshr_found); // has free bank && not already in mshr && mshr not full

    // ---------- MSHR for Non-Blocking ----------   
    typedef struct packed {
        logic valid;
        logic [TAG_BITS-1:0] tag;
        logic [INDEX_BITS-1:0] index;
        logic [BANK_BITS-1:0] bank;
        logic [$clog2(CACHE_WAYS)-1:0] way;
        logic [OFFSET_BITS-1:0] offset;
        MEM_COMMAND command;
        MEM_SIZE size;
        MEM_BLOCK store_data;
        // logic [3:0] request_id;
        MEM_TAG     mem_tag; 
        logic [`LQ_IDX_WIDTH-1:0] Dcache_req_tag;
        // logic victim_hit;  // Request went to victim cache
    } mshr_entry_t;

    mshr_entry_t mshr [MSHR_SIZE-1:0];
    logic [MSHR_SIZE-1:0] mshr_valid;

    // ---------- Signals for Allocate MSHR ----------   
    logic [$clog2(MSHR_SIZE)-1:0] pending_mshr_id;
    logic pending_req_to_mem;
    
    logic send_new_mem_req; // have req to memory & has MSHR entry
    int free_mshr_idx;
    

    // ----------  LRU logic ----------  
    //### LRU update at hit ###//
    // Find the replacement way
    always_comb begin : LRU
        int max_val_0 = -1;
        int max_val_1 = -1;
        replace_way_0 = '0;
        replace_way_1 = '0;

        // Req 0
        // First find invalid
        if (!(&cache_valid[bank_0][index_0])) begin
            for (int w1 = 0; w1 <CACHE_WAYS; w1++) begin
                if (!cache_valid[bank_0][index_0][w1]) begin
                    replace_way_0 = w1;
                    break;
                end
            end
        end else begin
            // If no invalid, find the oldest
            for (int w = 0; w <CACHE_WAYS; w++) begin
                if (lru_bits[bank_0][index_0][w] > max_val_0) begin
                    replace_way_0 = w;
                    max_val_0 = lru_bits[bank_0][index_0][w];
                end
            end
        end

        // Req 1
        // First find invalid
        if (!(&cache_valid[bank_1][index_1])) begin
            for (int w3 = 0; w3 <CACHE_WAYS; w3++) begin
                if (!cache_valid[bank_1][index_1][w3]) begin
                    replace_way_1 = w3;
                    break;
                end
            end
        end else begin
            // If no invalid, find the oldest
            for (int w2 = 0; w2 <CACHE_WAYS; w2++) begin
                if (lru_bits[bank_1][index_1][w2] > max_val_1) begin
                    replace_way_1 = w2;
                    max_val_1 = lru_bits[bank_1][index_1][w2];
                end
            end
        end
    end

    // Update LRU Bits
    // ### only update when cache hit ###//
    always_ff @(posedge clock or posedge reset) begin : update_LRU
        if (reset) begin
            for (int b = 0; b < BANKS; b++) begin
                for (int s = 0; s < SETS_PER_BANK; s++) begin
                    for (int w = 0; w < CACHE_WAYS; w++) begin
                        lru_bits[b][s][w] <= '0;   
                    end
                end
            end
        end else begin
            // cpu reauest 0
            if (cache_hit_0 && Dcache_req_0_accept) begin
                int b0   = bank_0;
                int s0   = index_0;
                int w0   = hit_way_0;
                logic [$clog2(CACHE_WAYS)-1:0] old = lru_bits[b0][s0][w0];

                for (int w = 0; w < CACHE_WAYS; w++) begin
                    if (w == w0) begin
                        lru_bits[b0][s0][w] <= '0;
                    end else if (lru_bits[b0][s0][w] < old) begin
                        lru_bits[b0][s0][w] <= lru_bits[b0][s0][w] + 1'b1;
                    end
                end
            end
            // cpu reauest 1
            if (cache_hit_1 && Dcache_req_1_accept) begin
                int b1   = bank_1;
                int s1   = index_1;
                int w1   = hit_way_1;
                logic [$clog2(CACHE_WAYS)-1:0] old1 = lru_bits[b1][s1][w1];

                for (int w11 = 0; w11 < CACHE_WAYS; w11++) begin
                    if (w11 == w1) begin
                        lru_bits[b1][s1][w11] <= '0;
                    end else if (lru_bits[b1][s1][w11] < old1) begin
                        lru_bits[b1][s1][w11] <= lru_bits[b1][s1][w11] + 1'b1;
                    end
                end
            end
        end
    end

    // ----------  MSHR logic -------------------------  
    // Find empty MSHR
    always_comb begin
        mshr_found    = 0;
        free_mshr_idx = 0;
        for (int i = MSHR_SIZE -1; i >=0; i--) begin
            if (!mshr[i].valid && !mshr_found) begin
                mshr_found    = 1;
                free_mshr_idx = i;
            end
        end
    end

    assign send_new_mem_req = has_req_to_mem && mshr_found;

    // Find refill MSHR id (when data tag comes back from memory)
    //### Handle the case that transaction tag and data tag come back at the same cycle ###//
    int refill_mshr_id;
    logic refill_enable;
    always_comb begin : blockName
        refill_mshr_id =  0;
        refill_enable = 0;
        if (mem2proc_data_tag != 0) begin
            if ((mem2proc_transaction_tag == mem2proc_data_tag)) begin
                refill_mshr_id = pending_mshr_id;   
                refill_enable = 1;
            end else begin
                for (int i = 0; i < MSHR_SIZE; i++) begin
                    if (mshr[i].valid && (mshr[i].mem_tag == mem2proc_data_tag)) begin
                        refill_mshr_id = i;
                        refill_enable = 1;
                    end
                end
            end 
        end
    end

    // Allocate to the MSHR 
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            // Record #MSHR that was used
            pending_mshr_id <= '0;
            pending_req_to_mem <= 0;


            // Allocate to the MSHR
            for (int i = 0; i < MSHR_SIZE; i++) begin
                mshr[i].valid   <= 0;
                mshr[i].mem_tag <= '0;
            end

            // initial helper tags array
            for (int b = 0; b < BANKS; b++) begin
                for (int s = 0; s < SETS_PER_BANK; s++) begin
                    cache_valid[b][s] <= '0;
                    cache_dirty[b][s] <= '0;
                    for (int w2 = 0; w2 < CACHE_WAYS; w2++) begin
                        cache_tags[b][s][w2] <= '0;
                    end
                end
            end
        end else begin
            // ---------- Record #MSHR that was used & Allocate to the MSHR ---------- 
            if (send_new_mem_req && !pending_req_to_mem) begin
                // Record #MSHR
                pending_mshr_id <= free_mshr_idx;
                pending_req_to_mem <= 1;
                // Allocate to the MSHR
                mshr[free_mshr_idx].valid  <= 1;
                mshr[free_mshr_idx].tag    <= (send_miss_0 ? tag_0   : tag_1);
                mshr[free_mshr_idx].index  <= (send_miss_0 ? index_0 : index_1);
                mshr[free_mshr_idx].bank   <= (send_miss_0 ? bank_0  : bank_1);
                mshr[free_mshr_idx].way    <= (send_miss_0 ? replace_way_0 : replace_way_1); //lru
                mshr[free_mshr_idx].command<= (send_miss_0 ? Dcache_command_0 : Dcache_command_1);
                mshr[free_mshr_idx].offset  <= (send_miss_0 ? offset_0         : offset_1);
                mshr[free_mshr_idx].size   <= (send_miss_0 ? Dcache_size_0    : Dcache_size_1);
                mshr[free_mshr_idx].store_data <= (send_miss_0 ? Dcache_store_data_0    : Dcache_store_data_1);
                mshr[free_mshr_idx].mem_tag <= '0;   
                mshr[free_mshr_idx].Dcache_req_tag <= Dcache_req_tag; 
            end  

            // ---------- Get tag/result from mem ---------- 
            // Get Tag from memory (save to MSHR & clear pending bit)
            if (mem2proc_transaction_tag != 0 && pending_req_to_mem) begin
                // $display("tag = %d | ",mem2proc_transaction_tag);
                mshr[pending_mshr_id].mem_tag <= mem2proc_transaction_tag;
                pending_req_to_mem <= 0;
                pending_mshr_id <= 0;
            end

            //  Get Result from memory => update cache state
            if (mem2proc_data_tag != 0 && refill_enable) begin
                // update cache tags and clear mshr entry
                cache_tags [mshr[refill_mshr_id].bank][mshr[refill_mshr_id].index][mshr[refill_mshr_id].way]  <= mshr[refill_mshr_id].tag;
                cache_valid[mshr[refill_mshr_id].bank][mshr[refill_mshr_id].index][mshr[refill_mshr_id].way]  <= 1'b1;
                // Store only store in cache not memory so dirty bit = 1
                cache_dirty[mshr[refill_mshr_id].bank][mshr[refill_mshr_id].index][mshr[refill_mshr_id].way]  <= (mshr[refill_mshr_id].command == MEM_STORE);
                mshr[refill_mshr_id].valid <= 1'b0; 

                // ---------- Write Dirty Bit ---------- 
                if (mshr[refill_mshr_id].command == MEM_STORE) cache_dirty[mshr[refill_mshr_id].bank][mshr[refill_mshr_id].index][mshr[refill_mshr_id].way] <= 1'b1;
            end

            // ---------- Write Dirty Bit ---------- (store cache hit)
            if (store_cache_hit_0) begin
                cache_dirty[bank_0][index_0][hit_way_0] <= 1'b1;
            end
            if (store_cache_hit_1) begin
                cache_dirty[bank_1][index_1][hit_way_1] <= 1'b1;
            end
        end
    end

    //  Get Result from memory => update cache data with received data
    always_comb begin 
        cache_write_en_refill_0 ='0;
        cache_write_en_refill_1 ='0;
        cache_write_addr_refill_0 = '0;
        cache_write_addr_refill_1 = '0;
        cache_write_data_refill_0 = '0;
        cache_write_data_refill_1 = '0;
        if (mem2proc_data_tag != 0 && mshr[refill_mshr_id].valid ) begin
            MEM_BLOCK fill_data;
            fill_data = mem2proc_data;

            // If store, first store data in and fill back to cache; If load, just fill back to cache
            if (mshr[refill_mshr_id].command == MEM_STORE) begin
                unique case (mshr[refill_mshr_id].size) 
                    BYTE:    fill_data.byte_level[mshr[refill_mshr_id].offset] = mshr[refill_mshr_id].store_data.byte_level[0];
                    HALF:    fill_data.half_level[mshr[refill_mshr_id].offset[OFFSET_BITS-1:1]] =  mshr[refill_mshr_id].store_data.half_level[0];
                    WORD:    fill_data.word_level[mshr[refill_mshr_id].offset[OFFSET_BITS-1:2]] = mshr[refill_mshr_id].store_data.word_level[0];
                    DOUBLE:  fill_data.dbbl_level = mshr[refill_mshr_id].store_data.dbbl_level;
                endcase
            end
    
            if (mshr[refill_mshr_id].bank == 1'b0) begin
                cache_write_addr_refill_0  = mshr[refill_mshr_id].index;
                cache_write_data_refill_0  = fill_data;
                cache_write_en_refill_0[mshr[refill_mshr_id].way] = 1'b1;
            end else begin
                cache_write_addr_refill_1 = mshr[refill_mshr_id].index;
                cache_write_data_refill_1  = fill_data;
                cache_write_en_refill_1[mshr[refill_mshr_id].way] = 1'b1;
            end
        end
    end

    // ---------- Send signal to the memory ------------------
    always_comb begin : signal_to_mem
        // default
        Dcache2mem_command = MEM_NONE;
        Dcache2mem_addr    = '0;
        Dcache2mem_size    = BYTE;  
        Dcache2mem_data    = '0;

        if (send_new_mem_req) begin
            if (send_miss_0) begin
                Dcache2mem_addr = {tag_0, index_0, bank_0, {OFFSET_BITS{1'b0}}};
            end else begin // send_miss_1
                Dcache2mem_addr = {tag_1, index_1, bank_1, {OFFSET_BITS{1'b0}}};
            end
            
            Dcache2mem_command = MEM_LOAD; // load back first (nomatter is load or store)
            Dcache2mem_size = DOUBLE;  // MEM_BLOCK = 8 bytes
            Dcache2mem_data = '0;      // TODO: READ ONLY NOW
        end
    end

    // ---------- MSHR Conflict ------------------
    //### Handle the situation that cpu sent request that is waiting inside the MSHR ###//
    always_comb begin
        mshr_hit_0 = 1'b0;
        mshr_hit_1 = 1'b0;
        for (int i = 0; i < MSHR_SIZE; i++) begin
            if (Dcache_command_0 != MEM_NONE &&
                mshr[i].valid &&
                mshr[i].tag   == tag_0   &&
                mshr[i].index == index_0 &&
                mshr[i].bank  == bank_0) begin
                mshr_hit_0 = 1'b1;
            end
            if (Dcache_command_1 != MEM_NONE && 
                mshr[i].valid &&    
                mshr[i].tag   == tag_1   &&
                mshr[i].index == index_1 &&
                mshr[i].bank  == bank_1) begin
                mshr_hit_1 = 1'b1;
            end
        end
    end


 task automatic show_status_old(); 
 $display("-------------------------------------------------------------------");
 $display("Dcache_command_0 = %p Accept0=[%0b%0b%0b] valid0=%0d dat0=%h | Dcache_command_1 = %p accept1=%0d valid1=%0d dat1=%h",
             Dcache_command_0, Dcache_req_0_accept,req_0_accept, mshr_hit_0, Dcache_valid_out_0, Dcache_data_out_0.dbbl_level, Dcache_command_1, Dcache_req_1_accept, Dcache_valid_out_1, Dcache_data_out_1.dbbl_level);
  $display("req_to_bank=[%b%b%b%b]", req_0_to_bank_0,req_0_to_bank_1,req_1_to_bank_0,req_1_to_bank_1 );
  
  $write("way_hit_0= ");
  for (int w = 0; w < CACHE_WAYS; w++) begin 
    $write("%b", way_hit_0[w]);
  end
  $display(" ");
  $write("way_hit_1= ");
  for (int w = 0; w < CACHE_WAYS; w++) begin
    $write("%b", way_hit_1[w]);
  end

  $display("cache_hit_0=%b, cache_hit_1=%b", cache_hit_0,cache_hit_1);

  
  $display(" ");
  $display("send_new_mem_req=%b |free_mshr_idx=%0d |pending_mshr_id=%d | pending_req_to_mem=%b", send_new_mem_req,free_mshr_idx,pending_mshr_id,pending_req_to_mem);

  for (int i = 0; i < MSHR_SIZE; i++) begin
    if (mshr[i].valid) begin
      $display("mashr[%0d] mem tag = %d", i, mshr[i].mem_tag);
    end
  end

  $display("memory response: tag=%d | data=%d | data_tag =%d",mem2proc_transaction_tag,mem2proc_data,mem2proc_data_tag );
   $display("Dcache_command_0 = %p Accept0=[%0b%0b%0b] valid0=%0d dat0=%h | Dcache_command_1 = %p accept1=%0d valid1=%0d dat1=%h",
             Dcache_command_0, Dcache_req_0_accept,req_0_accept, mshr_hit_0, Dcache_valid_out_0, Dcache_data_out_0.dbbl_level, Dcache_command_1, Dcache_req_1_accept, Dcache_valid_out_1, Dcache_data_out_1.dbbl_level);
 $display("-------------------------------------------------------------------");
 endtask 

task automatic show_status();
    $display("===================================================================");
    $display("D-Cache Status @ time %0t", $time);

    // =================================================================
    // Request 0 Pipeline  (Req0 -> Bank -> Hit/Miss -> MSHR -> Mem)
    // =================================================================
    $display("== Request 0 ======================================================");
    $display("[REQ0] cmd=%s size=%s addr=%h store_data=%h tag(LQ)=%0d",
             Dcache_command_0.name(), Dcache_size_0.name(),
             Dcache_addr_0, Dcache_store_data_0.dbbl_level, Dcache_req_tag);
    $display("[REQ0] bank=%0d index=%0d offset=%0d",
             bank_0, index_0, offset_0);

    // bank routing / accept
    $display("[REQ0] to_bank0=%b to_bank1=%b  req_0_accept=%b  Dcache_req_0_accept=%b",
             req_0_to_bank_0, req_0_to_bank_1,
             req_0_accept, Dcache_req_0_accept);

    // hit / miss / mshr
    $display("[REQ0] way_hit=%b  hit_way=%0d  cache_hit=%b  load_hit=%b  store_hit=%b",
             way_hit_0, hit_way_0, cache_hit_0, load_cache_hit_0, store_cache_hit_0);
    $display("[REQ0] miss=%b  mshr_hit=%b",
             miss_0, mshr_hit_0);

    // data out / valid
    $display("[REQ0] valid_out=%b  data_out=%h  load_tag=%0d",
             Dcache_valid_out_0, Dcache_data_out_0.dbbl_level, Dcache_load_tag);

    // =================================================================
    // Request 1 Pipeline  (Req1 -> Bank -> Hit/Miss -> MSHR -> Mem)
    // =================================================================
    $display("== Request 1 ======================================================");
    $display("[REQ1] cmd=%s size=%s addr=%h store_data=%h",
             Dcache_command_1.name(), Dcache_size_1.name(),
             Dcache_addr_1, Dcache_store_data_1.dbbl_level);
    $display("[REQ1] bank=%0d index=%0d offset=%0d",
             bank_1, index_1, offset_1);

    $display("[REQ1] to_bank0=%b to_bank1=%b  req_1_accept=%b  Dcache_req_1_accept=%b",
             req_1_to_bank_0, req_1_to_bank_1,
             req_1_accept, Dcache_req_1_accept);

    $display("[REQ1] way_hit=%b  hit_way=%0d  cache_hit=%b  load_hit=%b  store_hit=%b",
             way_hit_1, hit_way_1, cache_hit_1, load_cache_hit_1, store_cache_hit_1);
    $display("[REQ1] miss=%b  mshr_hit=%b",
             miss_1, mshr_hit_1);

    $display("[REQ1] valid_out=%b  data_out=%h",
             Dcache_valid_out_1, Dcache_data_out_1.dbbl_level);

    // =================================================================
    // Bank / Cache Array Control
    // =================================================================
    $display("== Bank / Cache Control ===========================================");
    $display("[BANK] req_to_bank = {req0->b0,b1, req1->b0,b1} = %b%b%b%b",
             req_0_to_bank_0, req_0_to_bank_1, req_1_to_bank_0, req_1_to_bank_1);
    $display("[BANK] has_req_to_mem=%b  send_miss_0=%b  send_miss_1=%b",
             has_req_to_mem, send_miss_0, send_miss_1);

    // read path
    $display("[READ]  en={b0,b1} = %b %b  addr={b0,b1} = %0d %0d",
             cache_read_en_0, cache_read_en_1,
             cache_read_addr_0, cache_read_addr_1);

    // write path
    $display("[WRITE] hit_en_0=%b  refill_en_0=%b  final_we_0=%b  waddr_0=%0d",
             cache_write_en_hit_0, cache_write_en_refill_0,
             cache_write_en_0, cache_write_addr_0);
    $display("[WRITE] hit_en_1=%b  refill_en_1=%b  final_we_1=%b  waddr_1=%0d",
             cache_write_en_hit_1, cache_write_en_refill_1,
             cache_write_en_1, cache_write_addr_1);

    // =================================================================
    // MSHR / Miss Handling
    // =================================================================
    $display("== MSHR / Miss Handling ===========================================");
    $display("[MSHR] send_new_mem_req=%b  mshr_found=%b  free_mshr_idx=%0d",
             send_new_mem_req, mshr_found, free_mshr_idx);
    $display("[MSHR] pending_mshr_id=%0d  pending_req_to_mem=%b",
             pending_mshr_id, pending_req_to_mem);
    $display("[MSHR] miss_0=%b miss_1=%b  has_req_to_mem=%b",
             miss_0, miss_1, has_req_to_mem);

    // 列出所有有效 MSHR entry
    for (int i = 0; i < MSHR_SIZE; i++) begin
            $display("[MSHR[%0d]] valid=%b tag=%h idx=%0d bank=%0d way=%0d cmd=%s size=%s",
                     i,
                     mshr[i].valid, mshr[i].tag, mshr[i].index, mshr[i].bank,
                     mshr[i].way,
                     mshr[i].command.name(), mshr[i].size.name());
            $display("           offset=%0d  mem_tag=%0d  LQ_tag=%0d  store_data=%h",
                     mshr[i].offset,
                     mshr[i].mem_tag,
                     mshr[i].Dcache_req_tag,
                     mshr[i].store_data.dbbl_level);
        end

    // =================================================================
    // Full Cache Contents (per bank / set / way)
    // =================================================================
    $display("== Cache Contents (tags / valid / dirty / LRU) =====================");
    for (int b = 0; b < BANKS; b++) begin
        for (int s = 0; s < SETS_PER_BANK; s++) begin
            // Summary line of valid/dirty bits for this set
            $write("[BANK%0d SET%0d] valid=", b, s);
            for (int w = 0; w < CACHE_WAYS; w++) begin
                $write("%b", cache_valid[b][s][w]);
            end
            $write(" dirty=");
            for (int w = 0; w < CACHE_WAYS; w++) begin
                $write("%b", cache_dirty[b][s][w]);
            end
            $display("");

            // Per-way detail: tag and LRU
            for (int w = 0; w < CACHE_WAYS; w++) begin
                $write("    way%0d: tag=%h  LRU=%0d", w,
                         cache_tags[b][s][w], lru_bits[b][s][w]);
            end

        end
    end
    


    // =================================================================
    // Memory Interface
    // =================================================================
    $display("== Memory Interface ===============================================");
    $display("[TO  MEM] cmd=%s addr=%h size=%s data=%h",
             Dcache2mem_command.name(), Dcache2mem_addr,
             Dcache2mem_size.name(), Dcache2mem_data.dbbl_level);
    $display("[FROM MEM] trans_tag=%0d  data_tag=%0d  data=%h",
             mem2proc_transaction_tag, mem2proc_data_tag, mem2proc_data.dbbl_level);

    $display("===================================================================");
endtask


always_ff @(negedge clock) begin
    if (!reset) begin
        show_status();
    end
end

endmodule