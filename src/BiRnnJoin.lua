function makeBiRnnJoinUnit(nIn, nOut)
    local fwdX, bwdX = nn.Identity()(), nn.Identity()()
    local inputs = {fwdX, bwdX}

    local fwdProj = nn.Linear(nIn, nOut)(fwdX)
    local bwdProj = nn.Linear(nIn, nOut)(bwdX)

    local output = nn.CAddTable()({fwdProj, bwdProj})
    local outputs = {output}

    return nn.gModule(inputs, outputs)
end


local BiRnnJoin, parent = torch.class('nn.BiRnnJoin', 'nn.Module')


function BiRnnJoin:__init(nIn, nOut, maxT)
    parent.__init(self)

    self.maxT = maxT
    self.output = {}
    self.gradInput = {}
    self.joinUnit = makeBiRnnJoinUnit(nIn, nOut)
    self.clones = {}
    self:reset()
end


function BiRnnJoin:type(type)
    assert(#self.clones == 0, 'Function type() should not be called after cloning.')
    self.joinUnit:type(type)
    return self
end


function BiRnnJoin:reset(stdv)
    local params, _ = self:parameters()
    for i = 1, #params do
        if i % 2 == 1 then
            params[i]:uniform(-0.08, 0.08)
        else
            params[i]:zero()
        end
    end
end


function BiRnnJoin:parameters()
    return self.joinUnit:parameters()
end


function BiRnnJoin:updateOutput(input)
    assert(type(input) == 'table' and #input == 2)
    assert(#(input[1]) == #(input[2]))

    if #self.clones == 0 then
        self.clones = cloneManyTimes(self.joinUnit, self.maxT)
    end

    self.output = {}
    local fwdInput, bwdInput = input[1], input[2]
    local T = #fwdInput
    for t = 1, T do
        if self.train then
            self.output[t] = self.clones[t]:updateOutput({fwdInput[t], bwdInput[t]})
        else
            self.output[t] = self.joinUnit:updateOutput({fwdInput[t], bwdInput[t]}):clone()
        end
    end
    return self.output
end


function BiRnnJoin:updateGradInput(input, gradOutput)
    assert(type(gradOutput) == 'table')

    self.gradInput[1] = {}
    self.gradInput[2] = {}

    local fwdInput, bwdInput = input[1], input[2]
    local T = #fwdInput
    for t = 1, T do
        local g = self.clones[t]:updateGradInput({fwdInput[t], bwdInput[t]}, gradOutput[t])
        self.gradInput[1][t] = g[1]
        self.gradInput[2][t] = g[2]
    end
    return self.gradInput
end


function BiRnnJoin:accGradParameters(input, gradOutput, scale)
    local fwdInput, bwdInput = input[1], input[2]
    local T = #fwdInput
    for t = 1, T do
        self.clones[t]:accGradParameters({fwdInput[t], bwdInput[t]}, gradOutput[t], scale)
    end
end
