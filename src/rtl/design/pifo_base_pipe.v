//------------------------------------------------------------------------------
// pifo_base maintains a sorted list of elements, 0 ... NUM_ELEMENTS
// 0 ----> lowest priority element
// It returns the highest priority element when queried
// eg: This is a valid state of the pifo_buffer 
// Index    0   1   2   3   4   5   6   7   8   9
// Priority 10  22  34  47  234 237 x   x   x   x
// In this state, when queried, pifo_buffer[5] (ie. prio 237) will
// be returned.
//------------------------------------------------------------------------------
module pifo_base_pipe (
    //--------------------------------------------------------------------------
    // Global signals
    //--------------------------------------------------------------------------
    clk,
    reset,

    //--------------------------------------------------------------------------
    // Input interface
    //--------------------------------------------------------------------------
    i__data_in_valid,           // assert true, if you want to enqueue
    i__data_in_priority,
    i__data_in,
    o__data_in_ready,           // true, if pifo is not full: safe to enqueue
    o__data_in_ready__next,     // [ssub]  Remove if unnecessary, but I think it may be useful

    //--------------------------------------------------------------------------
    // Output interface
    //--------------------------------------------------------------------------
    o__data_out_valid,          // true, if pifo is not empty ie. valid packet available for dequeue
    o__data_out_priority,
    o__data_out,
    i__data_out_ready,          // assert true, if you want to dequeue
    i__clear_all                // clear pifo
);

//------------------------------------------------------------------------------
// Parameters
//------------------------------------------------------------------------------
parameter   NUM_ELEMENTS    = (16);
parameter   MAX_PRIORITY    = (256);
parameter   DATA_WIDTH      = (8);

//------------------------------------------------------------------------------
// Constants
//------------------------------------------------------------------------------
localparam  PRIO_WIDTH      = $clog2(MAX_PRIORITY);
localparam  IDX_WIDTH       = $clog2(NUM_ELEMENTS+1);


//------------------------------------------------------------------------------
// Local data structure
//------------------------------------------------------------------------------
typedef struct {
	logic [DATA_WIDTH-1:0]  data;
	logic [PRIO_WIDTH-1:0]  prio;
} PifoEntry;

//------------------------------------------------------------------------------
// Global signals
//------------------------------------------------------------------------------
input  logic                        clk;
input  logic                        reset;

//------------------------------------------------------------------------------
// Input interface
//------------------------------------------------------------------------------
input  logic                        i__data_in_valid;
input  logic    [PRIO_WIDTH-1:0]    i__data_in_priority;
input  logic    [DATA_WIDTH-1:0]    i__data_in;
output logic                        o__data_in_ready;
output logic                        o__data_in_ready__next;


//------------------------------------------------------------------------------
// Output interface
//------------------------------------------------------------------------------
output logic                        o__data_out_valid;
output logic    [PRIO_WIDTH-1:0]    o__data_out_priority;
output logic    [DATA_WIDTH-1:0]    o__data_out;
input  logic                        i__data_out_ready;
input  logic                        i__clear_all;

//------------------------------------------------------------------------------
// Signals
//------------------------------------------------------------------------------
logic                               w__push;
logic                               w__pop;
logic           [IDX_WIDTH-1:0]     w__enq_idx; 
logic           [NUM_ELEMENTS-1:0]  w__enq_bmp__next; 
logic           [NUM_ELEMENTS-1:0]  r__enq_bmp; 

//------------------------------------------------------------------------------
// States and next signals
//------------------------------------------------------------------------------
logic           [PRIO_WIDTH-1:0]    r__data_in_priority;
logic           [DATA_WIDTH-1:0]    r__data_in;
logic                               r__push;
logic                               r__push__del;
logic           [IDX_WIDTH-1:0]     r__push_idx__del; 
logic           [PRIO_WIDTH-1:0]    r__data_in_priority__del;
logic                               r__pop;
logic                               r__pop__del;
logic                               w__empty__next;
logic                               r__empty__pff;
logic                               w__full__next;
logic                               r__full__pff;
logic           [IDX_WIDTH-1:0]     r__pifo_count__pff;
logic           [IDX_WIDTH-1:0]     w__pifo_count__next; 
logic           [IDX_WIDTH-1:0]     r__pifo_count__del;

PifoEntry                           r__buffer__pff          [NUM_ELEMENTS-1:0];

//------------------------------------------------------------------------------
// Output assignments
//------------------------------------------------------------------------------
assign o__data_in_ready         = ~r__full__pff & (~reset);         // When reset, ready should be low
assign o__data_in_ready__next   = ~w__full__next;
assign o__data_out_valid        = ~r__empty__pff;                   // When reset, this _will_ be low
assign o__data_out              = r__buffer__pff[r__pifo_count__del-1].data;
assign o__data_out_priority     = r__buffer__pff[r__pifo_count__del-1].prio;

//------------------------------------------------------------------------------
// Internal push and pop signals
//------------------------------------------------------------------------------
always_comb
begin
    // [ssub] For now, we assume upto one of these signals can be true in
    // any particular clock cycle, but not both. Bad things will happen 
    // if this assumption is violated.
    w__push = i__data_in_valid && o__data_in_ready;
    w__pop  = o__data_out_valid && i__data_out_ready;
end

