function naiveDecoding(input)
    --[[ Naive, lexicon-free decoding
    ARGS:
      - `input`   : float tensor [nFrame x inputLength x nClasses]
    RETURNS:
      - `pred`    : int tensor [nFrame x inputLength]
      - `predRaw` : int tensor [nFrame x inputLength]
    ]]

    assert(input:dim() == 3)
    local nFrame, inputLength = input:size(1), input:size(2)
    local pred, predRaw = input.nn.CTC_naiveDecoding(input)
    return pred, predRaw
end


function decodingWithLexicon(input, lexicon)
    --[[ Decoding by selecting the lexicon word with the highest probability
    ARGS:
      - `input`   : float tensor [nFrame x inputLength x nClasses], model feed forward output
    RETURNS:
      - `pred`    : int tensor [nFrame x inputLength]
      - `predRaw` : int tensor [nFrame x inputLength]
    ]]

    assert(input:dim() == 3 and input:size(1) == 1)
    assert(type(lexicon) == 'table')
    local lexSize = #lexicon

    local target = str2label(lexicon, 30) -- FIXME
    local inputN = torch.repeatTensor(input, lexSize, 1, 1)
    local logProb = -inputN.nn.CTC_forwardBackward(inputN, target, true, inputN.new())
    local _, idx = torch.max(logProb, 1)
    idx = idx[1]
    return lexicon[idx]
end
