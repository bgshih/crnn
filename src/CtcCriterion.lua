local CtcCriterion, parent = torch.class('nn.CtcCriterion', 'nn.Criterion')

function CtcCriterion:__init()
    parent.__init(self)
end


function CtcCriterion:forward(input, target, forwardOnly)
    forwardOnly = forwardOnly or false
    return self:updateOutput(input, target, forwardOnly)
end


function CtcCriterion:updateOutput(input, target, forwardOnly)
    forwardOnly = forwardOnly or false
    assert(input:dim() == 3 and input:isContiguous())
    assert(target:dim() == 2)
    local losses = input.nn.CTC_forwardBackward(input, target, forwardOnly, self.gradInput)
    self.output = losses:sum()
    return self.output
end


function CtcCriterion:updateGradInput(input, target)
    return self.gradInput
end