//------------------------------------------------------------------------------
// Pifo element count 
//------------------------------------------------------------------------------
always_comb
begin
    w__pifo_count__next = r__pifo_count__pff;
    if (w__push)
    	w__pifo_count__next = r__pifo_count__pff + 1'b1;
    else if (w__pop)
    	w__pifo_count__next = r__pifo_count__pff - 1'b1;
end

always_ff @(posedge clk)
begin
    if ((reset == 1'b1) || (i__clear_all == 1'b1))
    	r__pifo_count__pff <= '0;
    else
        r__pifo_count__pff <= w__pifo_count__next;
end

//------------------------------------------------------------------------------
// Internal full and empty states, signals
//------------------------------------------------------------------------------
always_comb
begin
    w__empty__next  = (w__pifo_count__next == '0);
    w__full__next   = (w__pifo_count__next == NUM_ELEMENTS);
end

always_ff @ (posedge clk)
begin
    if(reset == 1'b1)
    begin
        r__empty__pff   <= 1'b1;
        r__full__pff    <= 1'b0;
    end
    else
    begin
        r__empty__pff   <= w__empty__next;
        r__full__pff    <= w__full__next;
    end
end

//------------------------------------------------------------------------------
// Pifo next state : Core PIFO logic
//------------------------------------------------------------------------------
// Enqueue index computation
always_comb
begin
    w__enq_bmp__next = 0;
    for(integer i = 0; i < NUM_ELEMENTS; i = i + 1)
        if ((i == r__pifo_count__del) || (i__data_in_priority < r__buffer__pff[i].prio))
            w__enq_bmp__next[i] = 1'b1;
end

always_comb
begin
    w__enq_idx = NUM_ELEMENTS;
    for(integer i = NUM_ELEMENTS - 1; i >= 0; i = i - 1)
        if (r__enq_bmp[i])
            w__enq_idx = i;
end

always @(posedge clk)
begin
    r__enq_bmp <= w__enq_bmp__next;
    r__push <= w__push;
    r__pop <= w__pop;
    r__pop__del <= r__pop;
    r__push__del <= r__push;
    r__push_idx__del <= w__enq_idx - (r__pop__del && (w__enq_idx == r__pifo_count__del + 1));
    r__data_in_priority__del <= r__data_in_priority;
    r__data_in <= i__data_in;
    r__data_in_priority <= i__data_in_priority;
    r__pifo_count__del <= r__pifo_count__pff;
end    

genvar pifo_idx;
generate for(pifo_idx = 0; pifo_idx < NUM_ELEMENTS; pifo_idx = pifo_idx + 1) 
begin: gen_pifo_next_state
    PifoEntry   r__buffer__next;
    always_comb
    begin
        if (r__push && (pifo_idx == w__enq_idx - (r__pop__del && (w__enq_idx == r__pifo_count__del + 1)) +
                                                 (r__push__del && (w__enq_idx >= r__push_idx__del) && (r__data_in_priority >= r__data_in_priority__del))))
        begin
          r__buffer__next.data = r__data_in;
          r__buffer__next.prio = r__data_in_priority;
        end
        else if (r__push && (pifo_idx > w__enq_idx))
          r__buffer__next = r__buffer__pff[pifo_idx-1];
        else
          r__buffer__next = r__buffer__pff[pifo_idx];
        // [ssub] For now, either 1 push or 1 pop (or neither) can
        // happen in any particular cycle. If this assumption is violated
        // bad things will happen.
    end

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
        	r__buffer__pff[pifo_idx].data   <= '0;
        	r__buffer__pff[pifo_idx].prio   <= '0;
        end
        else
            r__buffer__pff[pifo_idx]    <= r__buffer__next;
    end
end
endgenerate

/*
integer idx;
always_comb
begin
    w__enq_idx = NUM_ELEMENTS;

    // Check if less than least element
    if (i__data_in_priority < r__buffer__pff[0].prio)
    begin
    	w__enq_idx = '0;
    end
    else
    begin
        w__enq_idx = r__pifo_count__pff-1'b1;
        for(idx = 0; idx < NUM_ELEMENTS; idx = idx + 1)
        	if ((idx < r__pifo_count__pff) && (i__data_in_priority > r__buffer__pff[idx].prio))
        		w__enq_idx = idx;
        w__enq_idx = w__enq_idx + 1'b1;
    end
end

genvar pifo_idx;
generate for(pifo_idx = 0; pifo_idx < NUM_ELEMENTS; pifo_idx = pifo_idx + 1) 
begin: gen_pifo_next_state
    PifoEntry   r__buffer__next;
    always_comb
    begin
        r__buffer__next = r__buffer__pff[pifo_idx];
        if (w__push && !w__pop) 
        begin
            if (pifo_idx > w__enq_idx)
            begin
            	r__buffer__next = r__buffer__pff[pifo_idx - 1];
            end
            else if (pifo_idx == w__enq_idx)
            begin
            	r__buffer__next.data = i__data_in;
            	r__buffer__next.prio = i__data_in_priority;
            end
        end
        // [ssub] For now, either 1 push or 1 pop (or neither) can
        // happen in any particular cycle. If this assumption is violated
        // bad things will happen.
    end

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
        	r__buffer__pff[pifo_idx].data   <= '0;
        	r__buffer__pff[pifo_idx].prio   <= '0;
        end
        else
            r__buffer__pff[pifo_idx]    <= r__buffer__next;
    end
end
endgenerate
*/
endmodule
