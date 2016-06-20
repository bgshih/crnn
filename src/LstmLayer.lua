function makeLstmUnit(nIn, nHidden, dropout)
    --[[ Create LSTM unit, adapted from https://github.com/karpathy/char-rnn/blob/master/model/LSTM.lua
    ARGS:
      - `nIn`      : integer, number of input dimensions
      - `nHidden`  : integer, number of hidden nodes
      - `dropout`  : boolean, if true apply dropout
    RETURNS:
      - `lstmUnit` : constructed LSTM unit (nngraph module)
    ]]
    dropout = dropout or 0

    -- there will 3 inputs: x (input), prev_c, prev_h
    local x, prev_c, prev_h = nn.Identity()(), nn.Identity()(), nn.Identity()()
    local inputs = {x, prev_c, prev_h}

    -- Construct the unit structure
    -- apply dropout, if any
    if dropout > 0 then x = nn.Dropout(dropout)(x) end
    -- evaluate the input sums at once for efficiency
    local i2h            = nn.Linear(nIn,     4*nHidden)(x)
    local h2h            = nn.Linear(nHidden, 4*nHidden)(prev_h)
    local all_input_sums = nn.CAddTable()({i2h, h2h})
    -- decode the gates
    local sigmoid_chunk  = nn.Narrow(2, 1, 3*nHidden)(all_input_sums)
    sigmoid_chunk        = nn.Sigmoid()(sigmoid_chunk)
    local in_gate        = nn.Narrow(2,           1, nHidden)(sigmoid_chunk)
    local forget_gate    = nn.Narrow(2,   nHidden+1, nHidden)(sigmoid_chunk)
    local out_gate       = nn.Narrow(2, 2*nHidden+1, nHidden)(sigmoid_chunk)
    -- decode the write inputs
    local in_transform   = nn.Narrow(2, 3*nHidden+1, nHidden)(all_input_sums)
    in_transform         = nn.Tanh()(in_transform)
    -- perform the LSTM update
    local next_c         = nn.CAddTable()({
                               nn.CMulTable()({forget_gate, prev_c}),
                               nn.CMulTable()({in_gate    , in_transform})
                               })
    -- gated cells from the output
    local next_h         = nn.CMulTable()({out_gate, nn.Tanh()(next_c)})
    -- y (output)
    local y              = nn.Identity()(next_h)

    -- there will be 3 outputs
    local outputs = {next_c, next_h, y}

    local lstmUnit = nn.gModule(inputs, outputs)
    return lstmUnit
end


local LstmLayer, parent = torch.class('nn.LstmLayer', 'nn.Module')


function LstmLayer:__init(nIn, nHidden, maxT, dropout, reverse)
    --[[
    ARGS:
      - `nIn`     : integer, number of input dimensions
      - `nHidden` : integer, number of hidden nodes
      - `maxT`    : integer, maximum length of input sequence
      - `dropout` : boolean, if true apply dropout
      - `reverse` : boolean, if true the sequence is traversed from the end to the start
    ]]
    parent.__init(self)

    self.dropout = dropout or 0
    self.reverse = reverse or false
    self.nHidden = nHidden
    self.maxT    = maxT

    self.output    = {}
    self.gradInput = {}

    -- LSTM unit and clones
    self.lstmUnit = makeLstmUnit(nIn, nHidden, self.dropout)
    self.clones   = {}

    -- LSTM states
    self.initState = {torch.CudaTensor(), torch.CudaTensor()} -- c, h

    self:reset()
end


function LstmLayer:reset(stdv)
    local params, _ = self:parameters()
    for i = 1, #params do
        if i % 2 == 1 then -- weight
            params[i]:uniform(-0.08, 0.08)
        else -- bias
            params[i]:zero()
        end
    end
end


function LstmLayer:type(type)
    assert(#self.clones == 0, 'Function type() should not be called after cloning.')
    self.lstmUnit:type(type)
    return self
end


function LstmLayer:parameters()
    return self.lstmUnit:parameters()
end


function LstmLayer:training()
    self.train = true
    self.lstmUnit:training()
    for t = 1, #self.clones do self.clones[t]:training() end
end


function LstmLayer:evaluate()
    self.train = false
    self.lstmUnit:evaluate()
    for t = 1, #self.clones do self.clones[t]:evaluate() end
end


function LstmLayer:updateOutput(input)
    assert(type(input) == 'table')
    self.output = {}
    local T = #input
    local batchSize = input[1]:size(1)
    self.initState[1]:resize(batchSize, self.nHidden):fill(0)
    self.initState[2]:resize(batchSize, self.nHidden):fill(0)
    if #self.clones == 0 then
        self.clones = cloneManyTimes(self.lstmUnit, self.maxT)
    end

    if not self.reverse then
        self.rnnState = {[0] = cloneList(self.initState, true)}
        for t = 1, T do
            local lst
            if self.train then
                lst = self.clones[t]:forward({input[t], unpack(self.rnnState[t-1])})
            else
                lst = self.lstmUnit:forward({input[t], unpack(self.rnnState[t-1])})
                lst = cloneList(lst)
            end
            self.rnnState[t] = {lst[1], lst[2]} -- next_c, next_h
            self.output[t] = lst[3]
        end
    else
        self.rnnState = {[T+1] = cloneList(self.initState, true)}
        for t = T, 1, -1 do
            local lst
            if self.train then
                lst = self.clones[t]:forward({input[t], unpack(self.rnnState[t+1])})
            else
                lst = self.lstmUnit:forward({input[t], unpack(self.rnnState[t+1])})
                lst = cloneList(lst)
            end
            self.rnnState[t] = {lst[1], lst[2]}
            self.output[t] = lst[3]
        end
    end
    return self.output
end


function LstmLayer:updateGradInput(input, gradOutput)
    assert(#input == #gradOutput)
    local T = #input
    self.gradInput = {}

    if not self.reverse then
        self.drnnState = {[T] = cloneList(self.initState, true)} -- zero gradient for the last frame
        for t = T, 1, -1 do
            local doutput_t = gradOutput[t]
            table.insert(self.drnnState[t], doutput_t) -- dnext_c, dnext_h, doutput_t
            local dlst = self.clones[t]:updateGradInput({input[t], unpack(self.rnnState[t-1])}, self.drnnState[t]) -- dx, dprev_c, dprev_h
            self.drnnState[t-1] = {dlst[2], dlst[3]}
            self.gradInput[t] = dlst[1]
        end
    else
        self.drnnState = {[1] = cloneList(self.initState, true)}
        for t = 1, T do
            local doutput_t = gradOutput[t]
            table.insert(self.drnnState[t], doutput_t)
            local dlst = self.clones[t]:updateGradInput({input[t], unpack(self.rnnState[t+1])}, self.drnnState[t])
            self.drnnState[t+1] = {dlst[2], dlst[3]}
            self.gradInput[t] = dlst[1]
        end
    end
    
    return self.gradInput
end


function LstmLayer:accGradParameters(input, gradOutput, scale)
    local T = #input
    if not self.reverse then
        for t = 1, T do
            self.clones[t]:accGradParameters({input[t], unpack(self.rnnState[t-1])}, self.drnnState[t], scale)
        end
    else
        for t = T, 1, -1 do
            self.clones[t]:accGradParameters({input[t], unpack(self.rnnState[t+1])}, self.drnnState[t], scale)
        end
    end
end
